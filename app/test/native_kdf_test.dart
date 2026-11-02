import 'dart:typed_data';

import 'package:ecp_core/ecp_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l0ck_ecp/security/native_kdf.dart';

/// libsodium's Argon2id must produce exactly what ecp_core's pure-Dart Argon2id produces;
/// otherwise a slot written by one could not be opened by the other.
void main() {
  late NativeArgon2 native;

  setUpAll(() async => native = await NativeArgon2.init());

  final salt = Uint8List.fromList(List.generate(16, (i) => i * 7));

  for (final kdf in const [
    KdfParams(memoryKiB: 64, iterations: 1, parallelism: 1),
    KdfParams(memoryKiB: 8 * 1024, iterations: 2, parallelism: 1),
    KdfParams.production(),
  ]) {
    test('native == Dart for m=${kdf.memoryKiB} KiB, t=${kdf.iterations}', () async {
      final a = await native.stretch('482913', salt, kdf);
      final b = await argon2idStretch('482913', salt, kdf);
      expect(toHex(a), toHex(b));
      expect(a, hasLength(32));
    });
  }

  test('a slot created natively opens with the Dart stretcher and vice versa', () async {
    const kdf = KdfParams(memoryKiB: 1024, iterations: 2, parallelism: 1);
    final c = await KeySlots.create(pin: '135790', kdf: kdf, stretch: native.stretch);
    expect((await KeySlots.unlock(c.file, '135790'))!.masterKey, c.realMasterKey);
    final d = await KeySlots.create(pin: '246801', kdf: kdf);
    expect((await KeySlots.unlock(d.file, '246801', stretch: native.stretch))!.masterKey, d.realMasterKey);
  });

  test('parallelism other than 1 is refused (libsodium limitation)', () {
    expect(
      () => native.stretch('1', salt, const KdfParams(memoryKiB: 64, iterations: 1, parallelism: 2)),
      throwsArgumentError,
    );
  });
}
