import 'dart:isolate';
import 'dart:typed_data';

import 'package:ecp_core/ecp_core.dart';
import 'package:test/test.dart';

void main() {
  // Tiny Argon2 cost so the suite runs fast; production uses KdfParams.production()
  const fast = KdfParams(memoryKiB: 64, iterations: 1, parallelism: 1);

  test('PIN opens the real profile, duress code the decoy, wrong code nothing', () async {
    final c = await KeySlots.create(pin: '482913', duressPin: '115577', kdf: fast);
    final real = await KeySlots.unlock(c.file, '482913');
    expect(real!.profile, Profile.real);
    expect(real.masterKey, c.realMasterKey);
    final decoy = await KeySlots.unlock(c.file, '115577');
    expect(decoy!.profile, Profile.decoy);
    expect(decoy.masterKey, c.decoyMasterKey);
    expect(decoy.slotIndex, isNot(real.slotIndex));
    expect(await KeySlots.unlock(c.file, '000000'), isNull);
  });

  test('duress destroys the real slot for good', () async {
    final c = await KeySlots.create(pin: '482913', duressPin: '115577', kdf: fast);
    final decoy = (await KeySlots.unlock(c.file, '115577'))!;
    final after = KeySlots.destroyAllBut(c.file, decoy.slotIndex);
    expect(await KeySlots.unlock(after, '482913'), isNull);
    expect((await KeySlots.unlock(after, '115577'))!.profile, Profile.decoy);
  });

  test('without a duress code the second slot is noise of the same size', () async {
    final c = await KeySlots.create(pin: '482913', kdf: fast);
    expect(c.decoyMasterKey, isNull);
    expect(c.file.slots.map((s) => s.length).toSet(), {KeySlots.slotLength});
    expect((await KeySlots.unlock(c.file, '482913'))!.profile, Profile.real);
  });

  test('slot file survives serialisation and keeps its KDF cost', () async {
    final c = await KeySlots.create(pin: '2468', duressPin: '1357', kdf: fast);
    final back = SlotFile.decode(c.file.encode());
    expect(back.kdf.memoryKiB, fast.memoryKiB);
    expect((await KeySlots.unlock(back, '2468'))!.masterKey, c.realMasterKey);
    expect(() => SlotFile.decode(c.file.encode().sublist(1)), throwsFormatException);
  });

  test('hardware strengthener is part of the key', () async {
    Future<List<int>> deviceA(List<int> k) async => [for (final b in k) b ^ 0x5a];
    Future<List<int>> deviceB(List<int> k) async => [for (final b in k) b ^ 0xa5];
    final c = await KeySlots.create(pin: '9999', kdf: fast, strengthen: deviceA);
    expect(await KeySlots.unlock(c.file, '9999', strengthen: deviceA), isNotNull);
    // Copied to another device (other Keystore key) or opened without it: useless
    expect(await KeySlots.unlock(c.file, '9999', strengthen: deviceB), isNull);
    expect(await KeySlots.unlock(c.file, '9999'), isNull);
  });

  test('Argon2id can run in an isolate (how the app keeps the UI responsive)', () async {
    Future<Uint8List> inIsolate(String pin, Uint8List salt, KdfParams kdf) =>
        Isolate.run(() => argon2idStretch(pin, salt, kdf));
    final c = await KeySlots.create(pin: '135790', kdf: fast, stretch: inIsolate);
    // Same result as in-process stretching: the slot file is portable between the two
    expect((await KeySlots.unlock(c.file, '135790'))!.masterKey, c.realMasterKey);
    expect((await KeySlots.unlock(c.file, '135790', stretch: inIsolate))!.profile,
        Profile.real);
  });

  test('destroyAll leaves nothing to unlock', () async {
    final c = await KeySlots.create(pin: '1111', duressPin: '2222', kdf: fast);
    final gone = KeySlots.destroyAll(c.file);
    expect(await KeySlots.unlock(gone, '1111'), isNull);
    expect(await KeySlots.unlock(gone, '2222'), isNull);
  });

  test('duress code must differ from the PIN', () {
    expect(() => KeySlots.create(pin: '1234', duressPin: '1234', kdf: fast),
        throwsArgumentError);
  });

  test('changing the PIN keeps the profile; the old PIN stops working', () async {
    final c = await KeySlots.create(pin: '111111', duressPin: '999999', kdf: fast);
    final r = (await KeySlots.unlock(c.file, '111111'))!;
    final f = await KeySlots.changeCode(c.file,
        index: r.slotIndex, profile: r.profile, masterKey: r.masterKey, newPin: '222222');
    expect(await KeySlots.unlock(f, '111111'), isNull);
    final again = (await KeySlots.unlock(f, '222222'))!;
    expect(again.masterKey, c.realMasterKey);
    expect(again.profile, Profile.real);
    expect((await KeySlots.unlock(f, '999999'))!.profile, Profile.decoy, reason: 'duress untouched');
    expect(
        () => KeySlots.changeCode(f,
            index: r.slotIndex, profile: r.profile, masterKey: r.masterKey, newPin: '999999'),
        throwsArgumentError,
        reason: 'one code must not open both profiles');
  });

  test('a new duress code means a new, empty decoy; none means noise', () async {
    final c = await KeySlots.create(pin: '111111', duressPin: '999999', kdf: fast);
    final r = (await KeySlots.unlock(c.file, '111111'))!;
    final (f, decoy) = await KeySlots.replaceOther(c.file, keepIndex: r.slotIndex, duressPin: '555555');
    expect(await KeySlots.unlock(f, '999999'), isNull);
    final d = (await KeySlots.unlock(f, '555555'))!;
    expect(d.profile, Profile.decoy);
    expect(d.masterKey, decoy);
    expect(d.masterKey, isNot(c.decoyMasterKey));
    expect((await KeySlots.unlock(f, '111111'))!.masterKey, c.realMasterKey);
    final (none, nk) = await KeySlots.replaceOther(f, keepIndex: r.slotIndex);
    expect(nk, isNull);
    expect(await KeySlots.unlock(none, '555555'), isNull);
    expect(none.slots[1 - r.slotIndex], hasLength(KeySlots.slotLength));
    expect(() => KeySlots.replaceOther(f, keepIndex: r.slotIndex, duressPin: '111111'),
        throwsArgumentError);
  });

  test('attempt policy: free tries, doubling delay, wipe', () {
    const p = AttemptPolicy();
    expect(p.delayAfter(2), Duration.zero);
    expect(p.delayAfter(3), const Duration(seconds: 30));
    expect(p.delayAfter(4), const Duration(minutes: 1));
    expect(p.delayAfter(30), const Duration(hours: 1));
    expect(p.shouldWipe(9), isFalse);
    expect(p.shouldWipe(10), isTrue);
    expect(const AttemptPolicy(maxAttempts: 0).shouldWipe(1000), isFalse);
  });
}
