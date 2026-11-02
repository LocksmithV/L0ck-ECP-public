import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'radio.dart' show Permissions;
import '../l10n/lang.dart';

class LocationError implements Exception {
  const LocationError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One position from the phone (android/…/location/LocationHost.java): GPS, network, or a
/// fresh last fix. Asked only when the user sends a report or looks at one.
abstract final class Locator {
  static const _m = MethodChannel('cz.l0ck.ecp/location');

  /// The latest own fix, for distance and bearing to reports.
  static final ValueNotifier<Position?> last = ValueNotifier(null);

  static Future<Position> current({Duration timeout = const Duration(seconds: 30)}) async {
    await Permissions.request(const [
      'android.permission.ACCESS_FINE_LOCATION',
      'android.permission.ACCESS_COARSE_LOCATION',
    ]);
    try {
      final m = Map<String, Object?>.from(
          (await _m.invokeMethod<Map>('current', {'timeoutMs': timeout.inMilliseconds}))!);
      final p = Position(
        lat: m['lat'] as double,
        lon: m['lon'] as double,
        altitude: (m['alt'] as double?)?.round(),
        accuracy: (m['acc'] as double?)?.round(),
        course: m['course'] as double?,
        speed: m['speed'] as double?,
      );
      last.value = p;
      return p;
    } on PlatformException catch (e) {
      throw LocationError(switch (e.code) {
        'NO_PERMISSION' => Lang.tr.locNoPermission,
        'OFF' => Lang.tr.locOff,
        'TIMEOUT' => Lang.tr.locTimeout,
        _ => Lang.tr.locFailed,
      });
    }
  }

  /// Opens the coordinates in an installed map app (OsmAnd, Organic Maps…); false if none.
  static Future<bool> openInMap(Position p, String label) async =>
      await const MethodChannel('cz.l0ck.ecp/activity').invokeMethod<bool>('openGeo', {
        'uri': 'geo:${p.lat},${p.lon}?q=${p.lat},${p.lon}(${Uri.encodeComponent(label)})',
      }) ??
      false;

  /// "50.0880, 14.4208", "50.0880 N 14.4208 E", "50,0880; 14,4208" → position, else null.
  static Position? parse(String text) {
    // Decimal comma → point (replaceAll would not expand $1, hence replaceAllMapped)
    final t = text.toUpperCase().replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}.${m[2]}');
    final nums = RegExp(r'-?\d+(\.\d+)?').allMatches(t).map((m) => double.parse(m[0]!)).toList();
    if (nums.length != 2) return null;
    var lat = nums[0], lon = nums[1];
    if (t.contains('S')) lat = -lat.abs();
    if (t.contains('W')) lon = -lon.abs();
    if (lat.abs() > 90 || lon.abs() > 180) return null;
    return Position(lat: lat, lon: lon);
  }
}
