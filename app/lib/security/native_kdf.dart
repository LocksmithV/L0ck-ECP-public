import 'dart:convert';
import 'dart:typed_data';

import 'package:ecp_core/ecp_core.dart';
import 'package:sodium/sodium_sumo.dart';

/// Argon2id from libsodium (C). Same RFC 9106 v1.3 output as ecp_core's pure-Dart
/// [argon2idStretch], so slot files stay compatible — just far faster on a phone CPU,
/// which lets the production cost (64 MiB, t = 3) stay in place.
class NativeArgon2 {
  NativeArgon2._(this._sodium);

  final SodiumSumo _sodium;

  static Future<NativeArgon2> init() async => NativeArgon2._(await SodiumSumoInit.init());

  /// A [PinStretcher] that runs in a background isolate.
  Future<Uint8List> stretch(String pin, Uint8List salt, KdfParams kdf) {
    if (kdf.parallelism != 1) {
      throw ArgumentError('libsodium Argon2id only supports parallelism 1');
    }
    final sodium = _sodium;
    return sodium.runIsolated((_, _) {
      final key = sodium.crypto.pwhash.callRaw(
        outLen: 32,
        password: Int8List.fromList(utf8.encode(pin)),
        salt: salt,
        opsLimit: kdf.iterations,
        memLimit: kdf.memoryKiB * 1024,
        alg: CryptoPwhashAlgorithm.argon2id13,
      );
      try {
        return key.extractBytes();
      } finally {
        key.dispose();
      }
    });
  }
}
