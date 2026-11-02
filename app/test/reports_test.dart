import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:l0ck_ecp/l10n/lang.dart';
import 'package:l0ck_ecp/platform/location.dart';
import 'package:l0ck_ecp/ui/reports.dart';

void main() {
  setUp(() => Lang.current.value = const Locale('cs'));

  test('typed coordinates in the usual forms', () {
    final a = Locator.parse('50.0880, 14.4208')!;
    expect(a.lat, 50.088);
    expect(a.lon, 14.4208);
    expect(Locator.parse('50,0880; 14,4208')!.lon, 14.4208, reason: 'Czech decimal comma');
    expect(Locator.parse('50.0880 N 14.4208 E')!.lat, 50.088);
    expect(Locator.parse('33.9 S, 18.4 E')!.lat, -33.9);
    expect(Locator.parse('95, 14'), isNull);
    expect(Locator.parse('jen text'), isNull);
  });

  test('every report reads back as text for copying', () {
    const p = Position(lat: 50.088, lon: 14.4208, accuracy: 6);
    expect(reportText(MessageType.position, p.encode()), 'POLOHA 50.08800 N, 14.42080 E');
    expect(
      reportText(MessageType.report, const StatusReport(StatusCode.needHelp, p).encode()),
      startsWith('STATUS Potřebuji pomoc 50.08800 N'),
    );
    final sitrep = SitrepReport(state: 2, persons: 3, position: p, text: 'u mostu').encode();
    expect(reportText(MessageType.report, sitrep), contains('Kontakt, osob 3'));
    final medevac = MedevacReport(
      location: p,
      callsign: 'SOKOL1',
      patientsByPrecedence: [1, 0, 0, 0, 0],
      equipment: 0,
      litter: 1,
      ambulatory: 0,
      security: 1,
      marking: 2,
      nationality: 0,
      terrain: 0,
    ).encode();
    expect(reportText(MessageType.report, medevac), startsWith('MEDEVAC SOKOL1'));
  });

  test('SALTER and 5W read back in the chosen language', () {
    const p = Position(lat: 50.088, lon: 14.4208);
    final at = DateTime(2026, 11, 2, 14, 5);
    final salter = SalterReport(
      size: 4,
      activity: 'kopou zákop',
      location: p,
      time: at,
      equipment: '2 vozidla',
    ).encode();
    final fiveW = FiveWReport(who: 'hlídka', what: 'zátaras', where: p, when: at).encode();
    expect(
      reportText(MessageType.report, salter),
      allOf(
        contains('S velikost: 4'),
        contains('A činnost: kopou zákop'),
        contains('E vybavení: 2 vozidla'),
        isNot(contains('R poznámky')),
      ),
    );
    expect(
      reportText(MessageType.report, fiveW),
      allOf(startsWith('5W'), contains('Kdo: hlídka'), isNot(contains('Proč'))),
    );
    Lang.current.value = const Locale('en');
    expect(reportText(MessageType.report, salter), contains('S size: 4'));
    expect(reportText(MessageType.report, fiveW), contains('What: zátaras'));
    expect(reportText(MessageType.position, p.encode()), startsWith('POSITION'));
  });
}
