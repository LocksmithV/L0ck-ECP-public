import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:l0ck_ecp/data/database.dart';
import 'package:l0ck_ecp/messaging/bramble_transport.dart';
import 'package:l0ck_ecp/messaging/messaging_service.dart';
import 'package:l0ck_ecp/platform/bramble.dart';
import 'package:l0ck_ecp/security/security_service.dart';
import 'package:l0ck_ecp/l10n/lang.dart';

/// Bramble nodes on a pretend network: a contact exists once both sides added each other's
/// link (as with real handshake links), and sends arrive as "received" events.
class FakeBrambleNet {
  final Map<String, FakeBramble> byLink = {};
}

class FakeBramble implements BrambleApi {
  FakeBramble(this.net, this.myLink) {
    net.byLink[myLink] = this;
  }

  final FakeBrambleNet net;
  final String myLink;
  final _events = StreamController<Map<String, Object?>>.broadcast();
  final Set<String> added = {};
  final Map<int, String> contactLinks = {};
  bool online = true;

  @override
  Future<String> start({required String profile, required String nickname, required String password}) async => myLink;

  @override
  Future<List<BrambleContact>> contacts() async => [
    for (final e in contactLinks.entries) BrambleContact(e.key, e.value, const ['tor']),
  ];

  @override
  Future<String> addContact(String link, String alias) async {
    if (!added.add(link)) return 'exists';
    final peer = net.byLink[link];
    if (peer != null && peer.added.contains(myLink)) {
      _becomeContacts(peer);
      peer._becomeContacts(this);
    }
    return 'pending';
  }

  void _becomeContacts(FakeBramble peer) {
    final id = contactLinks.length + 1;
    contactLinks[id] = peer.myLink;
    _events.add({'type': 'contactAdded', 'id': id});
  }

  /// Both sides see a link to each other open (e.g. LAN) or close.
  void link(FakeBramble peer, String transport, bool open) {
    for (final (a, b) in [(this, peer), (peer, this)]) {
      final id = a.contactLinks.entries.firstWhere((e) => e.value == b.myLink).key;
      a._events.add({'type': 'connection', 'contact': id, 'transport': transport, 'open': open});
    }
  }

  @override
  Future<void> send(int contact, Uint8List envelope) async {
    final peer = net.byLink[contactLinks[contact]]!;
    final back = peer.contactLinks.entries.firstWhere((e) => e.value == myLink).key;
    scheduleMicrotask(
      () => peer._events.add({
        'type': 'received',
        'contact': back,
        'data': envelope,
        'links': ['tor'],
      }),
    );
  }

  @override
  Future<List<String>> transports() async => online ? ['tor'] : [];

  @override
  Stream<Map<String, Object?>> get events => _events.stream;

  @override
  Future<void> stopUnless(String? keep) async {}

  @override
  Future<String> connectBluetooth(int contact) async => 'connected';

  @override
  Future<String> refreshBluetooth() async => 'ACTIVE';

  @override
  Future<String> restartTransport(String name) async => 'ACTIVE';

  @override
  Future<void> removeContact(int contact) async => contactLinks.remove(contact);

  @override
  Future<void> deleteProfilesExcept(String? keep) async {}
}

Future<Session> session(String name) async =>
    Session(randomBytes(32), EcpDatabase(NativeDatabase.memory()), await EcpIdentity.generate(), name);

Future<void> until(Future<bool> Function() cond) async {
  for (var i = 0; i < 200; i++) {
    if (await cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition not reached');
}

void main() {
  Lang.current.value = const Locale('cs');
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late MessagingService alice, bob;
  late FakeBramble ba, bb;

  Future<MessagingService> node(String name, FakeBramble b) async {
    final m = await MessagingService.start(await session(name));
    final t = await BrambleTransport.start(b, profile: 'p', nickname: name, password: 'x');
    await m.addTransport(t);
    await m.addTransport(t.squad);
    return m;
  }

  setUp(() async {
    final net = FakeBrambleNet();
    ba = FakeBramble(net, 'briar://alice');
    bb = FakeBramble(net, 'briar://bob');
    alice = await node('Alfa', ba);
    bob = await node('Bravo', bb);
  });

  tearDown(() async {
    for (final m in [alice, bob]) {
      await m.dispose();
      await m.session.close();
    }
  });

  test('own card carries the briar link once Bramble runs', () {
    expect(ContactCard.fromUri(alice.myContactUri()).briarLink, 'briar://alice');
    expect(alice.channelStatus, ['Bramble: tor', 'Síť skupiny: 0 v dosahu']);
  });

  test('cards swapped in person become Bramble contacts and a text goes over layer A', () async {
    final a = await alice.addContactFromUri(bob.myContactUri()) as ContactAdded;
    await bob.addContactFromUri(alice.myContactUri());
    await alice.sendText(a.contact.id, 'přes Tor');
    final adb = alice.session.db, bdb = bob.session.db;
    await until(() async => (await bdb.select(bdb.messages).get()).isNotEmpty);
    final got = (await bdb.select(bdb.messages).get()).single;
    expect(decodeText(got.payload), 'přes Tor');
    expect(got.via, 'bramble');
    await until(() async => (await adb.select(adb.messages).getSingle()).status == 'delivered');
  });

  test('before the other side adds the link the message waits, then goes', () async {
    final a = await alice.addContactFromUri(bob.myContactUri()) as ContactAdded;
    await alice.sendText(a.contact.id, 'čekám');
    final adb = alice.session.db;
    await until(() async => (await adb.select(adb.messages).getSingle()).status == 'waiting');
    await bob.addContactFromUri(alice.myContactUri()); // handshake completes → contactAdded
    await until(() async => (await adb.select(adb.messages).getSingle()).status == 'delivered');
  });

  group('team over the squad net', () {
    late Team team;

    setUp(() async {
      team = await alice.createTeam('Hlídka');
      final r = await bob.addContactFromUri(alice.teamCardUri(team)) as ContactAdded;
      expect(r.team!.id, team.id, reason: 'the id comes from the key, the same for both');
      await alice.addContactFromUri(bob.myContactUri());
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    test('both members get the same LoRa channel key from the team key', () async {
      final bt = await (bob.session.db.select(bob.session.db.teams)).getSingle();
      expect(await MessagingService.teamLoraKey(bt.key), await MessagingService.teamLoraKey(team.key));
    });

    test('nobody linked locally: not the squad net, but members get it over Bramble', () async {
      final adb = alice.session.db;
      await until(() async => (await adb.watchTeamMembers(team.id).first).isNotEmpty);
      await alice.sendTeamText(team.id, 'daleko');
      final m = (await adb.select(adb.messages).get()).firstWhere((m) => m.teamId != null);
      expect(m.via, 'bramble', reason: 'fan-out to the member, no squad frame without a local link');
      final bdb = bob.session.db;
      await until(() async => (await bdb.select(bdb.messages).get()).any((m) => m.teamId != null));
    });

    test('linked over LAN: the message arrives with the sender\'s name', () async {
      ba.link(bb, 'lan', true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(alice.channelStatus, contains('Síť skupiny: 1 v dosahu'));
      await alice.sendTeamText(team.id, 'sraz u mostu');
      final bdb = bob.session.db;
      await until(() async => (await bdb.select(bdb.messages).get()).isNotEmpty);
      final got = (await bdb.select(bdb.messages).get()).single;
      expect(got.teamId, team.id);
      expect(decodeText(got.payload), 'sraz u mostu');
      expect(got.via, 'squad');
      expect(bob.senderNames[got.sender], 'Alfa');
    });
  });
}
