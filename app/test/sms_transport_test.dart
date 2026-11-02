import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:ecp_core/ecp_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l0ck_ecp/data/database.dart';
import 'package:l0ck_ecp/messaging/messaging_service.dart';
import 'package:l0ck_ecp/messaging/sms_transport.dart';
import 'package:l0ck_ecp/platform/sms.dart';
import 'package:l0ck_ecp/security/security_service.dart';

/// A pretend GSM network: numbers (as the network writes them) → phones.
class FakeGsm {
  final Map<String, FakeSms> phones = {};
  final List<(String, String, String)> log = [];
}

class FakeSms implements SmsApi {
  FakeSms(this.net, this.number, {this.credit = true}) {
    net.phones[number] = this;
  }

  final FakeGsm net;
  final String number;
  bool credit;
  final _in = StreamController<(String, String)>.broadcast();

  @override
  Future<({bool send, bool receive, bool sim})> status() async => (send: true, receive: true, sim: true);

  @override
  Future<bool> send(String to, String text) async {
    if (!credit) return false;
    net.log.add((number, to, text));
    final peer = net.phones.entries.where((e) => SmsTransport.key(e.key) == SmsTransport.key(to)).firstOrNull?.value;
    // The network rewrites the sender into international form
    peer?._in.add(('+420${SmsTransport.key(number)}', text));
    return true;
  }

  void incoming(String from, String text) => _in.add((from, text));

  @override
  Stream<(String, String)> get received => _in.stream;
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

  test('numbers match whatever form the network or the card uses', () {
    expect(SmsTransport.key('+420 601 234 567'), SmsTransport.key('00420601234567'));
    expect(SmsTransport.key('601234567'), SmsTransport.key('+420601234567'));
    expect(SmsTransport.key('601234567'), isNot(SmsTransport.key('601234568')));
  });

  test('an envelope fits plain base64url with no prefix and round-trips', () async {
    final env = randomBytes(120); // SITREP size budget, docs §4
    final text = SmsTransport.encode(env);
    expect(text.length, lessThanOrEqualTo(160));
    expect(text, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    expect(SmsTransport.decode(text), env);
    expect(SmsTransport.decode('Ahoj, zavolej mi.'), isNull);
  });

  group('two phones, SMS only', () {
    late MessagingService alice, bob;
    late FakeSms sa, sb;
    late FakeGsm net;

    Future<MessagingService> node(String name, FakeSms sms, String number) async {
      final m = await MessagingService.start(await session(name));
      await m.setOwnPhone(number);
      final t = SmsTransport(sms);
      await t.start();
      await m.addTransport(t);
      return m;
    }

    setUp(() async {
      net = FakeGsm();
      sa = FakeSms(net, '601111111');
      sb = FakeSms(net, '602222222', credit: false); // Nokia: SIM without credit
      alice = await node('Alfa', sa, '+420 601 111 111');
      bob = await node('Bravo', sb, '+420602222222');
      await alice.addContactFromUri(bob.myContactUri());
      await bob.addContactFromUri(alice.myContactUri());
    });

    tearDown(() async {
      for (final m in [alice, bob]) {
        await m.dispose();
        await m.session.close();
      }
    });

    test('the number travels on the card', () {
      expect(ContactCard.fromUri(alice.myContactUri()).phone, '+420 601 111 111');
    });

    test('SMS only after confirmation; it arrives, and the ACK cannot come back without credit', () async {
      final adb = alice.session.db, bdb = bob.session.db;
      await alice.sendText(1, 'jen SMS');
      await until(() async => (await adb.select(adb.messages).getSingle()).status == 'confirm');
      expect(net.log, isEmpty, reason: 'nothing sent before the user agrees');
      final id = (await adb.select(adb.messages).getSingle()).id;
      await alice.approveSms(id);
      await until(() async => (await bdb.select(bdb.messages).get()).isNotEmpty);
      final got = (await bdb.select(bdb.messages).get()).single;
      expect(decodeText(got.payload), 'jen SMS');
      expect(got.via, 'sms');
      expect(net.log.single.$3, isNot(contains('ECP')), reason: 'no recognisable prefix');
      // Bob's SIM has no credit: his ACK fails, Alice keeps waiting
      expect((await adb.select(adb.messages).getSingle()).status, 'sent');
    });

    test('with credit both ways the message is delivered', () async {
      sb.credit = true;
      final adb = alice.session.db;
      await alice.sendText(1, 'tam a zpět');
      await until(() async => (await adb.select(adb.messages).getSingle()).status == 'confirm');
      await alice.approveSms((await adb.select(adb.messages).getSingle()).id);
      await until(() async => (await adb.select(adb.messages).getSingle()).status == 'delivered');
      expect((await adb.select(adb.messages).getSingle()).via, 'sms');
    });

    test('SMS from unknown numbers or ordinary texts are left alone', () async {
      final bdb = bob.session.db;
      final env = SmsTransport.encode(randomBytes(60));
      sb.incoming('+420777000000', env); // stranger with an envelope-looking text
      sb.incoming('+420601111111', 'Ahoj, jsem na místě.'); // a contact, but plain text
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await bdb.select(bdb.messages).get(), isEmpty);
    });
  });
}
