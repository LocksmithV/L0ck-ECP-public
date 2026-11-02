import 'dart:math';

import 'messages.dart';

/// Great-circle distance in metres (haversine on a 6 371 km sphere; < 0.5 % off WGS-84,
/// plenty for "how far is the sender").
double distanceMeters(Position a, Position b) {
  const r = 6371000.0;
  final dLat = _rad(b.lat - a.lat), dLon = _rad(b.lon - a.lon);
  final h = pow(sin(dLat / 2), 2) + cos(_rad(a.lat)) * cos(_rad(b.lat)) * pow(sin(dLon / 2), 2);
  return 2 * r * asin(min(1.0, sqrt(h)));
}

/// Initial bearing from [a] to [b], degrees clockwise from true north (0–360).
double bearingDegrees(Position a, Position b) {
  final p1 = _rad(a.lat), p2 = _rad(b.lat), dLon = _rad(b.lon - a.lon);
  final y = sin(dLon) * cos(p2);
  final x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dLon);
  return (atan2(y, x) * 180 / pi + 360) % 360;
}

/// "850 m" / "12,4 km".
String formatDistance(double m) => m < 1000
    ? '${m.round()} m'
    : '${(m / 1000).toStringAsFixed(m < 100000 ? 1 : 0).replaceAll('.', ',')} km';

/// Bearing with its 8-point compass name: "243° JZ".
String formatBearing(double deg) {
  const names = ['S', 'SV', 'V', 'JV', 'J', 'JZ', 'Z', 'SZ'];
  return '${deg.round() % 360}° ${names[((deg + 22.5) % 360 ~/ 45)]}';
}

/// "50.08804 N, 14.42076 E" — decimal degrees, 5 places (about 1 m).
String formatLatLon(Position p) =>
    '${p.lat.abs().toStringAsFixed(5)} ${p.lat >= 0 ? 'N' : 'S'}, '
    '${p.lon.abs().toStringAsFixed(5)} ${p.lon >= 0 ? 'E' : 'W'}';

double _rad(double d) => d * pi / 180;
