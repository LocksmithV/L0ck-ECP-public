/// Laptop test node for L0ck-ECP: a real ECP identity and PACE router with layer P (a
/// simplex-chat CLI's WebSocket server), layer A (Bramble, run as a `bramble-peer` child
/// process) and layer C (a MeshCore companion radio on a USB serial port). Lets the phone
/// app be tested end to end without a second phone.
///
///   dart run bin/ecp_peer.dart STATE_DIR BRAMBLE_PEER_BIN [--echo] [--simplex PORT]
///                              [--lora /dev/ttyUSB0] [--no-bramble] [--lora-key KEY]
///
/// Commands on stdin: card · add <l0ck://c/…> (a team card also joins the team) · contacts ·
/// send <name> <text…> · tsend <text…> (to the first team) · quit
/// With --echo every received text is answered with "echo: <text>" (team texts to the team).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ecp_core/ecp_core.dart';
import 'package:ecp_meshcore/ecp_meshcore.dart';

import 'package:ecp_meshcore/serial.dart';
import 'package:ecp_simplex/ecp_simplex.dart';
import 'package:ecp_simplex/ws.dart';

late PaceRouter router;
late BramblePeer bramble;
SquadTransport? squad;
MeshCoreTransport? loraTransport;
SimplexTransport? simplex;
bool hasBramble = false;
late File stateFile;
late Map<String, dynamic> state;
late EcpIdentity me;
bool echo = false;

void log(String s) => stdout.writeln('${DateTime.now().toIso8601String().substring(11, 19)} $s');

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: ecp_peer STATE_DIR BRAMBLE_PEER_BIN [--echo]');
    exit(2);
  }
  echo = args.contains('--echo');
  final dir = Directory(args[0])..createSync(recursive: true);
  stateFile = File('${dir.path}/state.json');
  if (stateFile.existsSync()) {
    state = jsonDecode(stateFile.readAsStringSync()) as Map<String, dynamic>;
    me = await EcpIdentity.fromPrivateKey(fromHex(state['key'] as String));
  } else {
    me = await EcpIdentity.generate();
    state = {
      'key': toHex(await me.privateKeyBytes()),
      'nick': 'Laptop',
      'password': toHex(randomBytes(32)),
      'contacts': <dynamic>[],
    };
    save();
  }

  final useBramble = !args.contains('--no-bramble');
  final loraAt = args.indexOf('--lora');
  final keyAt = args.indexOf('--lora-key');
  if (useBramble) {
    hasBramble = true;
    bramble = await BramblePeer.spawn(args[1], '${dir.path}/bramble');
    state['briar'] = await bramble.call('start ${state['nick']} ${state['password']}') as String;
  }

  final keys = KeyRing(senderFingerprint: await senderFingerprint(me.publicKey));
  for (final c in contacts) {
    keys.pairs[c['name'] as String] = await derivePairKeys(me, fromHex(c['ecp'] as String));
  }
  for (final t in teams) {
    keys.teams[t['id'] as String] = fromHex(t['key'] as String);
  }
  final lora = MeshCoreTransport(
      channelSecret: keyAt < 0 ? null : base64Url.decode(base64Url.normalize(args[keyAt + 1])));
  final transport = useBramble ? BrambleTransport(bramble) : null;
  squad = transport == null ? null : SquadTransport(transport);
  final sxAt = args.indexOf('--simplex');
  if (sxAt >= 0) {
    simplex = SimplexTransport(await WsSimplex.connect(int.parse(args[sxAt + 1])), ownKey: me.publicKey);
    await simplex!.start();
    state['sx'] = simplex!.address;
    log('simplex: ${simplex!.profile}');
  }
  router = PaceRouter(transports: [?simplex, ?transport, ?squad, lora], keys: keys);
  loraTransport = lora;
  simplex?.onData = (env) => router.receive(simplex!, env, now: DateTime.now());
  await syncSimplex();
  router.events.listen(onRouterEvent);
  if (loraAt >= 0) {
    final port = await SerialLink.open(args[loraAt + 1]);
    await Future<void>.delayed(const Duration(seconds: 3)); // ESP32 may reboot on open
    lora.onData = (env, meta) {
      log('lora datagram ${env.length} B, SNR ${meta.snr} dB${meta.flooded ? ', flooded' : ''}');
      router.receive(lora, env, now: DateTime.now());
    };
    if (teams.isNotEmpty && keyAt < 0) await lora.setChannelSecret(await teamLora(teams.first));
    await lora.attach(CompanionClient(port));
    log('lora ${lora.deviceInfo?.model}: ${lora.selfInfo?.radio}, '
        '${lora.isDefaultChannel ? 'ECP channel' : 'group channel'}');
  }
  if (transport == null) return commands();
  await transport.refresh();
  bramble.events.listen((e) async {
    switch (e['ev']) {
      case 'received':
        // First byte: 0 = pair envelope (layer A), 1 = squad-net frame (app BrambleKind)
        final d = fromHex(e['data'] as String);
        if (d.isEmpty) return;
        final body = Uint8List.sublistView(d, 1);
        await router.receive(d[0] == 1 ? squad! : transport, body, now: DateTime.now());
      case 'contactAdded':
        await transport.refresh();
        log('bramble contact up (id ${e['id']})');
        await router.availabilityChanged(DateTime.now());
      case 'transport':
        log('transport ${e['transport']} ${e['active'] == true ? 'up' : 'down'}');
        transport.setActive(e['transport'] as String, e['active'] == true);
        await router.availabilityChanged(DateTime.now());
      case 'connection':
        final set = transport.links.putIfAbsent(e['contact'] as int, () => {});
        e['open'] == true ? set.add(e['transport'] as String) : set.remove(e['transport'] as String);
        log('link ${e['transport']} ${e['open'] == true ? 'open' : 'closed'} (contact ${e['contact']})');
    }
  });
  await commands();
}

Future<void> commands() async {
  Timer.periodic(const Duration(seconds: 5), (_) => router.tick(DateTime.now()));
  log('ready. card:\n${myCard()}');
  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    await command(line.trim());
  }
}

List<Map<String, dynamic>> get teams =>
    ((state['teams'] ??= <dynamic>[]) as List).cast<Map<String, dynamic>>();

/// Same derivations as the app's MessagingService.teamIdFor / teamLoraKey.
Future<String> teamId(List<int> key) async => toHex(await deriveSubkey(key, 'team-id')).substring(0, 16);

Future<Uint8List> teamLora(Map<String, dynamic> t) async =>
    Uint8List.fromList((await deriveSubkey(fromHex(t['key'] as String), 'lora')).sublist(0, 16));

List<Map<String, dynamic>> get contacts =>
    (state['contacts'] as List).cast<Map<String, dynamic>>();

void save() => stateFile.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(state));

String myCard() => ContactCard(
      name: state['nick'] as String,
      ecpKey: me.publicKey,
      briarLink: state['briar'] as String?,
      simplexLink: state['sx'] as String?,
    ).toUri();

/// Tells layer P who our contacts are (and connects to their SimpleX addresses).
Future<void> syncSimplex() async => simplex?.contactsChanged(
      {for (final c in contacts) c['name'] as String: fromHex(c['ecp'] as String)},
      {for (final c in contacts) if (c['sx'] != null) c['name'] as String: c['sx'] as String},
    );

Future<void> command(String line) async {
  final parts = line.split(' ');
  switch (parts.first) {
    case 'card':
      log(myCard());
    case 'add':
      final card = ContactCard.fromUri(parts[1]);
      final name = card.name;
      contacts.removeWhere((c) => c['name'] == name);
      contacts.add({
        'name': name,
        'ecp': toHex(card.ecpKey),
        'briar': card.briarLink,
        'sx': card.simplexLink,
      });
      save();
      router.keys.pairs[name] = await derivePairKeys(me, card.ecpKey);
      if (hasBramble && card.briarLink != null) log('bramble add: ${await bramble.call('add ${card.briarLink} $name')}');
      await syncSimplex();
      final tk = card.teamKey;
      if (tk != null) {
        final id = await teamId(tk);
        if (!teams.any((t) => t['id'] == id)) teams.add({'id': id, 'key': toHex(tk)});
        save();
        router.keys.teams[id] = tk;
        if (loraTransport!.isAvailable) await loraTransport!.setChannelSecret(await teamLora(teams.first));
        log('joined team $id (LoRa on the team channel)');
      }
      log('added $name, verification ${await verificationNumber(me.publicKey, card.ecpKey)}');
    case 'contacts':
      for (final c in contacts) {
        log('${c['name']}  briar=${c['briar'] != null}');
      }
    case 'send':
      final id = await router.send(parts[1], MessageType.text, encodeText(parts.skip(2).join(' ')),
          now: DateTime.now());
      log('queued $id');
    case 'tsend':
      if (teams.isEmpty) return log('no team');
      await router.sendTeam(teams.first['id'] as String, MessageType.text,
          encodeText(parts.skip(1).join(' ')), now: DateTime.now());
      log('team message out (squad ${squad?.isAvailable == true ? 'up' : 'down'}, lora ${loraTransport!.isAvailable ? 'up' : 'down'})');
    case 'quit':
      if (hasBramble) await bramble.call('quit');
      exit(0);
    case '':
      break;
    default:
      log('? card | add <uri> | contacts | send <name> <text> | quit');
  }
}

Future<void> onRouterEvent(RouterEvent e) async {
  switch (e) {
    case MessageReceived(:final from, :final team, :final message, :final via):
      if (message.type == MessageType.text) {
        final text = decodeText(message.payload);
        log('RECEIVED ${team ? 'team' : 'from'} $from via $via: $text');
        if (echo && team) {
          await router.sendTeam(from, MessageType.text, encodeText('echo: $text'), now: DateTime.now());
        } else if (echo) {
          await router.send(from, MessageType.text, encodeText('echo: $text'), now: DateTime.now());
        }
      } else if (message.type != MessageType.ack) {
        log('RECEIVED from $from via $via: type ${message.type}');
      }
    case MessageSent(:final id, :final via):
      log('sent $id via $via');
    case MessageDelivered(:final id, :final via):
      log('DELIVERED $id via $via');
    case MessageWaiting(:final id):
      log('waiting $id');
    case MessageFailed(:final id):
      log('FAILED $id');
    case ConfirmationNeeded(:final id):
      log('needs SMS confirmation $id');
  }
}

/// The bramble-peer child process and its JSON line protocol (tools/bramble-peer Main.java).
class BramblePeer {
  BramblePeer._(this._p);

  static Future<BramblePeer> spawn(String bin, String dir) async {
    final p = await Process.start(bin, [dir], environment: {'BRAMBLE_PORT_OFFSET': '60'});
    final b = BramblePeer._(p);
    p.stderr.drain<void>();
    p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(b._line);
    return b;
  }

  final Process _p;
  final _replies = StreamController<Map<String, dynamic>>.broadcast();
  final _events = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get events => _events.stream;

  void _line(String l) {
    final m = jsonDecode(l) as Map<String, dynamic>;
    (m.containsKey('ev') ? _events : _replies).add(m);
  }

  Future<Object?> call(String cmd) async {
    final reply = _replies.stream.firstWhere((r) => r['re'] == cmd.split(' ').first);
    _p.stdin.writeln(cmd);
    final r = await reply.timeout(const Duration(minutes: 2));
    if (r['ok'] != true) throw StateError('$cmd: ${r['error']}');
    return r['value'];
  }
}

class BrambleTransport extends Transport {
  BrambleTransport(this.b);

  final BramblePeer b;
  final Set<String> _active = {};
  Map<String, int> _byLink = {};

  @override
  String get id => 'bramble';

  @override
  PaceLayer? get layer => PaceLayer.alternate;

  void setActive(String t, bool up) => up ? _active.add(t) : _active.remove(t);

  Future<void> refresh() async {
    final list = (await b.call('contacts') as List).cast<Map<String, dynamic>>();
    _byLink = {for (final c in list) if (c['link'] != null) c['link'] as String: c['id'] as int};
    for (final c in list) {
      links[c['id'] as int] = (c['links'] as List).cast<String>().toSet();
    }
    for (final t in (await b.call('transports') as List).cast<String>()) {
      _active.add(t);
    }
  }

  int? _idFor(String name) {
    final c = contacts.where((c) => c['name'] == name).firstOrNull;
    return c == null ? null : _byLink[c['briar']];
  }

  @override
  bool get isAvailable => _active.isNotEmpty;

  @override
  bool canReach(String contactId) => _idFor(contactId) != null;

  @override
  Future<bool> sendTo(String contactId, Uint8List data) async {
    final id = _idFor(contactId);
    if (id == null) return false;
    await b.call('send $id 00${toHex(data)}');
    return true;
  }

  /// Bramble contact id → transports with a live connection.
  final Map<int, Set<String>> links = {};
}

/// The squad net over Bramble: team frames to contacts linked over LAN/Bluetooth only.
class SquadTransport extends Transport {
  SquadTransport(this.b);

  final BrambleTransport b;

  Iterable<int> get _inRange => b.links.entries
      .where((e) => e.value.contains('lan') || e.value.contains('bluetooth'))
      .map((e) => e.key);

  @override
  String get id => 'squad';

  @override
  PaceLayer? get layer => null;

  @override
  bool get isAvailable => _inRange.isNotEmpty;

  @override
  bool canReach(String contactId) => false;

  @override
  Future<bool> sendTo(String contactId, Uint8List data) async => false;

  @override
  Future<bool> broadcast(Uint8List data) async {
    for (final c in _inRange.toList()) {
      await b.b.call('send $c 01${toHex(data)}');
    }
    return _inRange.isNotEmpty;
  }
}
