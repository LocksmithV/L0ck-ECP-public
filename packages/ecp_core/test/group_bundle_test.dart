import 'dart:io';
import 'dart:typed_data';

import 'package:ecp_core/ecp_core.dart';
import 'package:test/test.dart';

ContactCard card(String name, int seed) => ContactCard(
      name: name,
      ecpKey: Uint8List.fromList(List.filled(32, seed)),
      simplexLink: 'https://smp.example/a#/?v=1&smp=${'x' * 300}$seed',
      phone: '+420 600 000 00$seed',
    );

GroupBundle sample() => GroupBundle(
      members: [card('Alfa', 1), card('Bravo', 2), card('Charlie', 3)],
      teams: [
        GroupTeam(name: 'Hlídka', key: Uint8List.fromList(List.filled(32, 9)), members: [0, 1, 2]),
        GroupTeam(name: 'Zdravotníci', key: Uint8List.fromList(List.filled(32, 8)), members: [1]),
      ],
      loraTeam: 0,
      pace: [PaceLayer.alternate, PaceLayer.primary, PaceLayer.contingency, PaceLayer.emergency],
    );

void main() {
  test('round trip: members, teams, LoRa team, PACE order', () {
    final b = GroupBundle.decode(sample().encode());
    expect(b.members.map((m) => m.name), ['Alfa', 'Bravo', 'Charlie']);
    expect(b.members[2].phone, '+420 600 000 003');
    expect(b.teams.map((t) => t.name), ['Hlídka', 'Zdravotníci']);
    expect(b.teams.map((t) => t.members), [[0, 1, 2], [1]]);
    expect(b.teams[1].key, List.filled(32, 8));
    expect(b.loraTeam, 0);
    expect(b.pace!.first, PaceLayer.alternate);
    expect(b.indexOf(List.filled(32, 2)), 1);
    expect(b.indexOf(List.filled(32, 7)), isNull);
  });

  test('without teams, LoRa or PACE the phones keep their own', () {
    final b = GroupBundle.decode(GroupBundle(members: [card('Alfa', 1)]).encode());
    expect(b.teams, isEmpty);
    expect((b.loraTeam, b.pace), (null, null));
  });

  test('damaged bundles are refused', () {
    final data = sample().encode();
    expect(() => GroupBundle.decode(data.sublist(0, data.length - 1)), throwsFormatException);
    expect(() => GroupBundle.decode([...data, 0]), throwsFormatException);
    expect(() => GroupBundle.decode([0x47, 9, ...data.sublist(2)]), throwsFormatException);
    final badIndex = Uint8List.fromList(data);
    // the last team's single member index sits just before loraTeam, p and 4 layers
    badIndex[data.length - 7] = 5;
    expect(() => GroupBundle.decode(badIndex), throwsFormatException);
    expect(() => GroupBundle(members: [card('A', 1)], loraTeam: 0), throwsArgumentError);
    expect(() => GroupBundle(members: [card('A', 1)], pace: [PaceLayer.primary]), throwsArgumentError);
  });

  test('QR parts reassemble in any order; another bundle or junk is refused', () {
    final data = sample().encode();
    final parts = GroupBundle.toQrParts(data, id: '0a1b2c3d', chunk: 300);
    expect(parts.length, (data.length + 299) ~/ 300);
    expect(parts.every((p) => p.startsWith('l0ck://g/0a1b2c3d/')), isTrue);
    final a = GroupBundleAssembler();
    for (final p in parts.reversed) {
      expect(a.complete, isFalse);
      a.add(p);
      a.add(p); // the same part twice is harmless
    }
    expect((a.have, a.total, a.complete), (parts.length, parts.length, true));
    expect(a.bundle().members.length, 3);

    final b = GroupBundleAssembler()..add(parts.first);
    expect(b.next, 2);
    expect(() => b.add(GroupBundle.toQrParts(data, id: 'ffffffff', chunk: 300)[1]), throwsFormatException);
    expect(() => b.add('l0ck://c/AAAA'), throwsFormatException);
    expect(() => b.add('l0ck://g/0a1b2c3d/9/2/AA'), throwsFormatException);
    expect(() => b.bundle(), throwsStateError);
  });

  test('a bundle made by the base page (tools/ecp_base/bundle.js) decodes here', () {
    // Written by `node tools/ecp_base/test/bundle_test.js --write`
    final a = GroupBundleAssembler();
    for (final line in File('test/fixtures/group_bundle_js.txt').readAsLinesSync().reversed) {
      a.add(line);
    }
    final b = a.bundle();
    expect(b.members.map((m) => m.name), ['Alfa', 'Bravo', 'Čáp']);
    expect(b.members[1].simplexLink, startsWith('https://simplex.example/'));
    expect(b.teams.map((t) => t.name), ['Hlídka', 'Spojka']);
    expect(b.teams[0].key, List.filled(32, 9));
    expect(b.teams[1].members, [1]);
    expect(b.loraTeam, 0);
    expect(b.pace, [PaceLayer.alternate, PaceLayer.primary, PaceLayer.contingency, PaceLayer.emergency]);
    expect(b.indexOf(List.filled(32, 3)), 2);
  });
}
