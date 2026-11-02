import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'bytes.dart';
import 'envelope.dart' show randomBytes;

/// PIN-protected master-key slots with a duress decoy (docs/ARCHITECTURE_V2.md §6).
///
/// There is no stored PIN hash and no "duress" field. The file always holds two slots of
/// identical size in random order; without a duress code the second one is random noise.
/// A PIN unlocks whichever slot it fits; the slot itself says real or decoy.

const _slotAad = 'L0ck-ECP v1 slot';
final _aead = Chacha20.poly1305Aead();
final _rng = Random.secure();

/// Argon2id cost. [KdfParams.production] follows RFC 9106's second recommended option.
class KdfParams {
  const KdfParams({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  const KdfParams.production()
      : memoryKiB = 64 * 1024,
        iterations = 3,
        parallelism = 1;

  final int memoryKiB;
  final int iterations;
  final int parallelism;
}

/// Hardware binding: on Android an HMAC under a non-exportable Keystore key, so the PIN
/// cannot be brute-forced off the device. Must return 32 bytes.
typedef KeyStrengthener = Future<List<int>> Function(List<int> key);

/// Runs the Argon2id step. Apps pass one that uses an isolate (`Isolate.run`) so the UI
/// does not freeze for the seconds the production cost takes on a phone.
typedef PinStretcher = Future<Uint8List> Function(String pin, Uint8List salt, KdfParams kdf);

/// The Argon2id step on its own: a top-level function, so it can be sent to an isolate.
Future<Uint8List> argon2idStretch(String pin, Uint8List salt, KdfParams kdf) async {
  final argon = Argon2id(
    parallelism: kdf.parallelism,
    memory: kdf.memoryKiB,
    iterations: kdf.iterations,
    hashLength: 32,
  );
  final k = await argon.deriveKey(secretKey: SecretKey(utf8.encode(pin)), nonce: salt);
  return Uint8List.fromList(await k.extractBytes());
}

enum Profile {
  real(0),
  decoy(1);

  const Profile(this.code);
  final int code;
}

class SlotFile {
  SlotFile({required this.kdf, required this.salt, required List<Uint8List> slots})
      : slots = List.unmodifiable(slots) {
    if (salt.length != saltLength) throw ArgumentError('salt must be $saltLength bytes');
    if (slots.length != 2 || slots.any((s) => s.length != KeySlots.slotLength)) {
      throw ArgumentError('need exactly two ${KeySlots.slotLength}-byte slots');
    }
  }

  static const formatVersion = 1;
  static const saltLength = 16;

  final KdfParams kdf;
  final Uint8List salt;
  final List<Uint8List> slots;

  Uint8List encode() {
    final w = ByteWriter()
      ..u8(formatVersion)
      ..u32(kdf.memoryKiB)
      ..u8(kdf.iterations)
      ..u8(kdf.parallelism)
      ..bytes(salt);
    slots.forEach(w.bytes);
    return w.toBytes();
  }

  static SlotFile decode(List<int> data) {
    final r = ByteReader(data);
    if (r.u8() != formatVersion) throw const FormatException('unknown slot file version');
    final kdf = KdfParams(memoryKiB: r.u32(), iterations: r.u8(), parallelism: r.u8());
    final salt = r.take(saltLength);
    final slots = [r.take(KeySlots.slotLength), r.take(KeySlots.slotLength)];
    if (r.remaining != 0) throw const FormatException('trailing bytes in slot file');
    return SlotFile(kdf: kdf, salt: salt, slots: slots);
  }

  SlotFile _withSlot(int index, Uint8List slot) {
    final s = [...slots];
    s[index] = slot;
    return SlotFile(kdf: kdf, salt: salt, slots: s);
  }
}

class CreatedSlots {
  CreatedSlots(this.file, this.realMasterKey, this.decoyMasterKey);

  final SlotFile file;
  final Uint8List realMasterKey;
  final Uint8List? decoyMasterKey;
}

class UnlockResult {
  UnlockResult(this.profile, this.masterKey, this.slotIndex);

  final Profile profile;
  final Uint8List masterKey;
  final int slotIndex;
}

abstract final class KeySlots {
  static const masterKeyLength = 32;
  static const slotLength = 12 + 1 + masterKeyLength + 16; // nonce · profile · MK · tag

  static Future<CreatedSlots> create({
    required String pin,
    String? duressPin,
    KdfParams kdf = const KdfParams.production(),
    KeyStrengthener? strengthen,
    PinStretcher stretch = argon2idStretch,
  }) async {
    if (pin.isEmpty) throw ArgumentError('PIN must not be empty');
    if (duressPin != null && (duressPin.isEmpty || duressPin == pin)) {
      throw ArgumentError('duress code must be non-empty and differ from the PIN');
    }
    final salt = randomBytes(SlotFile.saltLength);
    final real = randomBytes(masterKeyLength);
    final realSlot =
        await _wrap(await _kek(pin, salt, kdf, strengthen, stretch), Profile.real, real);

    Uint8List? decoy;
    final Uint8List otherSlot;
    if (duressPin != null) {
      decoy = randomBytes(masterKeyLength);
      otherSlot = await _wrap(
          await _kek(duressPin, salt, kdf, strengthen, stretch), Profile.decoy, decoy);
    } else {
      otherSlot = randomBytes(slotLength); // indistinguishable from a real slot
    }
    final slots = _rng.nextBool() ? [realSlot, otherSlot] : [otherSlot, realSlot];
    return CreatedSlots(SlotFile(kdf: kdf, salt: salt, slots: slots), real, decoy);
  }

  /// One Argon2id run per attempt, tried against both slots. Null for a wrong code.
  static Future<UnlockResult?> unlock(
    SlotFile file,
    String pin, {
    KeyStrengthener? strengthen,
    PinStretcher stretch = argon2idStretch,
  }) async {
    final kek = await _kek(pin, file.salt, file.kdf, strengthen, stretch);
    for (var i = 0; i < file.slots.length; i++) {
      final opened = await _unwrap(kek, file.slots[i]);
      if (opened != null) return UnlockResult(opened.$1, opened.$2, i);
    }
    return null;
  }

  /// New code for the open slot [index]: the same master key, wrapped under [newPin].
  /// Refused when [newPin] would also open the other slot (one code, two profiles).
  static Future<SlotFile> changeCode(
    SlotFile file, {
    required int index,
    required Profile profile,
    required Uint8List masterKey,
    required String newPin,
    KeyStrengthener? strengthen,
    PinStretcher stretch = argon2idStretch,
  }) async {
    if (newPin.isEmpty) throw ArgumentError('PIN must not be empty');
    final kek = await _kek(newPin, file.salt, file.kdf, strengthen, stretch);
    if (await _unwrap(kek, file.slots[index == 0 ? 1 : 0]) != null) {
      throw ArgumentError('the new code equals the other code');
    }
    return file._withSlot(index, await _wrap(kek, profile, masterKey));
  }

  /// Replaces the other slot (not [keepIndex]): a fresh decoy under [duressPin], or noise
  /// when null (no duress code). Whatever the other slot held is gone. Returns the new file
  /// and the new decoy's master key.
  static Future<(SlotFile, Uint8List?)> replaceOther(
    SlotFile file, {
    required int keepIndex,
    String? duressPin,
    KeyStrengthener? strengthen,
    PinStretcher stretch = argon2idStretch,
  }) async {
    final other = keepIndex == 0 ? 1 : 0;
    if (duressPin == null) return (destroySlot(file, other), null);
    if (duressPin.isEmpty) throw ArgumentError('duress code must not be empty');
    final kek = await _kek(duressPin, file.salt, file.kdf, strengthen, stretch);
    if (await _unwrap(kek, file.slots[keepIndex]) != null) {
      throw ArgumentError('the duress code equals the PIN');
    }
    final decoy = randomBytes(masterKeyLength);
    return (file._withSlot(other, await _wrap(kek, Profile.decoy, decoy)), decoy);
  }

  /// Crypto-shred one slot: its master key, and every database keyed from it, becomes
  /// unrecoverable even though the encrypted data stays on flash.
  static SlotFile destroySlot(SlotFile file, int index) =>
      file._withSlot(index, randomBytes(slotLength));

  /// Duress path: keep the decoy that was just opened, destroy the other slot.
  static SlotFile destroyAllBut(SlotFile file, int keepIndex) =>
      destroySlot(file, keepIndex == 0 ? 1 : 0);

  static SlotFile destroyAll(SlotFile file) => destroySlot(destroySlot(file, 0), 1);

  static Future<Uint8List> _kek(
    String pin,
    Uint8List salt,
    KdfParams kdf,
    KeyStrengthener? strengthen,
    PinStretcher stretch,
  ) async {
    final stretched = await stretch(pin, salt, kdf);
    if (stretched.length != 32) throw StateError('stretcher must return 32 bytes');
    if (strengthen == null) return stretched;
    final hw = await strengthen(stretched);
    if (hw.length != 32) throw StateError('key strengthener must return 32 bytes');
    return Uint8List.fromList(hw);
  }

  static Future<Uint8List> _wrap(Uint8List kek, Profile profile, Uint8List mk) async {
    final nonce = randomBytes(12);
    final box = await _aead.encrypt(
      [profile.code, ...mk],
      secretKey: SecretKey(kek),
      nonce: nonce,
      aad: utf8.encode(_slotAad),
    );
    return (BytesBuilder(copy: false)
          ..add(nonce)
          ..add(box.cipherText)
          ..add(box.mac.bytes))
        .toBytes();
  }

  static Future<(Profile, Uint8List)?> _unwrap(Uint8List kek, Uint8List slot) async {
    try {
      final clear = await _aead.decrypt(
        SecretBox(
          Uint8List.sublistView(slot, 12, slot.length - 16),
          nonce: Uint8List.sublistView(slot, 0, 12),
          mac: Mac(Uint8List.sublistView(slot, slot.length - 16)),
        ),
        secretKey: SecretKey(kek),
        aad: utf8.encode(_slotAad),
      );
      final profile = Profile.values.firstWhere((p) => p.code == clear[0]);
      return (profile, Uint8List.fromList(clear.sublist(1)));
    } on SecretBoxAuthenticationError {
      return null;
    }
  }
}

/// Wrong-PIN handling (§6): free tries, then doubling delays, then wipe.
class AttemptPolicy {
  const AttemptPolicy({
    this.freeAttempts = 3,
    this.maxAttempts = 10,
    this.baseDelay = const Duration(seconds: 30),
    this.maxDelay = const Duration(hours: 1),
  });

  final int freeAttempts;

  /// 0 disables the wipe.
  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;

  Duration delayAfter(int failures) {
    if (failures < freeAttempts) return Duration.zero;
    final step = failures - freeAttempts;
    if (step >= 20) return maxDelay;
    final d = baseDelay * (1 << step);
    return d > maxDelay ? maxDelay : d;
  }

  bool shouldWipe(int failures) => maxAttempts > 0 && failures >= maxAttempts;
}
