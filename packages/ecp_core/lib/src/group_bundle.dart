import 'dart:convert';
import 'dart:math' show min;
import 'dart:typed_data';

import 'bytes.dart';
import 'contact_card.dart';
import 'router.dart' show PaceLayer;

/// A team inside a [GroupBundle]: its name, key and which members (indexes into
/// [GroupBundle.members]) belong to it.
class GroupTeam {
  GroupTeam({required this.name, required this.key, required this.members}) {
    final n = utf8.encode(name).length;
    if (n == 0 || n > maxName) throw ArgumentError('team name must be 1..$maxName bytes');
    if (key.length != 32) throw ArgumentError('team key must be 32 bytes');
  }

  static const maxName = 40;

  final String name;
  final Uint8List key;
  final List<int> members;
}

/// The whole group's setup, made on the base laptop (tools/ecp_base) after it scanned every
/// phone's contact QR: all members' cards, the teams with their keys and members, the team
/// whose private LoRa channel the radios use, and the PACE order. Each phone scans it and
/// sets itself up (docs/ARCHITECTURE_V2.md §5).
///
/// It carries every team's key: show it only at the base, in person.
///
/// `'G' · version · u8 n · (u16 len · card)*n · u8 t · (u8 len · name · key[32] · u8 m ·
/// u8 member*m)*t · u8 loraTeam (0xff: none) · u8 p · u8 layer*p (p = 0: keep the order)`
class GroupBundle {
  GroupBundle({required this.members, this.teams = const [], this.loraTeam, this.pace}) {
    if (members.isEmpty || members.length > 250) throw ArgumentError('1..250 members');
    if (teams.length > 250) throw ArgumentError('at most 250 teams');
    for (final t in teams) {
      if (t.members.any((m) => m < 0 || m >= members.length)) throw ArgumentError('no such member');
    }
    if (loraTeam != null && (loraTeam! < 0 || loraTeam! >= teams.length)) {
      throw ArgumentError('no such team for LoRa');
    }
    if (pace != null && (pace!.length != PaceLayer.values.length || pace!.toSet().length != pace!.length)) {
      throw ArgumentError('PACE order must name every layer once');
    }
  }

  static const _magic = 0x47; // 'G'
  static const version = 1;

  final List<ContactCard> members;
  final List<GroupTeam> teams;

  /// Index into [teams]; null: the radios keep their channel.
  final int? loraTeam;

  /// Null: every phone keeps its own order.
  final List<PaceLayer>? pace;

  /// The member whose ECP key is [key], or null when this phone is not in the bundle.
  int? indexOf(List<int> key) {
    for (final (i, m) in members.indexed) {
      if (constantTimeEquals(m.ecpKey, key)) return i;
    }
    return null;
  }

  Uint8List encode() {
    final w = ByteWriter()
      ..u8(_magic)
      ..u8(version)
      ..u8(members.length);
    for (final m in members) {
      final c = m.encode();
      w
        ..u16(c.length)
        ..bytes(c);
    }
    w.u8(teams.length);
    for (final t in teams) {
      final name = utf8.encode(t.name);
      w
        ..u8(name.length)
        ..bytes(name)
        ..bytes(t.key)
        ..u8(t.members.length)
        ..bytes(t.members);
    }
    w
      ..u8(loraTeam ?? 0xff)
      ..u8(pace?.length ?? 0)
      ..bytes([for (final l in pace ?? const <PaceLayer>[]) l.index]);
    return w.toBytes();
  }

  static GroupBundle decode(List<int> data) {
    try {
      final r = ByteReader(data);
      if (r.u8() != _magic) throw const FormatException('not a group bundle');
      final v = r.u8();
      if (v != version) throw FormatException('unsupported group bundle version $v');
      final members = [for (var i = r.u8(); i > 0; i--) ContactCard.decode(r.take(r.u16()))];
      final teams = [
        for (var i = r.u8(); i > 0; i--)
          GroupTeam(
            name: utf8.decode(r.take(r.u8())),
            key: r.take(32),
            members: r.take(r.u8()).toList(),
          ),
      ];
      final lora = r.u8();
      final p = r.u8();
      final pace = p == 0 ? null : [for (final i in r.take(p)) PaceLayer.values[i]];
      if (r.remaining != 0) throw const FormatException('trailing bytes');
      return GroupBundle(members: members, teams: teams, loraTeam: lora == 0xff ? null : lora, pace: pace);
    } on FormatException {
      rethrow;
    } on Object catch (e) {
      // short data, bad indexes, invalid names or keys
      throw FormatException('invalid group bundle: $e');
    }
  }

  // --- as a series of QR codes ---

  static const qrPrefix = 'l0ck://g/';

  /// Splits [data] into QR texts `l0ck://g/<id>/<i>/<n>/<base64url part>` (i from 1). [id]
  /// keeps parts of two different bundles apart; [chunk] bytes per QR keeps each code
  /// readable from a laptop screen.
  static List<String> toQrParts(List<int> data, {required String id, int chunk = 700}) {
    if (!RegExp(r'^[0-9a-f]{8}$').hasMatch(id)) throw ArgumentError('id must be 8 hex digits');
    final n = (data.length + chunk - 1) ~/ chunk;
    return [
      for (var i = 0; i < n; i++)
        '$qrPrefix$id/${i + 1}/$n/'
            '${base64Url.encode(data.sublist(i * chunk, min((i + 1) * chunk, data.length))).replaceAll('=', '')}',
    ];
  }
}

/// Collects the QR parts of one bundle in any order, scanned one by one.
class GroupBundleAssembler {
  String? _id;
  int _total = 0;
  final Map<int, Uint8List> _parts = {};

  int get have => _parts.length;
  int get total => _total;
  bool get complete => _total > 0 && _parts.length == _total;

  /// The first part not scanned yet (1-based), for the scanner's prompt.
  int get next {
    for (var i = 1; i <= _total; i++) {
      if (!_parts.containsKey(i)) return i;
    }
    return _total;
  }

  static bool isPart(String s) => s.trim().startsWith(GroupBundle.qrPrefix);

  /// Adds one scanned part. Throws [FormatException] for anything that is not a part of
  /// the bundle being collected (another bundle's part restarts nothing: it is refused).
  void add(String qr) {
    final s = qr.trim();
    if (!isPart(s)) throw const FormatException('not a group bundle QR');
    final f = s.substring(GroupBundle.qrPrefix.length).split('/');
    if (f.length != 4) throw const FormatException('bad group bundle QR');
    final i = int.tryParse(f[1]), n = int.tryParse(f[2]);
    if (!RegExp(r'^[0-9a-f]{8}$').hasMatch(f[0]) || i == null || n == null || n < 1 || n > 255 || i < 1 || i > n) {
      throw const FormatException('bad group bundle QR');
    }
    if (_id != null && (f[0] != _id || n != _total)) throw const FormatException('another group bundle');
    final Uint8List bytes;
    try {
      bytes = base64Url.decode(f[3].padRight(f[3].length + (4 - f[3].length % 4) % 4, '='));
    } on FormatException {
      throw const FormatException('bad group bundle QR');
    }
    _id = f[0];
    _total = n;
    _parts[i] = bytes;
  }

  /// The whole bundle once [complete].
  GroupBundle bundle() {
    if (!complete) throw StateError('parts missing');
    final b = BytesBuilder();
    for (var i = 1; i <= _total; i++) {
      b.add(_parts[i]!);
    }
    return GroupBundle.decode(b.toBytes());
  }
}
