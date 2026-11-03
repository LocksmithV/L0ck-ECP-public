import 'dart:convert';

/// When the unlocked app covers itself with the PIN screen, and what else opens it. Kept in
/// the profile's encrypted database like [PanicConfig]; after a restart the PIN is always
/// needed, since the profile key is derived from it.
class LockConfig {
  const LockConfig({this.after = Duration.zero, this.quickLock = true, this.biometric = false})
      : assert(after != null || quickLock, 'locking only by hand needs the four taps');

  /// Choices in the settings; null: only by hand.
  static const choices = <Duration?>[
    Duration.zero,
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    null,
  ];

  /// A fingerprint opens the running profile for this long after the last PIN.
  static const biometricFor = Duration(hours: 8);

  /// How long after leaving the app it locks; zero: at once, null: only by hand (the four
  /// taps, which then cannot be switched off).
  final Duration? after;

  /// Emergency lock: four quick taps anywhere lock and hide the app.
  final bool quickLock;

  /// A fingerprint may stand in for the PIN on the PIN screen (see [biometricFor]). Only
  /// with PANIC and KOMPROMITOVÁN on that screen: a fingerprint has no duress code.
  final bool biometric;

  /// Another delay; only by hand turns the four taps back on.
  LockConfig withAfter(Duration? after) =>
      LockConfig(after: after, quickLock: after == null || quickLock, biometric: biometric);

  LockConfig copyWith({bool? quickLock, bool? biometric}) => LockConfig(
    after: after,
    quickLock: quickLock ?? this.quickLock,
    biometric: biometric ?? this.biometric,
  );

  String encode() => jsonEncode({'after': after?.inSeconds ?? -1, 'quick': quickLock, 'bio': biometric});

  /// Unknown or damaged settings fall back to the defaults, field by field.
  static LockConfig decode(String? s) {
    const d = LockConfig();
    if (s == null) return d;
    try {
      final m = jsonDecode(s) as Map<String, Object?>;
      final secs = m['after'] is int ? m['after'] as int : 0;
      final after = secs < 0 ? null : Duration(seconds: secs);
      return LockConfig(
        after: after,
        quickLock: after == null || (m['quick'] is bool ? m['quick'] as bool : d.quickLock),
        biometric: m['bio'] is bool ? m['bio'] as bool : d.biometric,
      );
    } on Object {
      return d;
    }
  }
}
