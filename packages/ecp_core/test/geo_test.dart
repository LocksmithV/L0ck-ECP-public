import 'package:ecp_core/ecp_core.dart';
import 'package:test/test.dart';

void main() {
  const prague = Position(lat: 50.0880, lon: 14.4208);
  const brno = Position(lat: 49.1951, lon: 16.6068);

  test('distance Prague–Brno about 185 km', () {
    expect(distanceMeters(prague, brno) / 1000, closeTo(185.5, 2));
    expect(distanceMeters(prague, prague), 0);
  });

  test('bearing: Brno lies south-east of Prague, and back', () {
    expect(bearingDegrees(prague, brno), closeTo(122, 2));
    expect(bearingDegrees(brno, prague), closeTo(304, 2));
    expect(bearingDegrees(const Position(lat: 0, lon: 0), const Position(lat: 1, lon: 0)), closeTo(0, 0.01));
  });

  test('formatting', () {
    expect(formatDistance(850), '850 m');
    expect(formatDistance(12400), '12,4 km');
    expect(formatBearing(243), '243° JZ');
    expect(formatBearing(359), '359° S');
    expect(formatLatLon(prague), '50.08800 N, 14.42080 E');
  });
}
