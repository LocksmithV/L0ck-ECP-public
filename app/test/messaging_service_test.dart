import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:ecp_core/ecp_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l0ck_ecp/data/database.dart';
import 'package:l0ck_ecp/messaging/messaging_service.dart';
import 'package:l0ck_ecp/security/security_service.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// A wire between two services: whatever one side sends arrives at the other's router.
class Loop extends Transport {
  Loop(this.id, this.layer);

  @override
  final String id;
  @override
  final PaceLayer? layer;
  late Loop peer;
  late MessagingService Function() owner;
  bool up = true;

  @override
  bool get isAvailable => up;

  @override
  bool canReach(String contactId) => true;

  @override
  Future<bool> sendTo(String contactId, Uint8List data) async {
    if (!up) return false;
    Future(() => peer.owner().router.receive(peer, data, now: DateTime.now()));
    return true;
  }
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
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('pair over a loopback channel', () {
    late MessagingService alice, bob;
    late Loop aSide, bSide;

    setUp(() async {
      aSide = Loop('simplex', PaceLayer.primary);
      bSide = Loop('simplex', PaceLayer.primary);
      aSide.peer = bSide;
      bSide.peer = aSide;
      alice = await MessagingService.start(await session('Alfa'), transports: [aSide]);
      bob = await MessagingService.start(await session('Bravo'), transports: [bSide]);
      aSide.owner = () => alice;
      bSide.owner = () => bob;
    });

    tearDown(() async {
      for (final m in [alice, bob]) {
        await m.dispose();
        await m.session.close();
      }
    });

    test('both sides see the same verification number', () async {
      final a = await alice.addContactFromUri(bob.myContactUri()) as ContactAdded;
      final b = await bob.addContactFromUri(alice.myContactUri()) as ContactAdded;
      expect(a.contact.name, 'Bravo');
      expect(a.verification, b.verification);
      expect(a.contact.verified, isFalse);
      await alice.setVerified(a.contact.id, true);
      expect((await alice.session.db.select(alice.session.db.contacts).getSingle()).verified, isTrue);
    });

    test('rejects garbage and own link; a known key is refreshed', () async {
      expect(await alice.addContactFromUri('l0ck://c/xyz'), isA<ContactRejected>());
      expect(await alice.addContactFromUri(alice.myContactUri()), isA<ContactRejected>());
      expect(await alice.addContactFromUri(bob.myContactUri()), isA<ContactAdded>());
      expect(
        await alice.addContactFromUri(bob.myContactUri()),
        isA<ContactUpdated>(),
        reason: 'a known key refreshes the contact instead of adding it twice',
      );
      final card = ContactCard.fromUri(bob.myContactUri());
      final newer = ContactCard(name: card.name, ecpKey: card.ecpKey, simplexLink: 'https://smp.example/a#x');
      final r = await alice.addContactFromUri(newer.toUri()) as ContactUpdated;
      expect(r.contact.simplexLink, 'https://smp.example/a#x');
      expect(await alice.session.db.select(alice.session.db.contacts).get(), hasLength(1));
    });

    test('a text arrives and the sender sees it delivered', () async {
      final a = await alice.addContactFromUri(bob.myContactUri()) as ContactAdded;
      await bob.addContactFromUri(alice.myContactUri());
      await alice.sendText(a.contact.id, 'Ahoj');
      final adb = alice.session.db, bdb = bob.session.db;
      await until(() async => (await bdb.select(bdb.messages).get()).isNotEmpty);
      final got = (await bdb.select(bdb.messages).get()).single;
      expect(got.outgoing, isFalse);
      expect(decodeText(got.payload), 'Ahoj');
      expect(got.via, 'simplex');
      await until(() async => (await adb.select(adb.messages).getSingle()).status == 'delivered');
      expect((await adb.select(adb.messages).getSingle()).via, 'simplex');
      expect(await adb.select(adb.outboxRows).get(), isEmpty);
    });

    test('a new own number reaches contacts by itself; a card with another key is ignored', () async {
      final a = await alice.addContactFromUri(bob.myContactUri()) as ContactAdded;
      await bob.addContactFromUri(alice.myContactUri());
      final bdb = bob.session.db;
      await alice.setOwnPhone('+420 777 123 456'); // new local SIM in the deployment area
      expect(ContactCard.fromUri(alice.myContactUri()).phone, '+420 777 123 456');
      await until(() async => (await bdb.select(bdb.contacts).getSingle()).phone == '+420 777 123 456');
      await alice.setOwnPhone(null);
      await until(() async => (await bdb.select(bdb.contacts).getSingle()).phone == null);
      expect(a.contact.id, isNotNull);
      expect(await bdb.select(bdb.messages).get(), isEmpty, reason: 'control, not a chat message');
    });

    test('messages arriving out of view are counted for the notification', () async {
      final a = await alice.addContactFromUri(bob.myContactUri()) as ContactAdded;
      await bob.addContactFromUri(alice.myContactUri());
      final counts = <int>[];
      final targets = <String>{};
      bob.onUnseen = (n, open) {
        counts.add(n);
        targets.add(open);
      };
      await alice.sendText(a.contact.id, 'jedna');
      await alice.sendText(a.contact.id, 'dvě');
      await until(() async => counts.length == 2);
      expect(counts, [1, 2]);
      expect(targets, {'c:1'}, reason: 'a tap leads to the conversation with Alfa');
      bob.seen();
      await alice.sendText(a.contact.id, 'tři');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(counts, [1, 2], reason: 'the user is looking at the app');
    });

    test('read receipt: the sender sees "read" once the conversation is opened', () async {
      final a = await alice.addContactFromUri(bob.myContactUri()) as ContactAdded;
      final b = await bob.addContactFromUri(alice.myContactUri()) as ContactAdded;
      await alice.sendText(a.contact.id, 'čti');
      final adb = alice.session.db, bdb = bob.session.db;
      await until(() async => (await adb.select(adb.messages).getSingle()).status == 'delivered');
      final unread = await bdb.watchUnread().first;
      expect(unread.contacts[b.contact.id], 1);
      await bob.markRead(b.contact.id);
      expect((await bdb.watchUnread().first).contacts, isEmpty);
      await until(() async => (await adb.select(adb.messages).getSingle()).status == 'read');
      expect((await adb.select(adb.messages).getSingle()).statusAt, isNotNull);
    });

    test('team: joining announces the member; team messages reach members over P', () async {
      final team = await alice.createTeam('Hlídka');
      await alice.addContactFromUri(bob.myContactUri());
      await bob.addContactFromUri(alice.teamCardUri(team));
      final adb = alice.session.db, bdb = bob.session.db;
      await until(() async => (await adb.watchTeamMembers(team.id).first).isNotEmpty);
      expect((await bdb.watchTeamMembers(team.id).first).single.name, 'Alfa');
      await alice.sendTeamText(team.id, 'sraz v 6');
      await until(() async => (await bdb.select(bdb.messages).get()).isNotEmpty);
      final got = (await bdb.select(bdb.messages).get()).single;
      expect(got.teamId, team.id);
      expect(got.via, 'simplex');
      final sent = (await adb.select(adb.messages).get()).firstWhere((m) => m.teamId != null);
      expect(sent.status, 'sent');
      expect(sent.via, 'simplex');
    });

    test('leaving a team tells the members and forgets the team', () async {
      final team = await alice.createTeam('Hlídka');
      await alice.addContactFromUri(bob.myContactUri());
      await bob.addContactFromUri(alice.teamCardUri(team));
      final adb = alice.session.db, bdb = bob.session.db;
      await until(() async => (await adb.watchTeamMembers(team.id).first).isNotEmpty);
      await bob.leaveTeam(team.id);
      expect(await bdb.select(bdb.teams).get(), isEmpty);
      expect(bob.router.keys.teams, isEmpty);
      await until(() async => (await adb.watchTeamMembers(team.id).first).isEmpty);
    });

    test('a position report travels as its own message type', () async {
      final a = await alice.addContactFromUri(bob.myContactUri()) as ContactAdded;
      await bob.addContactFromUri(alice.myContactUri());
      const p = Position(lat: 50.088, lon: 14.4208, accuracy: 8);
      await alice.sendPayload(a.contact.id, MessageType.report, const StatusReport(StatusCode.moving, p).encode());
      final bdb = bob.session.db;
      await until(() async => (await bdb.select(bdb.messages).get()).isNotEmpty);
      final got = (await bdb.select(bdb.messages).getSingle());
      expect(got.type, MessageType.report);
      final r = Report.decode(got.payload) as StatusReport;
      expect(r.status, StatusCode.moving);
      expect(r.position!.lat, closeTo(50.088, 1e-6));
    });

    test('deleting a contact removes its conversation and keys', () async {
      final a = await alice.addContactFromUri(bob.myContactUri()) as ContactAdded;
      await alice.sendText(a.contact.id, 'x');
      await alice.deleteContact(a.contact.id);
      final adb = alice.session.db;
      expect(await adb.select(adb.contacts).get(), isEmpty);
      expect(await adb.select(adb.messages).get(), isEmpty);
      expect(alice.router.keys.pairs, isEmpty);
    });

    test('PACE order is kept across restarts', () async {
      final order = [PaceLayer.contingency, PaceLayer.primary, PaceLayer.alternate, PaceLayer.emergency];
      await alice.setPaceOrder(order);
      final again = await MessagingService.start(alice.session);
      expect(again.paceOrder, order);
      await again.dispose();
    });

    test('no channel up: the message waits in the persisted outbox', () async {
      aSide.up = false;
      final a = await alice.addContactFromUri(bob.myContactUri()) as ContactAdded;
      await alice.sendText(a.contact.id, 'later');
      final adb = alice.session.db;
      await until(() async => (await adb.select(adb.messages).getSingle()).status == 'waiting');
      expect(await adb.select(adb.outboxRows).get(), hasLength(1));
    });
  });

  test('a v1 profile database upgrades to v2 and keeps its data', () async {
    final dir = await Directory.systemTemp.createTemp('l0ck_ecp_mig');
    final file = File('${dir.path}/v1.db');
    // The v1 schema exactly as F2 created it
    final fresh = EcpDatabase(NativeDatabase.memory());
    final v1Tables = await fresh
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'table' "
          "AND name IN ('identity_rows', 'contacts')",
        )
        .map((r) => r.read<String>('sql'))
        .get();
    await fresh.close();
    final db1 = raw.sqlite3.open(file.path);
    for (final sql in v1Tables) {
      db1.execute(sql);
    }
    db1.execute("INSERT INTO identity_rows VALUES (1, x'00', 'Alfa', 0)");
    db1.execute('PRAGMA user_version = 1');
    db1.close();

    final db2 = EcpDatabase(NativeDatabase(file));
    expect((await db2.identity())!.nickname, 'Alfa');
    expect(await db2.select(db2.messages).get(), isEmpty);
    expect(await db2.select(db2.outboxRows).get(), isEmpty);
    expect(await db2.select(db2.seenIds).get(), isEmpty);
    await db2.close();
    await dir.delete(recursive: true);
  });
}
