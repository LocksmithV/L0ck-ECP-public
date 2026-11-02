import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'bytes.dart';
import 'keys.dart';

/// Seconds-since-2024-01-01 timestamps keep the inner header at 4 bytes until 2160.
const ecpEpochSeconds = 1704067200;

int ecpTime(DateTime t) =>
    t.toUtc().millisecondsSinceEpoch ~/ 1000 - ecpEpochSeconds;

DateTime fromEcpTime(int s) =>
    DateTime.fromMillisecondsSinceEpoch((s + ecpEpochSeconds) * 1000, isUtc: true);

enum EnvelopeKind {
  pair(0),
  team(1);

  const EnvelopeKind(this.code);
  final int code;
}

abstract final class MessageFlags {
  static const ackRequested = 0x01;
  static const priority = 0x02;
  static const signed = 0x04; // reserved for v2
}

final _aead = Chacha20.poly1305Aead();
final _rng = Random.secure();

Uint8List randomBytes(int n, [Random? rng]) {
  final r = rng ?? _rng;
  return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
}

/// The authenticated plaintext inside an envelope (§3, "Vnitřek").
class InnerMessage {
  InnerMessage({
    required this.type,
    this.flags = 0,
    required this.id,
    required this.sentAt,
    this.senderFingerprint,
    required this.payload,
  }) {
    if (id.length != 8) throw ArgumentError('message id must be 8 bytes');
  }

  /// A fresh message with a random id, stamped now.
  factory InnerMessage.create({
    required int type,
    required List<int> payload,
    int flags = 0,
    List<int>? senderFingerprint,
    DateTime? now,
  }) =>
      InnerMessage(
        type: type,
        flags: flags,
        id: randomBytes(8),
        sentAt: ecpTime(now ?? DateTime.now()),
        senderFingerprint:
            senderFingerprint == null ? null : Uint8List.fromList(senderFingerprint),
        payload: Uint8List.fromList(payload),
      );

  final int type;
  final int flags;
  final Uint8List id;
  final int sentAt;
  final Uint8List? senderFingerprint;
  final Uint8List payload;

  bool get wantsAck => flags & MessageFlags.ackRequested != 0;
}

/// A key the receiver is willing to try; [owner] lets the app map a hit back to a contact
/// or team.
class KeyCandidate {
  const KeyCandidate(this.kind, this.key, [this.owner]);

  final EnvelopeKind kind;
  final List<int> key;
  final Object? owner;
}

class OpenedEnvelope {
  OpenedEnvelope(this.via, this.message);

  final KeyCandidate via;
  final InnerMessage message;
}

/// ECP envelope v1 (docs/ARCHITECTURE_V2.md §3):
/// `ver|kind (1) · tag (2) · nonce (12) · ciphertext · Poly1305 tag (16)`.
abstract final class EcpEnvelope {
  static const version = 1;
  static const headerLength = 3;
  static const nonceLength = 12;
  static const macLength = 16;
  static const overhead = headerLength + nonceLength + macLength; // 31
  static const innerHeaderLength = 14;
  static const teamInnerHeaderLength = innerHeaderLength + 2;

  /// [nonce] is only for test vectors; production always uses a fresh random nonce.
  static Future<Uint8List> seal({
    required EnvelopeKind kind,
    required List<int> key,
    required InnerMessage message,
    DateTime? now,
    List<int>? nonce,
  }) async {
    if (key.length != 32) throw ArgumentError('key must be 32 bytes');
    final fp = message.senderFingerprint;
    if (kind == EnvelopeKind.team && (fp == null || fp.length != 2)) {
      throw ArgumentError('team envelope needs a 2-byte sender fingerprint');
    }
    final tag = await envelopeTag(key, utcDay(now ?? DateTime.now()));
    final header = Uint8List.fromList([(version << 4) | kind.code, tag[0], tag[1]]);
    final n = nonce == null ? randomBytes(nonceLength) : Uint8List.fromList(nonce);
    if (n.length != nonceLength) throw ArgumentError('nonce must be 12 bytes');

    final box = await _aead.encrypt(
      _encodeInner(kind, message),
      secretKey: SecretKey(key),
      nonce: n,
      aad: header,
    );
    return (BytesBuilder(copy: false)
          ..add(header)
          ..add(n)
          ..add(box.cipherText)
          ..add(box.mac.bytes))
        .toBytes();
  }

  /// Returns null for anything that is not a valid envelope for one of [candidates]:
  /// wrong version, unknown tag, failed authentication or a malformed inner message.
  static Future<OpenedEnvelope?> open(
    List<int> data,
    Iterable<KeyCandidate> candidates, {
    DateTime? now,
  }) async {
    if (data.length < overhead + innerHeaderLength) return null;
    final bytes = Uint8List.fromList(data);
    if (bytes[0] >> 4 != version) return null;
    final kindCode = bytes[0] & 0x0f;
    final header = Uint8List.sublistView(bytes, 0, headerLength);
    final tag = Uint8List.sublistView(bytes, 1, headerLength);
    final nonce = Uint8List.sublistView(bytes, headerLength, headerLength + nonceLength);
    final cipher =
        Uint8List.sublistView(bytes, headerLength + nonceLength, bytes.length - macLength);
    final mac = Uint8List.sublistView(bytes, bytes.length - macLength);
    final today = utcDay(now ?? DateTime.now());

    for (final c in candidates) {
      if (c.kind.code != kindCode || c.key.length != 32) continue;
      // Yesterday/tomorrow too: sender and receiver clocks and time zones drift
      var tagMatches = false;
      for (final day in [today, today - 1, today + 1]) {
        if (constantTimeEquals(await envelopeTag(c.key, day), tag)) {
          tagMatches = true;
          break;
        }
      }
      if (!tagMatches) continue;
      final List<int> clear;
      try {
        clear = await _aead.decrypt(
          SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
          secretKey: SecretKey(c.key),
          aad: header,
        );
      } on SecretBoxAuthenticationError {
        continue; // 2-byte tags collide now and then; the AEAD settles it
      }
      try {
        return OpenedEnvelope(c, _decodeInner(c.kind, clear));
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  static Uint8List _encodeInner(EnvelopeKind kind, InnerMessage m) {
    final w = ByteWriter()
      ..u8(m.type)
      ..u8(m.flags)
      ..bytes(m.id)
      ..u32(m.sentAt);
    if (kind == EnvelopeKind.team) w.bytes(m.senderFingerprint!);
    w.bytes(m.payload);
    return w.toBytes();
  }

  static InnerMessage _decodeInner(EnvelopeKind kind, List<int> clear) {
    final r = ByteReader(clear);
    final type = r.u8();
    final flags = r.u8();
    final id = r.take(8);
    final sentAt = r.u32();
    final fp = kind == EnvelopeKind.team ? r.take(2) : null;
    return InnerMessage(
      type: type,
      flags: flags,
      id: id,
      sentAt: sentAt,
      senderFingerprint: fp,
      payload: r.rest(),
    );
  }
}

/// Drops replays and stale messages (§3). Persist [export]/[ReplayGuard.restore] across
/// restarts so a captured SMS or LoRa packet cannot be replayed after a reboot.
class ReplayGuard {
  ReplayGuard({this.window = const Duration(days: 14)});

  ReplayGuard.restore(Map<String, int> seen, {this.window = const Duration(days: 14)}) {
    _seen.addAll(seen);
  }

  final Duration window;
  final Map<String, int> _seen = {};

  /// True exactly once per message id, and only within ±[window] of [now].
  bool accept(InnerMessage m, {DateTime? now}) {
    final t = ecpTime(now ?? DateTime.now());
    _seen.removeWhere((_, seenAt) => t - seenAt > window.inSeconds);
    if ((m.sentAt - t).abs() > window.inSeconds) return false;
    final key = toHex(m.id);
    if (_seen.containsKey(key)) return false;
    _seen[key] = t;
    return true;
  }

  Map<String, int> export() => Map.unmodifiable(_seen);
}
