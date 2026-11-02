import 'package:ecp_core/ecp_core.dart';
import 'package:test/test.dart';

void main() {
  late EcpIdentity alice, bob;

  setUp(() async {
    alice = await EcpIdentity.generate();
    bob = await EcpIdentity.generate();
  });

  test('pair keys match crosswise and differ per direction', () async {
    final a = await derivePairKeys(alice, bob.publicKey);
    final b = await derivePairKeys(bob, alice.publicKey);
    expect(a.send, b.recv);
    expect(a.recv, b.send);
    expect(a.send, isNot(a.recv));
  });

  test('identity survives export/import of the private key', () async {
    final restored = await EcpIdentity.fromPrivateKey(await alice.privateKeyBytes());
    expect(restored.publicKey, alice.publicKey);
    final a = await derivePairKeys(restored, bob.publicKey);
    final b = await derivePairKeys(bob, alice.publicKey);
    expect(a.send, b.recv);
  });

  test('rejects own key, wrong length and low-order points', () async {
    expect(() => derivePairKeys(alice, alice.publicKey), throwsArgumentError);
    expect(() => derivePairKeys(alice, List.filled(31, 1)), throwsArgumentError);
    // u = 0 is a low-order point: shared secret would be all zeros
    expect(() => derivePairKeys(alice, List.filled(32, 0)), throwsArgumentError);
  });

  test('verification number is the same on both sides and 12 digits', () async {
    final n1 = await verificationNumber(alice.publicKey, bob.publicKey);
    final n2 = await verificationNumber(bob.publicKey, alice.publicKey);
    expect(n1, n2);
    expect(n1, matches(RegExp(r'^\d{4} \d{4} \d{4}$')));
    final carol = await EcpIdentity.generate();
    expect(await verificationNumber(alice.publicKey, carol.publicKey), isNot(n1));
  });

  test('tags rotate daily and depend on the key', () async {
    final k = (await derivePairKeys(alice, bob.publicKey)).send;
    final day = utcDay(DateTime.utc(2026, 11, 1));
    expect(await envelopeTag(k, day), hasLength(2));
    expect(await envelopeTag(k, day), await envelopeTag(k, day));
    // 2-byte tags may collide by chance; over a week of days they must not all match
    final week = [for (var d = day; d < day + 7; d++) toHex(await envelopeTag(k, d))];
    expect(week.toSet().length, greaterThan(1));
  });

  test('subkeys are purpose-bound', () async {
    final mk = List<int>.generate(32, (i) => i);
    final db = await deriveSubkey(mk, 'db');
    expect(db, hasLength(32));
    expect(await deriveSubkey(mk, 'db'), db);
    expect(await deriveSubkey(mk, 'bramble'), isNot(db));
  });
}
