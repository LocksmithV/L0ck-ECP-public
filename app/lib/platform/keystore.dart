import 'package:flutter/services.dart';

/// Dart side of `KeystoreStrengthener` in MainActivity.kt: binds PIN-derived keys to this
/// device's Keystore (docs/ARCHITECTURE_V2.md §6).
class Keystore {
  const Keystore();

  static const _channel = MethodChannel('cz.l0ck.ecp/keystore');

  /// HMAC-SHA256 under the device-bound key; 32 bytes out.
  Future<List<int>> strengthen(List<int> key) async {
    final out = await _channel.invokeMethod<Uint8List>(
      'strengthen',
      {'key': Uint8List.fromList(key)},
    );
    if (out == null || out.length != 32) {
      throw StateError('Keystore returned no key');
    }
    return out;
  }

  /// After this no slot can ever be opened again on this device.
  Future<void> deleteKey() => _channel.invokeMethod<void>('deleteKey');
}
