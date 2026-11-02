import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:l0ck_ecp/security/security_service.dart';
import 'package:l0ck_ecp/l10n/lang.dart';

/// Runs the real SecurityService against real SQLCipher on the host; only the Keystore is
/// replaced by an HMAC under a fixed key (deleting it makes every later call fail, like a
/// deleted Keystore entry).
void main() {
  Lang.current.value = const Locale('cs');
  late Directory dir;
  late bool hwKeyDeleted;

  Future<List<int>> fakeKeystore(List<int> k) async {
    if (hwKeyDeleted) throw StateError('keystore key deleted');
    final mac = await Hmac.sha256().calculateMac(k, secretKey: SecretKey(List.filled(32, 7)));
    return mac.bytes;
  }

  late List<String?> destroyed;

  SecurityService service({AttemptPolicy policy = const AttemptPolicy()}) => SecurityService(
    dir,
    strengthen: fakeKeystore,
    deleteHardwareKey: () async => hwKeyDeleted = true,
    kdf: const KdfParams(memoryKiB: 64, iterations: 1, parallelism: 1),
    policy: policy,
    runInIsolate: false,
    onProfilesDestroyed: (keep) async => destroyed.add(keep),
  );

  List<File> dbFiles() => dir
      .listSync()
      .whereType<File>()
      .where((f) => f.uri.pathSegments.last.startsWith('ecp_') && f.path.endsWith('.db'))
      .toList();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('l0ck_ecp_test');
    hwKeyDeleted = false;
    destroyed = [];
  });

  tearDown(() => dir.delete(recursive: true));

  test('PIN rules', () {
    expect(SecurityService.validatePin('12345'), isNotNull);
    expect(SecurityService.validatePin('12a456'), isNotNull);
    expect(SecurityService.validatePin('1234567890123'), isNotNull);
    expect(SecurityService.validatePin('123456'), isNull);
  });

  test('real PIN, then duress: decoy opens and the real profile is gone', () async {
    final s = service();
    await s.setup(pin: '482913', duressPin: '115577', nickname: 'Kos');
    expect(await s.isSetUp(), isTrue);
    expect(dbFiles(), hasLength(2), reason: 'real + decoy database');

    final real = (await s.unlock('482913')) as Unlocked;
    final realKey = real.session.identity.publicKey;
    expect(real.session.nickname, 'Kos');
    await real.session.close();

    final decoy = (await s.unlock('115577')) as Unlocked;
    expect(decoy.session.nickname, 'Kos', reason: 'decoy must look like the same person');
    expect(decoy.session.identity.publicKey, isNot(realKey));
    await decoy.session.close();

    expect(dbFiles(), hasLength(1), reason: 'real database deleted');
    expect(await s.unlock('482913'), isA<WrongCode>(), reason: 'real slot destroyed');
    // The decoy keeps working afterwards
    final again = (await s.unlock('115577')) as Unlocked;
    await again.session.close();
  });

  test('locked in the background: own code resumes, duress switches and drops Bramble', () async {
    final s = service();
    await s.setup(pin: '482913', duressPin: '115577', nickname: 'Kos');
    final real = (await s.unlock('482913')) as Unlocked;
    final running = real.session.profileId;
    expect(real.session.brambleProfile, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(real.session.bramblePassword, hasLength(64));

    expect(await s.unlock('482913', runningProfile: running), isA<StillUnlocked>());
    expect(destroyed, isEmpty);

    final decoy = (await s.unlock('115577', runningProfile: running)) as Unlocked;
    expect(decoy.session.profileId, isNot(running));
    expect(destroyed, [decoy.session.brambleProfile], reason: 'every Bramble profile but the decoy goes');
    expect(decoy.session.brambleProfile, isNot(real.session.brambleProfile));
    await real.session.close();
    await decoy.session.close();

    await s.wipeAll();
    expect(destroyed.last, isNull, reason: 'wipe removes all Bramble profiles');
  });

  test('settings: change PIN, new duress code, rename both profiles', () async {
    final s = service();
    await s.setup(pin: '482913', duressPin: '115577', nickname: 'Kos');
    final real = (await s.unlock('482913')) as Unlocked;
    final session = real.session;

    expect(await s.changePin(session, current: '000000', newPin: '246810'), 'Současný kód nesedí.');
    expect(await s.changePin(session, current: '482913', newPin: '115577'), 'Tento kód už se používá.');
    expect(await s.changePin(session, current: '482913', newPin: '246810'), isNull);
    expect(await s.unlock('482913', runningProfile: session.profileId), isA<WrongCode>());
    expect(await s.unlock('246810', runningProfile: session.profileId), isA<StillUnlocked>());

    expect(await s.rename(session, 'Sokol', duress: '115577'), isNull);
    expect(session.nickname, 'Sokol');
    expect(destroyed, isEmpty, reason: 'renaming opens the decoy, it does not trigger duress');

    expect(await s.setDuress(session, current: '246810', duress: '135790'), isNull);
    expect(dbFiles(), hasLength(2), reason: 'old decoy gone, new decoy created');
    final decoy = (await s.unlock('135790', runningProfile: session.profileId)) as Unlocked;
    expect(decoy.session.nickname, 'Sokol', reason: 'the new decoy carries the current name');
    await decoy.session.close();
    await session.close();
  });

  test('profile databases are encrypted on disk', () async {
    final s = service();
    await s.setup(pin: '482913', nickname: 'Kos');
    final u = (await s.unlock('482913')) as Unlocked;
    await u.session.close();
    for (final f in dbFiles()) {
      final head = f.readAsBytesSync().take(16).toList();
      expect(ascii.decode(head, allowInvalid: true), isNot(startsWith('SQLite format 3')));
    }
  });

  test('wrong codes: delay after the free tries', () async {
    final s = service(policy: const AttemptPolicy(freeAttempts: 1, baseDelay: Duration(minutes: 5)));
    await s.setup(pin: '482913', nickname: 'Kos');
    expect(await s.unlock('000000'), isA<WrongCode>());
    expect(await s.unlock('000000'), isA<MustWait>(), reason: 'second wrong try starts a 5-minute lockout');
    expect(await s.unlock('482913'), isA<MustWait>(), reason: 'even the right PIN waits out the lockout');
  });

  test('too many wrong codes wipe everything', () async {
    final s = service(policy: const AttemptPolicy(freeAttempts: 10, maxAttempts: 3));
    await s.setup(pin: '482913', duressPin: '115577', nickname: 'Kos');
    expect(await s.unlock('000000'), isA<WrongCode>());
    expect(await s.unlock('000001'), isA<WrongCode>());
    expect(await s.unlock('000002'), isA<Wiped>());
    expect(await s.isSetUp(), isFalse);
    expect(dbFiles(), isEmpty);
    expect(hwKeyDeleted, isTrue);
  });
}
