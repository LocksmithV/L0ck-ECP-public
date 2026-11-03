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

  /// An incoming call rings with [text] (no caller shown); a tap opens the app at `k:CONTACT_ID`.
  static Future<void> call(String text, {String? open}) => _m.invokeMethod('call', {'text': text, 'open': open});

  static Future<void> callEnd() => _m.invokeMethod('callEnd');

  /// A reminder from the app (the check-in is due soon).
  static Future<void> reminder(String text) => _m.invokeMethod('reminder', {'text': text});
}
