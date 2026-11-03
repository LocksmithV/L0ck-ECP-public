import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l0ck_ecp/data/database.dart';
import 'package:l0ck_ecp/messaging/call_service.dart';
import 'package:l0ck_ecp/messaging/messaging_service.dart';
import 'package:l0ck_ecp/security/security_service.dart';

import 'messaging_service_test.dart' show Loop, until;

/// WebRTC stand-in: SDP is a label, the "connection" comes up once both sides have each
/// other's description.
class FakeMedia implements CallMedia {
  FakeMedia(this.name);

  final String name;
  final _up = StreamController<bool>.broadcast();
  bool closed = false, muted = false;

  @override
  Stream<bool> get connected => _up.stream;

  @override
  Future<String> offer() async => 'offer from $name';

  @override
  Future<String> answer(String offer) async {
    Timer(const Duration(milliseconds: 20), () => _up.add(true));
    return 'answer from $name to [$offer]';
  }

  @override
  Future<void> accepted(String answer) async => Timer(const Duration(milliseconds: 20), () => _up.add(true));

  @override
  Future<void> mute(bool on) async => muted = on;

  @override
  Future<void> speaker(bool on) async {}

  @override
  Future<bool?> relayed() async => false;

  @override
  Future<void> close() async => closed = true;

  void drop() => _up.add(false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late MessagingService alice, bob;
  late CallService aCalls, bCalls;
  late List<FakeMedia> aMedia, bMedia;
  late Contact bobAtAlice;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('cz.l0ck.ecp/permissions'), (_) async => true);
    final aSide = Loop('simplex', PaceLayer.primary), bSide = Loop('simplex', PaceLayer.primary);
    aSide.peer = bSide;
    bSide.peer = aSide;
    Future<Session> s(String n) async =>
        Session(randomBytes(32), EcpDatabase(NativeDatabase.memory()), await EcpIdentity.generate(), n);
    alice = await MessagingService.start(await s('Alfa'), transports: [aSide]);
    bob = await MessagingService.start(await s('Bravo'), transports: [bSide]);
    aSide.owner = () => alice;
    bSide.owner = () => bob;
    bobAtAlice = (await alice.addContactFromUri(bob.myContactUri()) as ContactAdded).contact;
    await bob.addContactFromUri(alice.myContactUri());
    aMedia = [];
    bMedia = [];
    aCalls = CallService(alice, media: () => FakeMedia('alice')..let(aMedia.add));
    bCalls = CallService(bob, media: () => FakeMedia('bob')..let(bMedia.add), ringFor: const Duration(milliseconds: 300));
  });

  tearDown(() async {
    for (final m in [alice, bob]) {
      await m.dispose();
      await m.session.close();
    }
  });

  Future<List<int>> log(MessagingService m) async {
    final db = m.session.db;
    return [
      for (final r in await (db.select(db.messages)..where((t) => t.type.equals(MessagingService.callLogType))).get())
        r.payload[0]
    ];
  }

  test('a call rings, is answered, both sides talk, one hangs up; both log it', () async {
    CallState? incoming;
    bCalls.onIncoming = (c) => incoming = c;
    expect(await aCalls.call(bobAtAlice, noChannel: 'x', noMic: 'y'), isNull);
    expect(aCalls.current.value!.phase, CallPhase.calling);
    await until(() async => incoming != null);
    expect((incoming!.contact.name, incoming!.outgoing, bCalls.current.value!.phase), ('Alfa', false, CallPhase.ringing));

    await bCalls.accept(noMic: 'y');
    expect(bMedia.single.closed, isFalse);
    await until(() async => aCalls.current.value?.phase == CallPhase.active && bCalls.current.value?.phase == CallPhase.active);
    expect(aCalls.current.value!.relayed, isFalse);

    await aCalls.toggleMute();
    expect(aMedia.single.muted, isTrue);

    await aCalls.hangUp();
    await until(() async => bCalls.current.value?.phase == CallPhase.ended);
    expect((aMedia.single.closed, bMedia.single.closed), (true, true));
    expect(await log(alice), [MessagingService.callAnswered]);
    expect(await log(bob), [MessagingService.callAnswered]);
  });

  test('declined; a second caller hears busy; an unanswered call is missed', () async {
    await aCalls.call(bobAtAlice, noChannel: 'x', noMic: 'y');
    await until(() async => bCalls.current.value?.phase == CallPhase.ringing);
    await bCalls.decline();
    await until(() async => aCalls.current.value?.phase == CallPhase.ended);
    expect(aCalls.current.value!.reason, CallSignal.declined);
    expect(await log(alice), [MessagingService.callDeclined]);

    // Bob is in another call: Alice hears busy
    await until(() async => aCalls.current.value == null && bCalls.current.value == null);
    bCalls.current.value = CallState(contact: bobAtAlice, outgoing: true, phase: CallPhase.active);
    await aCalls.call(bobAtAlice, noChannel: 'x', noMic: 'y');
    await until(() async => aCalls.current.value?.phase == CallPhase.ended);
    expect(aCalls.current.value!.reason, CallSignal.busy);
    bCalls.current.value = null;

    // Nobody answers: Bob's phone stops ringing and logs a missed call
    await until(() async => aCalls.current.value == null);
    await aCalls.call(bobAtAlice, noChannel: 'x', noMic: 'y');
    await until(() async => bCalls.current.value?.phase == CallPhase.ringing);
    await until(() async => bCalls.current.value?.phase == CallPhase.ended);
    expect(await log(bob), contains(MessagingService.callMissed));
    await aCalls.hangUp();
  });

  test('no SimpleX/Bramble: no call', () async {
    (alice.router.transports.single as Loop).up = false;
    expect(alice.canCall(bobAtAlice.id), isFalse);
    expect(await aCalls.call(bobAtAlice, noChannel: 'none', noMic: 'y'), 'none');
    expect(aCalls.current.value, isNull);
  });
}

extension<T> on T {
  void let(void Function(T) f) => f(this);
}
