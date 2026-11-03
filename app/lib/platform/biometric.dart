import 'package:flutter/services.dart';

/// The system fingerprint prompt (MainActivity, Android 11+, strong biometrics only). It only
/// gates the screen of a profile that is already open: no key depends on it.
abstract final class Biometric {
  static const _channel = MethodChannel('cz.l0ck.ecp/biometric');

  /// A fingerprint is enrolled and the sensor is usable.
  static Future<bool> available() async {
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } on Object {
      return false; // older Android, tests
    }
  }

  /// Shows the prompt; true once a finger matched, false when cancelled or locked out.
  static Future<bool> authenticate({required String title, required String cancel}) async {
    try {
      return await _channel.invokeMethod<bool>('authenticate', {'title': title, 'cancel': cancel}) ?? false;
    } on Object {
      return false;
    }
  }
}
