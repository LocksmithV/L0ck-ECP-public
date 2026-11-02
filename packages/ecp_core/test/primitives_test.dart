// Known-answer tests from the RFCs: they check that the `cryptography` package we build on
// implements the standard primitives, not just that our code round-trips with itself.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:ecp_core/ecp_core.dart';
import 'package:test/test.dart';

void main() {
  test('X25519 — RFC 7748 §6.1', () async {
    final x = X25519();
    final alice = await x.newKeyPairFromSeed(
        fromHex('77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a'));
    final bob = await x.newKeyPairFromSeed(
        fromHex('5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb'));
    expect(toHex((await alice.extractPublicKey()).bytes),
        '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a');
    expect(toHex((await bob.extractPublicKey()).bytes),
        'de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f');
    final k = await x.sharedSecretKey(
        keyPair: alice, remotePublicKey: await bob.extractPublicKey());
    expect(toHex(await k.extractBytes()),
        '4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742');
  });

  test('ChaCha20-Poly1305 AEAD — RFC 8439 §2.8.2', () async {
    final plain = utf8.encode("Ladies and Gentlemen of the class of '99: If I could offer "
        'you only one tip for the future, sunscreen would be it.');
    final box = await Chacha20.poly1305Aead().encrypt(
      plain,
      secretKey: SecretKey(fromHex(
          '808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f')),
      nonce: fromHex('070000004041424344454647'),
      aad: fromHex('50515253c0c1c2c3c4c5c6c7'),
    );
    expect(
        toHex(box.cipherText),
        'd31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d6'
        '3dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b36'
        '92ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc'
        '3ff4def08e4b7a9de576d26586cec64b6116');
    expect(toHex(box.mac.bytes), '1ae10b594f09e26a7e902ecbd0600691');
  });

  test('HKDF-SHA256 — RFC 5869 A.1', () async {
    final okm = await Hkdf(hmac: Hmac.sha256(), outputLength: 42).deriveKey(
      secretKey: SecretKey(fromHex('0b' * 22)),
      nonce: fromHex('000102030405060708090a0b0c'),
      info: fromHex('f0f1f2f3f4f5f6f7f8f9'),
    );
    expect(
        toHex(await okm.extractBytes()),
        '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf'
        '34007208d5b887185865');
  });
}
