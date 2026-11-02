import 'package:ecp_core/ecp_core.dart';
import 'package:test/test.dart';

void main() {
  late EcpIdentity me;

  setUp(() async => me = await EcpIdentity.generate());

  test('full card round-trips through the l0ck:// URI', () {
    final card = ContactCard(
      name: 'Kos',
      ecpKey: me.publicKey,
      briarLink: 'briar://ad4otnwxdu5h2nyfg3gqbreh37oq6m2hhj4njlnkcg7j45fxt43cc',
      simplexLink: 'https://simplex.chat/contact#/?v=2-7&smp=smp%3A%2F%2Fexample',
      phone: '+420600000000',
      meshtasticNodeId: 0xdeadbeef,
      meshcoreKey: randomBytes(32),
    );
    final uri = card.toUri();
    expect(uri, startsWith('l0ck://c/'));
    expect(uri, isNot(contains('=')));
    final back = ContactCard.fromUri(uri);
    expect(back.name, 'Kos');
    expect(back.ecpKey, me.publicKey);
    expect(back.briarLink, card.briarLink);
    expect(back.simplexLink, card.simplexLink);
    expect(back.phone, '+420600000000');
    expect(back.meshtasticNodeId, 0xdeadbeef);
    expect(back.meshcoreKey, card.meshcoreKey);
    expect(back.isTeamCard, isFalse);
  });

  test('minimal card and team card', () {
    final minimal = ContactCard.fromUri(ContactCard(name: 'A', ecpKey: me.publicKey).toUri());
    expect(minimal.briarLink, isNull);
    final team = ContactCard(name: 'Lead', ecpKey: me.publicKey, teamKey: randomBytes(32));
    expect(ContactCard.decode(team.encode()).isTeamCard, isTrue);
  });

  test('unknown fields are skipped (forward compatible)', () {
    final enc = ContactCard(name: 'A', ecpKey: me.publicKey).encode();
    final withExtra = [...enc, 0x7e, 0x00, 0x03, 1, 2, 3];
    expect(ContactCard.decode(withExtra).name, 'A');
  });

  test('broken cards are refused', () {
    expect(() => ContactCard(name: '', ecpKey: me.publicKey), throwsArgumentError);
    expect(() => ContactCard(name: 'x' * 25, ecpKey: me.publicKey), throwsArgumentError);
    expect(() => ContactCard(name: 'A', ecpKey: randomBytes(31)), throwsArgumentError);
    expect(() => ContactCard.decode([1]), throwsFormatException); // wrong version
    expect(() => ContactCard.decode([2]), throwsFormatException); // no name / key
    final enc = ContactCard(name: 'A', ecpKey: me.publicKey).encode();
    expect(() => ContactCard.decode(enc.sublist(0, enc.length - 1)), throwsFormatException);
    expect(() => ContactCard.fromUri('https://example.com'), throwsFormatException);
  });
}
