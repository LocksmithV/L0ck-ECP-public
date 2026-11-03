import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ecp_core/ecp_core.dart';

import '../data/database.dart';
import '../l10n/lang.dart';

/// An unlocked profile. Real and decoy sessions look identical to the UI on purpose:
/// nothing on screen may reveal that a duress code was used.
class Session {
  Session(this.masterKey, this.db, this.identity, this.nickname,
      {this.profileId = '',
      this.brambleProfile = '',
      this.bramblePassword = '',
      this.slotIndex = 0,
      this.profile = Profile.real});

  final Uint8List masterKey;
  final EcpDatabase db;
  final EcpIdentity identity;

  /// Changeable in settings (SecurityService.rename).
  String nickname;

  /// Which key slot opened this session, and the profile byte inside it — needed to re-wrap
  /// the slot under a new PIN. Never shown: the UI must look the same in both profiles.
  final int slotIndex;
  final Profile profile;

  /// Name of the profile's database file; tells two sessions of one profile apart.
  final String profileId;

  /// The profile's Bramble directory name and account password, both derived from the
  /// master key, so nothing on disk links them to the profile (docs/ARCHITECTURE_V2.md §6).
  final String brambleProfile;
  final String bramblePassword;

  Future<void> close() async {
    await db.close();
    masterKey.fillRange(0, masterKey.length, 0);
  }
}

sealed class UnlockOutcome {
  const UnlockOutcome();
}

class Unlocked extends UnlockOutcome {
  const Unlocked(this.session);
  final Session session;
}

class WrongCode extends UnlockOutcome {
  const WrongCode(this.failures, this.retryAfter);
  final int failures;
  final Duration retryAfter;
}

class MustWait extends UnlockOutcome {
  const MustWait(this.remaining);
  final Duration remaining;
}

/// The code opens the profile that is already running in the background (§7: the app keeps
/// receiving while locked), so only the screen unlocks.
class StillUnlocked extends UnlockOutcome {
  const StillUnlocked();
}

/// Too many wrong codes: everything was destroyed (docs/ARCHITECTURE_V2.md §6).
class Wiped extends UnlockOutcome {
  const Wiped();
}

/// Owns the key-slot file, the wrong-attempt counter and the per-profile databases.
class SecurityService {
  SecurityService(
    this.dir, {
    required this.strengthen,
    required this.deleteHardwareKey,
    this.kdf = const KdfParams.production(),
    this.policy = const AttemptPolicy(),
    this.runInIsolate = true,
    this.stretcher,
    this.onProfilesDestroyed,
    this.onProfileDestroyed,
  });

  final Directory dir;
  final KeyStrengthener strengthen;
  final Future<void> Function() deleteHardwareKey;
  final KdfParams kdf;
  final AttemptPolicy policy;
  final bool runInIsolate;

  /// Native Argon2id when available (see NativeArgon2); otherwise the pure-Dart one.
  final PinStretcher? stretcher;

  /// Called after duress or a wipe destroyed profiles, with the Bramble profile that
  /// survives (null: none), so data outside this directory goes too.
  final Future<void> Function(String? keepBrambleProfile)? onProfilesDestroyed;

  /// Called after [destroyProfile] destroyed one profile, with its Bramble profile: only
  /// that one's data outside this directory goes (the other slot's is unknown here).
  final Future<void> Function(String brambleProfile)? onProfileDestroyed;

  static const minPinLength = 6;
  static const maxPinLength = 12;

  File get _slotsFile => File('${dir.path}/slots.bin');
  File get _attemptsFile => File('${dir.path}/attempts');

  Future<bool> isSetUp() => _slotsFile.exists();

  /// PIN rules: 6–12 digits (6 is the floor: an attacker holding the device can still drive
  /// the Keystore, so only Argon2 cost × PIN space limits online guessing).
  static String? validatePin(String pin) {
    final l = Lang.tr;
    if (pin.isEmpty) return l.pinRuleEnter(minPinLength, maxPinLength);
    if (!RegExp(r'^\d+$').hasMatch(pin)) return l.pinRuleDigits;
    if (pin.length < minPinLength) return l.pinRuleMin(minPinLength);
    if (pin.length > maxPinLength) return l.pinRuleMax(maxPinLength);
    return null;
  }

  Future<void> setup({
    required String pin,
    String? duressPin,
    required String nickname,
  }) async {
    final err = validatePin(pin) ?? (duressPin == null ? null : validatePin(duressPin));
    if (err != null) throw ArgumentError(err);
    final created = await KeySlots.create(
      pin: pin,
      duressPin: duressPin,
      kdf: kdf,
      strengthen: strengthen,
      stretch: _stretch,
    );
    await _writeAtomic(_slotsFile, created.file.encode());
    await _writeAttempts(0, null);
    // Both profiles get a real identity and database, so the decoy looks lived-in-ready
    await (await _openProfile(created.realMasterKey, nickname)).close();
    final decoy = created.decoyMasterKey;
    if (decoy != null) await (await _openProfile(decoy, nickname)).close();
  }

  /// [runningProfile] is the [Session.profileId] still open in the background, if any.
  Future<UnlockOutcome> unlock(String pin, {String? runningProfile}) async {
    final (failures, lockedUntil) = await _readAttempts();
    final now = DateTime.now();
    if (lockedUntil != null && now.isBefore(lockedUntil)) {
      return MustWait(lockedUntil.difference(now));
    }
    final file = SlotFile.decode(await _slotsFile.readAsBytes());
    final result =
        await KeySlots.unlock(file, pin, strengthen: strengthen, stretch: _stretch);

    if (result == null) {
      final f = failures + 1;
      if (policy.shouldWipe(f)) {
        await wipeAll();
        return const Wiped();
      }
      final wait = policy.delayAfter(f);
      await _writeAttempts(f, wait == Duration.zero ? null : now.add(wait));
      return WrongCode(f, wait);
    }

    await _writeAttempts(0, null);
    final dbName = await _dbFileName(result.masterKey);
    if (result.profile == Profile.decoy) {
      // Duress: the real master key is gone the moment the decoy opens, then its
      // (now undecryptable) database files go too
      await _writeAtomic(
          _slotsFile, KeySlots.destroyAllBut(file, result.slotIndex).encode());
      await _deleteDatabasesExcept(dbName);
      await _profilesDestroyed(await _brambleProfile(result.masterKey));
    }
    if (dbName == runningProfile) return const StillUnlocked();
    return Unlocked(await _openProfile(result.masterKey, null,
        slotIndex: result.slotIndex, profile: result.profile));
  }

  /// Destroys both slots, the hardware key and every database. Back to first start.
  Future<void> wipeAll() async {
    if (await _slotsFile.exists()) {
      final file = SlotFile.decode(await _slotsFile.readAsBytes());
      await _writeAtomic(_slotsFile, KeySlots.destroyAll(file).encode());
      await _slotsFile.delete();
    }
    try {
      await deleteHardwareKey();
    } catch (_) {
      // Keystore errors must not stop the wipe
    }
    await _deleteDatabasesExcept(null);
    await _profilesDestroyed(null);
    if (await _attemptsFile.exists()) await _attemptsFile.delete();
  }

  /// The PIN screen's KOMPROMITOVÁN: the open profile is destroyed as the duress code would
  /// destroy it, without any code — it is open already. Its slot goes first (from then on
  /// its data cannot be decrypted), then [close] stops what still uses it, then its files.
  /// The other slot stays as it was, a decoy or noise: the PIN screen looks unchanged and a
  /// duress code still opens the decoy.
  Future<void> destroyProfile(Session s, {required Future<void> Function() close}) async {
    await _writeAtomic(_slotsFile, KeySlots.destroySlot(await _slots(), s.slotIndex).encode());
    try {
      await close();
    } catch (_) {
      // The slot is gone already; a failing close must not keep the files
    }
    if (await dir.exists()) {
      await for (final e in dir.list()) {
        final name = e.uri.pathSegments.last;
        if (!name.startsWith(s.profileId)) continue; // the database and its -wal / -shm
        try {
          await e.delete();
        } catch (_) {}
      }
    }
    try {
      await onProfileDestroyed?.call(s.brambleProfile);
    } catch (_) {}
  }

  Future<void> _profilesDestroyed(String? keep) async {
    try {
      await onProfilesDestroyed?.call(keep);
    } catch (_) {
      // Like the Keystore: a failing cleanup must not stop the wipe or the decoy opening
    }
  }

  Future<(int, DateTime?)> attemptState() => _readAttempts();

  // --- profiles ---

  // --- settings ---

  /// The code that opened [s] must be given again; a wrong one changes nothing (and is not
  /// counted: the session is already open, so there is nothing to guess).
  Future<bool> _confirms(Session s, String code) async {
    final r = await KeySlots.unlock(await _slots(), code, strengthen: strengthen, stretch: _stretch);
    return r != null && r.slotIndex == s.slotIndex;
  }

  Future<SlotFile> _slots() async => SlotFile.decode(await _slotsFile.readAsBytes());

  /// New PIN for the open profile. Returns an error text, or null when done.
  Future<String?> changePin(Session s, {required String current, required String newPin}) async {
    final err = validatePin(newPin);
    if (err != null) return err;
    if (!await _confirms(s, current)) return Lang.tr.currentCodeWrong;
    try {
      final f = await KeySlots.changeCode(await _slots(),
          index: s.slotIndex,
          profile: s.profile,
          masterKey: s.masterKey,
          newPin: newPin,
          strengthen: strengthen,
          stretch: _stretch);
      await _writeAtomic(_slotsFile, f.encode());
      return null;
    } on ArgumentError {
      return Lang.tr.codeInUse;
    }
  }

  /// New duress code (a fresh, empty decoy with the same nickname), or none ([duress] null).
  /// Whatever the old other profile held is destroyed. Returns an error text, or null.
  Future<String?> setDuress(Session s, {required String current, String? duress}) async {
    if (duress != null) {
      final err = validatePin(duress);
      if (err != null) return err;
    }
    if (!await _confirms(s, current)) return Lang.tr.currentCodeWrong;
    final SlotFile f;
    final Uint8List? decoy;
    try {
      (f, decoy) = await KeySlots.replaceOther(await _slots(),
          keepIndex: s.slotIndex, duressPin: duress, strengthen: strengthen, stretch: _stretch);
    } on ArgumentError {
      return Lang.tr.duressMustDiffer;
    }
    await _writeAtomic(_slotsFile, f.encode());
    final keep = {s.profileId};
    if (decoy != null) {
      final d = await _openProfile(decoy, s.nickname);
      keep.add(d.profileId);
      await d.close();
    }
    await _deleteDatabasesExcept(null, keepAll: keep);
    await _profilesDestroyed(s.brambleProfile);
    return null;
  }

  /// New nickname. With the duress code the decoy is renamed too — otherwise it would show
  /// the old name under duress and give itself away. The decoy slot is only opened here,
  /// nothing is destroyed. Returns an error text, or null.
  Future<String?> rename(Session s, String nickname, {String? duress}) async {
    final n = nickname.trim();
    if (n.isEmpty) return Lang.tr.enterNickname;
    if (duress != null && duress.isNotEmpty) {
      final r = await KeySlots.unlock(await _slots(), duress, strengthen: strengthen, stretch: _stretch);
      if (r == null || r.slotIndex == s.slotIndex) return Lang.tr.duressWrong;
      final d = await _openProfile(r.masterKey, null);
      await d.db.saveIdentity(await d.identity.privateKeyBytes(), n);
      await d.close();
    }
    await s.db.saveIdentity(await s.identity.privateKeyBytes(), n);
    s.nickname = n;
    return null;
  }

  Future<Session> _openProfile(Uint8List mk, String? nicknameIfNew,
      {int slotIndex = 0, Profile profile = Profile.real}) async {
    final file = File('${dir.path}/${await _dbFileName(mk)}');
    final db = EcpDatabase.openEncrypted(file, await deriveSubkey(mk, 'db'));
    var row = await db.identity();
    if (row == null) {
      final id = await EcpIdentity.generate();
      await db.saveIdentity(await id.privateKeyBytes(), nicknameIfNew ?? 'L0ck');
      row = await db.identity();
    }
    final identity = await EcpIdentity.fromPrivateKey(row!.privateKey);
    return Session(Uint8List.fromList(mk), db, identity, row.nickname,
        profileId: file.uri.pathSegments.last,
        brambleProfile: await _brambleProfile(mk),
        bramblePassword: toHex(await deriveSubkey(mk, 'bramble-password')),
        slotIndex: slotIndex,
        profile: profile);
  }

  Future<String> _brambleProfile(List<int> mk) async =>
      toHex(await deriveSubkey(mk, 'bramble-dir')).substring(0, 32);

  /// Database file names come from the master key, so nothing on disk labels a profile.
  Future<String> _dbFileName(List<int> mk) async =>
      'ecp_${toHex(await deriveSubkey(mk, 'db-name')).substring(0, 16)}.db';

  Future<void> _deleteDatabasesExcept(String? keep, {Set<String> keepAll = const {}}) async {
    if (!await dir.exists()) return;
    await for (final e in dir.list()) {
      final name = e.uri.pathSegments.last;
      if (!name.startsWith('ecp_')) continue;
      if (keep != null && name.startsWith(keep)) continue; // also keeps -wal / -shm
      if (keepAll.any(name.startsWith)) continue;
      try {
        await e.delete();
      } catch (_) {}
    }
  }

  // --- helpers ---

  Future<Uint8List> _stretch(String pin, Uint8List salt, KdfParams k) {
    final native = stretcher;
    if (native != null) return native(pin, salt, k);
    return runInIsolate
        ? Isolate.run(() => argon2idStretch(pin, salt, k))
        : argon2idStretch(pin, salt, k);
  }

  Future<(int, DateTime?)> _readAttempts() async {
    if (!await _attemptsFile.exists()) return (0, null);
    final parts = (await _attemptsFile.readAsString()).split(',');
    final failures = int.tryParse(parts.first) ?? 0;
    final until = parts.length > 1 ? int.tryParse(parts[1]) : null;
    return (
      failures,
      until == null || until == 0 ? null : DateTime.fromMillisecondsSinceEpoch(until),
    );
  }

  Future<void> _writeAttempts(int failures, DateTime? lockedUntil) => _writeAtomic(
      _attemptsFile, '$failures,${lockedUntil?.millisecondsSinceEpoch ?? 0}'.codeUnits);

  static Future<void> _writeAtomic(File f, List<int> bytes) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
  }
}
