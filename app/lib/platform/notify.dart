import 'package:flutter/services.dart';

/// "New message" notifications without content (android/…/notify/NotifyHost.java).
abstract final class Notifications {
  static const _m = MethodChannel('cz.l0ck.ecp/notify');

  /// [open]: `c:CONTACT_ID` or `t:TEAM_ID`, where a tap leads after the PIN.
  static Future<void> message(int count, {String? open}) =>
      _m.invokeMethod('message', {'count': count, 'open': open});

  /// The conversation of the last tapped notification, once.
  static Future<String?> takeOpen() =>
      const MethodChannel('cz.l0ck.ecp/activity').invokeMethod<String>('takeOpen');

  static Future<void> clear() => _m.invokeMethod('clear');
}
