import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:ecp_core/ecp_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l0ck_ecp/data/database.dart';
import 'package:l0ck_ecp/messaging/messaging_service.dart';
import 'package:l0ck_ecp/messaging/panic.dart';
import 'package:l0ck_ecp/security/lock_config.dart';
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

    test('voice: a clip in three parts is one message at the other end, delivered once all are', () async {
      final a = await alice.addContactFromUri(bob.myContactUri()) as ContactAdded;
      await bob.addContactFromUri(alice.myContactUri());
      expect(alice.canSendVoice(a.contact.id), isTrue);
      final audio = Uint8List.fromList(List.generate(20000, (i) => i * 7 % 256));
      final id = await alice.sendVoice(a.contact.id, VoicePart.opus, 2500, audio);
      final adb = alice.session.db, bdb = bob.session.db;
      await until(() async => (await bdb.select(bdb.messages).get()).isNotEmpty);
      final got = (await bdb.select(bdb.messages).get()).single;
      expect(got.type, MessageType.voice);
      final clip = VoicePart.decode(got.payload);
      expect((clip.count, clip.durationMs, clip.codec), (1, 2500, VoicePart.opus));
      expect(clip.data, audio);
      expect(await bdb.select(bdb.voiceParts).get(), isEmpty, reason: 'parts are gone once joined');
      await until(() async =>
          (await (adb.select(adb.messages)..where((m) => m.id.equals(id))).getSingle()).status == 'delivered');
      expect(await adb.select(adb.messages).get(), hasLength(1), reason: 'one row for the whole clip');

      aSide.up = false; // no SimpleX/Bramble: no voice (it would not go by LoRa or SMS)
      expect(alice.canSendVoice(a.contact.id), isFalse);
    });

    test('a file in parts arrives whole, with its name and type', () async {
      final a = await alice.addContactFromUri(bob.myContactUri()) as ContactAdded;
      await bob.addContactFromUri(alice.myContactUri());
      final bytes = Uint8List.fromList(List.generate(9000, (i) => i * 3 % 256));
      await alice.sendAttachment(
          a.contact.id, Attachment(kind: Attachment.file, name: 'mapa.pdf', mime: 'application/pdf', bytes: bytes));
      final bdb = bob.session.db;
      await until(() async => (await bdb.select(bdb.messages).get()).isNotEmpty);
      final got = (await bdb.select(bdb.messages).get()).single;
      expect(got.type, MessageType.file);
      final file = Attachment.decode(got.payload);
      expect((file.name, file.mime, file.kind), ('mapa.pdf', 'application/pdf', Attachment.file));
      expect(file.bytes, bytes);
      expect(await bdb.select(bdb.voiceParts).get(), isEmpty);
    });

    test('parts arriving all at once still make one message', () async {
      final a = await alice.addContactFromUri(bob.myContactUri()) as ContactAdded;
      await bob.addContactFromUri(alice.myContactUri());
      // Bob's side handles every part at the same moment (no awaits in between)
      final blob = Attachment(kind: Attachment.file, name: 'a.bin', mime: 'x/y', bytes: Uint8List(7000)).encode();
      final parts = FilePart.split(Uint8List.fromList([1, 1, 1, 1]), blob);
      final aKeys = alice.router.keys.pairs['${a.contact.id}']!;
      final now = DateTime.now();
      final envs = [
        for (final p in parts)
          await EcpEnvelope.seal(
              kind: EnvelopeKind.pair,
              key: aKeys.send,
              message: InnerMessage.create(type: MessageType.file, payload: p.encode(), now: now),
              now: now)
      ];
      await Future.wait([for (final e in envs) bob.router.receive(bSide, e, now: now)]);
      final bdb = bob.session.db;
      await until(() async => (await bdb.select(bdb.messages).get()).isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await bdb.select(bdb.messages).get(), hasLength(1));
    });

    test('clearing a chat empties it on this phone; the contact stays', () async {
      final a = await alice.addContactFromUri(bob.myContactUri()) as ContactAdded;
      await alice.sendText(a.contact.id, 'ahoj');
      final adb = alice.session.db;
      expect(await adb.select(adb.messages).get(), hasLength(1));
      await alice.clearChat(contactId: a.contact.id);
      expect(await adb.select(adb.messages).get(), isEmpty);
      expect(await adb.select(adb.contacts).get(), hasLength(1));
    });

    test('disappearing messages: older ones go, newer stay, the choice persists', () async {
      final a = await alice.addContactFromUri(bob.myContactUri()) as ContactAdded;
      final adb = alice.session.db;
      await alice.sendText(a.contact.id, 'staré');
      await (adb.update(adb.messages)).write(MessagesCompanion(at: Value(DateTime.now().subtract(const Duration(hours: 2)))));
      await alice.sendText(a.contact.id, 'nové');
      await alice.setKeepFor(const Duration(hours: 1));
      final left = await adb.select(adb.messages).get();
      expect(left.map((m) => decodeText(m.payload)), ['nové']);
      final again = await MessagingService.start(alice.session);
      expect(again.keepFor, const Duration(hours: 1));
      await again.dispose();
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

    test('PANIC: status with position, then the own text, as emergency; settings persist', () async {
      final a = await alice.addContactFromUri(bob.myContactUri()) as ContactAdded;
      await bob.addContactFromUri(alice.myContactUri());
      await alice.setPanic(const PanicConfig(status: StatusCode.injured, text: 'most u řeky', teams: false));
      final again = await MessagingService.start(alice.session);
      expect(again.panic.status, StatusCode.injured);
      await again.dispose();
      const p = Position(lat: 50.088, lon: 14.4208);
      final r = await alice.sendPanic(position: p);
      expect((r.contacts, r.teams, r.ids.length), (1, 0, 2));
      final bdb = bob.session.db;
      await until(() async => (await bdb.select(bdb.messages).get()).length == 2);
      final got = await (bdb.select(bdb.messages)..orderBy([(t) => OrderingTerm(expression: t.at)])).get();
      final status = Report.decode(got.first.payload) as StatusReport;
      expect(status.status, StatusCode.injured);
      expect(status.position!.lat, closeTo(50.088, 1e-6));
      expect(decodeText(got.last.payload), 'most u řeky');
      final adb = alice.session.db;
      await alice.awaitDelivery(r.ids, const Duration(seconds: 2));
      expect((await adb.select(adb.messages).get()).map((m) => m.status).toSet(), {'delivered'});
      expect(a.contact.id, isNotNull);
    });

    test('a repeated PANIC carries the status with the new position, not the text again', () async {
      final a = await alice.addContactFromUri(bob.myContactUri()) as ContactAdded;
      await bob.addContactFromUri(alice.myContactUri());
      await alice.setPanic(const PanicConfig(text: 'most u řeky', repeatMinutes: 5, teams: false));
      final r = await alice.sendPanic(repeat: true, position: const Position(lat: 50.1, lon: 14.4));
      expect(r.ids, hasLength(1));
      final bdb = bob.session.db;
      await until(() async => (await bdb.select(bdb.messages).get()).isNotEmpty);
      final got = (await bdb.select(bdb.messages).get()).single;
      expect((Report.decode(got.payload) as StatusReport).position!.lat, closeTo(50.1, 1e-6));
      expect(a.contact.id, isNotNull);
    });

    test('check-in: confirmed in time nothing goes; missed, the status goes; OK after it', () async {
      await alice.addContactFromUri(bob.myContactUri());
      await bob.addContactFromUri(alice.myContactUri());
      var reminded = 0;
      alice.onCheckInSoon = () => reminded++;
      await alice.setCheckIn(const CheckInConfig(enabled: true, minutes: 60, status: StatusCode.injured, position: false));
      final due = alice.checkInDue.value!;
      expect(due.difference(DateTime.now()).inMinutes, inInclusiveRange(59, 60));
      await alice.checkInTick();
      expect(reminded, 0);
      final bdb = bob.session.db;
      expect(await bdb.select(bdb.messages).get(), isEmpty);

      alice.checkInDue.value = DateTime.now().subtract(const Duration(seconds: 1)); // time is up
      await alice.checkInTick();
      expect((reminded, alice.checkInDue.value, alice.checkInFired.value != null), (1, null, true));
      await until(() async => (await bdb.select(bdb.messages).get()).isNotEmpty);
      expect((Report.decode((await bdb.select(bdb.messages).get()).single.payload) as StatusReport).status,
          StatusCode.injured);

      await alice.checkedIn(); // "I am fine": everyone hears OK, the next one is armed
      await until(() async => (await bdb.select(bdb.messages).get()).length == 2);
      expect(alice.checkInFired.value, isNull);
      expect(alice.checkInDue.value, isNotNull);
      final again = await MessagingService.start(alice.session);
      expect((again.checkIn.enabled, again.checkIn.status, again.checkInDue.value != null), (true, StatusCode.injured, true));
      await again.dispose();
    });

    test('PANIC with only SMS left goes out at once; a normal message waits for approval', () async {
      final a = await alice.addContactFromUri(bob.myContactUri()) as ContactAdded;
      await bob.addContactFromUri(alice.myContactUri());
      final aSms = Loop('sms', PaceLayer.emergency), bSms = Loop('sms', PaceLayer.emergency);
      aSms.peer = bSms;
      bSms.peer = aSms;
      aSms.owner = () => alice;
      bSms.owner = () => bob;
      await alice.addTransport(aSms);
      await bob.addTransport(bSms);
      aSide.up = false; // no SimpleX: only "SMS"
      final adb = alice.session.db;
      final normal = await alice.sendPayload(a.contact.id, MessageType.text, encodeText('běžná'));
      expect((await (adb.select(adb.messages)..where((m) => m.id.equals(normal))).getSingle()).status, 'confirm');
      await alice.setPanic(const PanicConfig(position: false, teams: false));
      final r = await alice.sendPanic();
      await alice.awaitDelivery(r.ids, const Duration(seconds: 2));
      final row = await (adb.select(adb.messages)..where((m) => m.id.equals(r.ids.single))).getSingle();
      expect((row.status, row.via), ('delivered', 'sms'));
    });

    test('KOMPROMITOVÁN reports "compromised" without the own text', () async {
      await alice.addContactFromUri(bob.myContactUri());
      await bob.addContactFromUri(alice.myContactUri());
      await alice.setPanic(const PanicConfig(text: 'nemá jít', position: false));
      final r = await alice.sendPanic(compromised: true, position: const Position(lat: 1, lon: 2));
      expect(r.ids, hasLength(1));
      final bdb = bob.session.db;
      await until(() async => (await bdb.select(bdb.messages).get()).isNotEmpty);
      final s = Report.decode((await bdb.select(bdb.messages).getSingle()).payload) as StatusReport;
      expect(s.status, StatusCode.compromised);
      expect(s.position, isNull, reason: 'position switched off in the settings');
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

  test('PANIC settings: damaged or partial values fall back to the defaults', () {
    expect(PanicConfig.decode(null).status, StatusCode.needHelp);
    expect(PanicConfig.decode('{').button, isTrue);
    final c = PanicConfig.decode('{"status":3,"teams":false,"text":7}');
    expect((c.status, c.teams, c.text, c.contacts), (StatusCode.injured, false, '', true));
    final back = PanicConfig.decode(const PanicConfig(compromiseButton: false, text: 'x', repeatMinutes: 10).encode());
    expect((back.compromiseButton, back.text, back.repeatMinutes), (false, 'x', 10));
    expect(PanicConfig.decode('{"repeat":"x"}').repeatMinutes, 0);
  });

  test('lock settings: defaults, persisted, and only by hand keeps the four taps', () async {
    const d = LockConfig();
    expect((d.after, d.quickLock, d.biometric), (Duration.zero, true, false));
    expect(LockConfig.decode('{"after":"x"').after, Duration.zero);
    final manual = const LockConfig(quickLock: false).withAfter(null);
    expect((manual.after, manual.quickLock), (null, true));
    expect(LockConfig.decode('{"after":-1,"quick":false}').quickLock, isTrue,
        reason: 'a damaged or hand-made value must not lose the only way to lock');
    final five = LockConfig.decode(manual.withAfter(const Duration(minutes: 5)).copyWith(biometric: true).encode());
    expect((five.after, five.quickLock, five.biometric), (const Duration(minutes: 5), true, true));

    final s = await session('Alfa');
    final m = await MessagingService.start(s);
    await m.setLock(LockConfig.decode('{"after":60,"quick":false,"bio":true}'));
    await m.dispose();
    final again = await MessagingService.start(s);
    expect((again.lock.after, again.lock.quickLock, again.lock.biometric), (const Duration(minutes: 1), false, true));
    await again.dispose();
    await s.close();
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
