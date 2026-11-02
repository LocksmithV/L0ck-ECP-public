import 'dart:async';
import 'dart:typed_data';

import 'package:ecp_core/ecp_core.dart';
import 'package:ecp_meshcore/ecp_meshcore.dart';
import 'package:test/test.dart';

/// A pretend MeshCore companion radio on a pretend mesh: datagrams sent on a channel are
/// queued at every other radio holding the same channel secret, and fetched with
/// CMD_SYNC_NEXT_MESSAGE after a "messages waiting" push — as the firmware does.
class FakeMesh {
  final List<FakeRadio> radios = [];
}

class FakeRadio implements FrameLink {
  FakeRadio(this.mesh, {this.maxChannels = 8}) {
    mesh.radios.add(this);
    channels[0] = ('Public', Uint8List(16)..[0] = 0x8b);
  }

  final FakeMesh mesh;
  final int maxChannels;
  final Map<int, (String, Uint8List)> channels = {};
  final List<Uint8List> inbox = [];
  final _out = StreamController<Uint8List>.broadcast();
  final List<Uint8List> sent = [];

  @override
  Stream<Uint8List> get frames => _out.stream;

  void _reply(List<int> f) => scheduleMicrotask(() => _out.add(Uint8List.fromList(f)));

  @override
  Future<void> send(Uint8List f) async {
    sent.add(f);
    switch (f[0]) {
      case Cmd.appStart:
        _reply([Resp.selfInfo, 1, 22, 22, ...List.filled(32, 7), ...List.filled(12, 0),
          0x38, 0x44, 0x0D, 0, 0x24, 0xF4, 0, 0, 7, 5, ...'node'.codeUnits]);
      case Cmd.deviceQuery:
        _reply([Resp.deviceInfo, 14, 50, maxChannels, ...List.filled(76, 0)]);
      case Cmd.getChannel:
        final c = channels[f[1]];
        _reply([Resp.channelInfo, f[1], ...Uint8List(32)..setAll(0, (c?.$1 ?? '').codeUnits),
          ...(c?.$2 ?? Uint8List(16))]);
      case Cmd.setChannel:
        final name = String.fromCharCodes(f.sublist(2, 34).takeWhile((b) => b != 0));
        channels[f[1]] = (name, Uint8List.fromList(f.sublist(34, 50)));
        _reply([Resp.ok]);
      case Cmd.sendChannelData:
        if (f.length - 5 > maxChannelData) return _reply([Resp.err, 6]);
        final secret = channels[f[1]]!.$2;
        final type = f.sublist(3, 5), data = f.sublist(5);
        for (final r in mesh.radios.where((r) => r != this)) {
          final slot = r.channels.entries.where((e) => _eq(e.value.$2, secret)).firstOrNull;
          if (slot == null) continue;
          r.inbox.add(Uint8List.fromList(
              [Resp.channelDataRecv, 24, 0, 0, slot.key, 2, ...type, data.length, ...data]));
          r._reply([Resp.msgWaiting]);
        }
        _reply([Resp.ok]);
      case Cmd.syncNextMessage:
        _reply(inbox.isEmpty ? [Resp.noMoreMessages] : inbox.removeAt(0));
    }
  }

  static bool _eq(List<int> a, List<int> b) =>
      a.length == b.length && Iterable.generate(a.length).every((i) => a[i] == b[i]);
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  test('serial framing: frames split and glued across reads, noise skipped', () {
    final fr = SerialFraming();
    final a = [0x3E, 2, 0, 0xAA, 0xBB], b = [0x3E, 1, 0, 0xCC];
    expect(fr.feed([0x21, 0x0A, ...a.sublist(0, 2)]), isEmpty);
    final got = fr.feed([...a.sublist(2), ...b]);
    expect(got.map((f) => f.toList()), [
      [0xAA, 0xBB],
      [0xCC],
    ]);
    expect(SerialFraming.wrap([1, 2]), [0x3C, 2, 0, 1, 2]);
  });

  test('handshake parses radio settings; channel goes into the first free slot, once',
      () async {
    final radio = FakeRadio(FakeMesh());
    final c = CompanionClient(radio);
    final (self, dev) = await c.start();
    expect(self.name, 'node');
    expect(self.freqMHz, closeTo(869.432, 0.001));
    expect(self.sf, 7);
    expect(dev.maxChannels, 8);
    final secret = MeshCoreTransport.defaultChannelSecret;
    expect(await c.ensureChannel('ecp', secret, 8), 1, reason: 'slot 0 is Public');
    final writes = radio.sent.where((f) => f[0] == Cmd.setChannel).length;
    expect(await c.ensureChannel('ecp', secret, 8), 1);
    expect(radio.sent.where((f) => f[0] == Cmd.setChannel).length, writes,
        reason: 'existing slot reused, nothing rewritten');
  });

  test('a private group channel: other radios stop hearing, the old slot is reused',
      () async {
    final mesh = FakeMesh();
    final a = MeshCoreTransport(), b = MeshCoreTransport(), outsider = MeshCoreTransport();
    final heard = <String, int>{'b': 0, 'outsider': 0};
    b.onData = (_, __) => heard['b'] = heard['b']! + 1;
    outsider.onData = (_, __) => heard['outsider'] = heard['outsider']! + 1;
    final ra = FakeRadio(mesh);
    for (final (t, r) in [(a, ra), (b, FakeRadio(mesh)), (outsider, FakeRadio(mesh))]) {
      await t.attach(CompanionClient(r));
    }
    final group = Uint8List.fromList(List.generate(16, (i) => i * 7 + 1));
    await a.setChannelSecret(group);
    await b.setChannelSecret(group);
    expect(a.isDefaultChannel, isFalse);
    expect(ra.channels.values.where((c) => c.$1 == 'ecp'), hasLength(1),
        reason: 'the ECP slot is rewritten, not a second one taken');
    await a.broadcast(Uint8List.fromList([1, 2, 3]));
    await settle();
    expect(heard, {'b': 1, 'outsider': 0});
  });

  test('public channel traffic and other apps\' datagrams are ignored', () async {
    final mesh = FakeMesh();
    final ours = MeshCoreTransport();
    var heard = 0;
    ours.onData = (_, __) => heard++;
    final r = FakeRadio(mesh);
    await ours.attach(CompanionClient(r));
    r.inbox
      ..add(Uint8List.fromList([Resp.channelDataRecv, 0, 0, 0, 0, 2, 0xEC, 0xFF, 1, 9]))
      ..add(Uint8List.fromList([Resp.channelDataRecv, 0, 0, 0, 1, 2, 0x00, 0x01, 1, 9]))
      ..add(Uint8List.fromList([Resp.channelMsgV3, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0x41]));
    r._reply([Resp.msgWaiting]); // the radio says messages wait; the client drains them
    await settle();
    expect(r.inbox, isEmpty, reason: 'all fetched');
    expect(heard, 0);
  });

  test('errors and oversize datagrams', () async {
    final radio = FakeRadio(FakeMesh());
    final c = CompanionClient(radio);
    expect(() => sendChannelData(1, 0xFFEC, Uint8List(166)), throwsArgumentError);
    radio.channels[1] = ('x', Uint8List(16));
    await expectLater(c.request(Uint8List.fromList([Cmd.sendChannelData, 1, 0xFF, 0xEC, 0xFF,
      ...List.filled(170, 1)]), {Resp.ok}), throwsA(isA<CompanionError>()));
  });

  group('PACE layer C between two routers', () {
    late PaceRouter alice, bob;
    late MeshCoreTransport ta;
    final received = <String>[];
    final delivered = <String>[];

    Future<(PaceRouter, MeshCoreTransport)> node(
        FakeMesh mesh, EcpIdentity me, EcpIdentity peer, String peerName) async {
      final t = MeshCoreTransport();
      final keys = KeyRing(senderFingerprint: await senderFingerprint(me.publicKey));
      keys.pairs[peerName] = await derivePairKeys(me, peer.publicKey);
      final r = PaceRouter(transports: [t], keys: keys);
      t.onData = (env, _) => r.receive(t, env, now: DateTime.now());
      await t.attach(CompanionClient(FakeRadio(mesh)));
      return (r, t);
    }

    setUp(() async {
      received.clear();
      delivered.clear();
      final mesh = FakeMesh();
      final ia = await EcpIdentity.generate(), ib = await EcpIdentity.generate();
      (alice, ta) = await node(mesh, ia, ib, 'bob');
      (bob, _) = await node(mesh, ib, ia, 'alice');
      bob.events.listen((e) {
        if (e is MessageReceived && e.message.type == MessageType.text) {
          received.add(decodeText(e.message.payload));
        }
      });
      alice.events.listen((e) {
        if (e is MessageDelivered) delivered.add(e.via);
      });
    });

    test('a text floods over LoRa and the ACK comes back the same way', () async {
      expect(ta.isAvailable, isTrue);
      await alice.send('bob', MessageType.text, encodeText('přes LoRa'), now: DateTime.now());
      await settle();
      expect(received, ['přes LoRa']);
      expect(delivered, ['meshcore']);
    });

    test('a position report fits one datagram', () async {
      final p = const Position(lat: 50.08, lon: 14.42).encode();
      final env = await EcpEnvelope.seal(
          kind: EnvelopeKind.pair,
          key: alice.keys.pairs['bob']!.send,
          message: InnerMessage.create(type: MessageType.position, payload: p, now: DateTime.now()),
          now: DateTime.now());
      expect(env.length, lessThanOrEqualTo(maxChannelData));
    });

    test('too long for LoRa: the layer is skipped, not truncated', () async {
      await ta.detach();
      expect(await ta.sendTo('bob', Uint8List(200)), isFalse);
    });
  });
}
