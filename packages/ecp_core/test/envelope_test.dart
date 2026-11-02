import 'dart:typed_data';

import 'package:ecp_core/ecp_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 1, 12);
  late PairKeys a, b;
  late EcpIdentity alice, bob;

  setUp(() async {
    alice = await EcpIdentity.generate();
    bob = await EcpIdentity.generate();
    a = await derivePairKeys(alice, bob.publicKey);
    b = await derivePairKeys(bob, alice.publicKey);
  });

  InnerMessage text(String s, {int flags = 0}) => InnerMessage.create(
        type: MessageType.text,
        payload: encodeText(s),
        flags: flags,
        now: now,
      );

  test('pair envelope round-trips and maps back to the contact', () async {
    final m = text('rally at the bridge', flags: MessageFlags.ackRequested);
    final sealed = await EcpEnvelope.seal(
        kind: EnvelopeKind.pair, key: a.send, message: m, now: now);
    expect(sealed.length, EcpEnvelope.overhead + EcpEnvelope.innerHeaderLength + m.payload.length);

    final opened = await EcpEnvelope.open(
        sealed, [KeyCandidate(EnvelopeKind.pair, b.recv, 'alice')], now: now);
    expect(opened, isNotNull);
    expect(opened!.via.owner, 'alice');
    expect(decodeText(opened.message.payload), 'rally at the bridge');
    expect(opened.message.id, m.id);
    expect(opened.message.sentAt, m.sentAt);
    expect(opened.message.wantsAck, isTrue);
  });

  test('wrong key, reflected message and other contacts do not open it', () async {
    final sealed = await EcpEnvelope.seal(
        kind: EnvelopeKind.pair, key: a.send, message: text('x'), now: now);
    final carol = await EcpIdentity.generate();
    final c = await derivePairKeys(carol, alice.publicKey);
    expect(await EcpEnvelope.open(sealed, [KeyCandidate(EnvelopeKind.pair, c.recv)], now: now),
        isNull);
    // Alice cannot open her own message with her receive key (no reflection)
    expect(await EcpEnvelope.open(sealed, [KeyCandidate(EnvelopeKind.pair, a.recv)], now: now),
        isNull);
  });

  test('finds the right key among many candidates', () async {
    final others = [
      for (var i = 0; i < 20; i++)
        KeyCandidate(EnvelopeKind.pair, randomBytes(32), 'other$i'),
    ];
    final sealed = await EcpEnvelope.seal(
        kind: EnvelopeKind.pair, key: a.send, message: text('hi'), now: now);
    final opened = await EcpEnvelope.open(
        sealed, [...others, KeyCandidate(EnvelopeKind.pair, b.recv, 'alice')], now: now);
    expect(opened?.via.owner, 'alice');
  });

  test('any flipped bit is rejected', () async {
    final sealed = await EcpEnvelope.seal(
        kind: EnvelopeKind.pair, key: a.send, message: text('integrity'), now: now);
    for (var i = 0; i < sealed.length; i++) {
      final bad = Uint8List.fromList(sealed)..[i] ^= 0x01;
      expect(
          await EcpEnvelope.open(bad, [KeyCandidate(EnvelopeKind.pair, b.recv)], now: now),
          isNull,
          reason: 'byte $i');
    }
  });

  test('accepts yesterday and tomorrow, rejects a week later', () async {
    final sealed = await EcpEnvelope.seal(
        kind: EnvelopeKind.pair, key: a.send, message: text('t'), now: now);
    final cand = [KeyCandidate(EnvelopeKind.pair, b.recv)];
    expect(await EcpEnvelope.open(sealed, cand, now: now.add(const Duration(days: 1))),
        isNotNull);
    expect(await EcpEnvelope.open(sealed, cand, now: now.subtract(const Duration(days: 1))),
        isNotNull);
    expect(await EcpEnvelope.open(sealed, cand, now: now.add(const Duration(days: 7))),
        isNull);
  });

  test('team envelope carries the sender fingerprint', () async {
    final teamKey = randomBytes(32);
    final fp = await senderFingerprint(alice.publicKey);
    final m = InnerMessage.create(
        type: MessageType.report,
        payload: const StatusReport(StatusCode.ok).encode(),
        senderFingerprint: fp,
        now: now);
    final sealed = await EcpEnvelope.seal(
        kind: EnvelopeKind.team, key: teamKey, message: m, now: now);
    expect(await EcpEnvelope.open(sealed, [KeyCandidate(EnvelopeKind.pair, teamKey)], now: now),
        isNull,
        reason: 'kind must match');
    final opened = await EcpEnvelope.open(
        sealed, [KeyCandidate(EnvelopeKind.team, teamKey)], now: now);
    expect(opened!.message.senderFingerprint, fp);
    expect(Report.decode(opened.message.payload), isA<StatusReport>());
  });

  test('team envelope without fingerprint is refused at seal time', () async {
    expect(
        () => EcpEnvelope.seal(
            kind: EnvelopeKind.team, key: randomBytes(32), message: text('x'), now: now),
        throwsArgumentError);
  });

  test('replay guard accepts once, refuses stale messages', () async {
    final guard = ReplayGuard();
    final m = text('once');
    expect(guard.accept(m, now: now), isTrue);
    expect(guard.accept(m, now: now), isFalse);
    final old = InnerMessage.create(
        type: MessageType.text,
        payload: encodeText('old'),
        now: now.subtract(const Duration(days: 30)));
    expect(guard.accept(old, now: now), isFalse);
    final restored = ReplayGuard.restore(guard.export());
    expect(restored.accept(m, now: now), isFalse, reason: 'survives a restart');
  });

  test('regression vector: fixed key, nonce, id and time give fixed bytes', () async {
    // Pins the v1 wire format. Any change here breaks compatibility with deployed devices.
    final key = fromHex('000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f');
    final m = InnerMessage(
      type: MessageType.text,
      flags: MessageFlags.ackRequested,
      id: fromHex('0102030405060708'),
      sentAt: ecpTime(now),
      payload: encodeText('L0ck'),
    );
    final sealed = await EcpEnvelope.seal(
        kind: EnvelopeKind.pair,
        key: key,
        message: m,
        now: now,
        nonce: fromHex('a0a1a2a3a4a5a6a7a8a9aaab'));
    expect(toHex(sealed.sublist(0, 1)), '10'); // version 1, pair
    expect(toHex(sealed.sublist(3, 15)), 'a0a1a2a3a4a5a6a7a8a9aaab');
    expect(sealed.length, 31 + 14 + 4);
    final opened =
        await EcpEnvelope.open(sealed, [KeyCandidate(EnvelopeKind.pair, key)], now: now);
    expect(decodeText(opened!.message.payload), 'L0ck');
    expect(toHex(sealed), _pinnedVector);
  });
}

// Generated once by this implementation and pinned (see test above).
const _pinnedVector = '108b1ca0a1a2a3a4a5a6a7a8a9aaab0eaa795d4ee2c7aba707f641d5bab1cbfe'
    '353ad6057b2f5559b14ebab11aa4d57cbd';
