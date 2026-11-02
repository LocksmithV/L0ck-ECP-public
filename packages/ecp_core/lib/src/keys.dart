import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'bytes.dart';

/// Domain-separation labels. Changing any of them breaks compatibility with v1.
const _pairSalt = 'L0ck-ECP v1 pair';
const _verifyLabel = 'L0ck-ECP v1 verify';
const _subkeySalt = 'L0ck-ECP v1 subkey';
const _tagLabel = 'tag';

final _x25519 = X25519();
final _hmac = Hmac.sha256();
final _sha256 = Sha256();

/// The device's long-term X25519 identity (docs/ARCHITECTURE_V2.md §2).
class EcpIdentity {
  EcpIdentity._(this._keyPair, this.publicKey);

  final SimpleKeyPair _keyPair;
  final Uint8List publicKey;

  static Future<EcpIdentity> generate() async {
    final kp = await _x25519.newKeyPair();
    return _wrap(kp);
  }

  /// Restores an identity from its 32-byte private key (as stored in the encrypted DB).
  static Future<EcpIdentity> fromPrivateKey(List<int> privateKey) async {
    if (privateKey.length != 32) {
      throw ArgumentError('X25519 private key must be 32 bytes');
    }
    final kp = await _x25519.newKeyPairFromSeed(privateKey);
    return _wrap(kp);
  }

  static Future<EcpIdentity> _wrap(SimpleKeyPair kp) async {
    final pub = await kp.extractPublicKey();
    return EcpIdentity._(kp, Uint8List.fromList(pub.bytes));
  }

  Future<Uint8List> privateKeyBytes() async =>
      Uint8List.fromList(await _keyPair.extractPrivateKeyBytes());

  Future<Uint8List> _sharedSecret(List<int> peerPublic) async {
    final k = await _x25519.sharedSecretKey(
      keyPair: _keyPair,
      remotePublicKey: SimplePublicKey(peerPublic, type: KeyPairType.x25519),
    );
    return Uint8List.fromList(await k.extractBytes());
  }
}

/// Directional keys shared with one contact: [send] for A→B, [recv] for B→A.
class PairKeys {
  PairKeys(this.send, this.recv, this.peerPublic);

  final Uint8List send;
  final Uint8List recv;
  final Uint8List peerPublic;
}

/// X25519 + HKDF-SHA256 → one key per direction, so a message reflected back to its sender
/// cannot be opened (§2).
Future<PairKeys> derivePairKeys(EcpIdentity me, List<int> peerPublic) async {
  if (peerPublic.length != 32) {
    throw ArgumentError('peer public key must be 32 bytes');
  }
  if (constantTimeEquals(peerPublic, me.publicKey)) {
    throw ArgumentError('peer key equals own key');
  }
  final shared = await me._sharedSecret(peerPublic);
  // A low-order peer point yields an all-zero secret; refuse it (RFC 7748 §6.1)
  if (shared.every((b) => b == 0)) {
    throw ArgumentError('invalid peer public key (low-order point)');
  }
  final (lo, hi) = _ordered(me.publicKey, peerPublic);
  final okm = await Hkdf(hmac: _hmac, outputLength: 64).deriveKey(
    secretKey: SecretKey(shared),
    nonce: utf8.encode(_pairSalt),
    info: [...lo, ...hi],
  );
  final bytes = Uint8List.fromList(await okm.extractBytes());
  final loToHi = Uint8List.sublistView(bytes, 0, 32);
  final hiToLo = Uint8List.sublistView(bytes, 32, 64);
  final iAmLo = identical(lo, me.publicKey) || constantTimeEquals(lo, me.publicKey);
  return iAmLo
      ? PairKeys(Uint8List.fromList(loToHi), Uint8List.fromList(hiToLo),
          Uint8List.fromList(peerPublic))
      : PairKeys(Uint8List.fromList(hiToLo), Uint8List.fromList(loToHi),
          Uint8List.fromList(peerPublic));
}

/// 12-digit verification number, identical on both phones (§5).
Future<String> verificationNumber(List<int> a, List<int> b) async {
  final (lo, hi) = _ordered(a, b);
  final h = await _sha256.hash([...utf8.encode(_verifyLabel), ...lo, ...hi]);
  var n = BigInt.zero;
  for (final byte in h.bytes.take(8)) {
    n = (n << 8) | BigInt.from(byte);
  }
  final digits = (n % BigInt.from(1000000000000)).toString().padLeft(12, '0');
  return '${digits.substring(0, 4)} ${digits.substring(4, 8)} ${digits.substring(8)}';
}

/// 2-byte sender fingerprint used inside team envelopes (§3). Not authenticating.
Future<Uint8List> senderFingerprint(List<int> publicKey) async {
  final h = await _sha256.hash(publicKey);
  return Uint8List.fromList(h.bytes.sublist(0, 2));
}

/// Daily-rotating 2-byte tag: lets the recipient find the right key without revealing
/// to outsiders who the message is for (§3).
Future<Uint8List> envelopeTag(List<int> key, int utcDay) async {
  final w = ByteWriter()
    ..bytes(utf8.encode(_tagLabel))
    ..u32(utcDay);
  final mac = await _hmac.calculateMac(w.toBytes(), secretKey: SecretKey(key));
  return Uint8List.fromList(mac.bytes.sublist(0, 2));
}

int utcDay(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

/// Purpose-bound 32-byte key derived from the master key (§6), e.g. "db", "bramble".
Future<Uint8List> deriveSubkey(List<int> masterKey, String label) async {
  final k = await Hkdf(hmac: _hmac, outputLength: 32).deriveKey(
    secretKey: SecretKey(masterKey),
    nonce: utf8.encode(_subkeySalt),
    info: utf8.encode(label),
  );
  return Uint8List.fromList(await k.extractBytes());
}

(List<int>, List<int>) _ordered(List<int> a, List<int> b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return a[i] < b[i] ? (a, b) : (b, a);
  }
  return a.length <= b.length ? (a, b) : (b, a);
}
