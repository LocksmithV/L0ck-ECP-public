import 'dart:convert';
import 'dart:typed_data';

import 'bytes.dart';

/// One QR that sets up every layer for a contact (docs/ARCHITECTURE_V2.md §5):
/// `l0ck://c/<base64url(version · (tag u8 · len u16 · value)*)>`.
class ContactCard {
  ContactCard({
    required this.name,
    required this.ecpKey,
    this.briarLink,
    this.simplexLink,
    this.phone,
    this.meshtasticNodeId,
    this.meshcoreKey,
    this.teamKey,
  }) {
    if (utf8.encode(name).length > maxName || name.isEmpty) {
      throw ArgumentError('name must be 1..$maxName bytes');
    }
    _require32(ecpKey, 'ecp key');
    if (meshcoreKey != null) _require32(meshcoreKey!, 'MeshCore key');
    if (teamKey != null) _require32(teamKey!, 'team key');
    if (meshtasticNodeId != null &&
        (meshtasticNodeId! < 0 || meshtasticNodeId! > 0xffffffff)) {
      throw ArgumentError('Meshtastic node id must be u32');
    }
  }

  static const version = 2;
  static const maxName = 24;
  static const uriPrefix = 'l0ck://c/';

  static const _tName = 0x01;
  static const _tEcp = 0x02;
  static const _tBriar = 0x03;
  static const _tSimplex = 0x04;
  static const _tPhone = 0x05;
  static const _tMeshtastic = 0x06;
  static const _tMeshcore = 0x07;
  static const _tTeam = 0x10;

  final String name;
  final Uint8List ecpKey;
  final String? briarLink;
  final String? simplexLink;
  final String? phone;
  final int? meshtasticNodeId;
  final Uint8List? meshcoreKey;

  /// Present only on a team-join card. Show such a QR in person only — anyone who
  /// photographs it can read team traffic.
  final Uint8List? teamKey;

  bool get isTeamCard => teamKey != null;

  Uint8List encode() {
    final w = ByteWriter()..u8(version);
    void field(int tag, List<int>? value) {
      if (value == null) return;
      w
        ..u8(tag)
        ..u16(value.length)
        ..bytes(value);
    }

    field(_tName, utf8.encode(name));
    field(_tEcp, ecpKey);
    field(_tBriar, briarLink == null ? null : utf8.encode(briarLink!));
    field(_tSimplex, simplexLink == null ? null : utf8.encode(simplexLink!));
    field(_tPhone, phone == null ? null : utf8.encode(phone!));
    if (meshtasticNodeId != null) {
      field(_tMeshtastic, (ByteWriter()..u32(meshtasticNodeId!)).toBytes());
    }
    field(_tMeshcore, meshcoreKey);
    field(_tTeam, teamKey);
    return w.toBytes();
  }

  static ContactCard decode(List<int> data) {
    final r = ByteReader(data);
    final v = r.u8();
    if (v != version) throw FormatException('unsupported contact card version $v');
    final fields = <int, Uint8List>{};
    while (r.remaining > 0) {
      final tag = r.u8();
      final value = r.take(r.u16());
      if (fields.containsKey(tag)) throw FormatException('duplicate field $tag');
      fields[tag] = value; // unknown tags are kept but ignored: forward compatible
    }
    final name = fields[_tName];
    final ecp = fields[_tEcp];
    if (name == null || ecp == null) {
      throw const FormatException('contact card needs a name and an ECP key');
    }
    final mt = fields[_tMeshtastic];
    if (mt != null && mt.length != 4) throw const FormatException('bad Meshtastic id');
    try {
      return ContactCard(
        name: utf8.decode(name),
        ecpKey: ecp,
        briarLink: _str(fields[_tBriar]),
        simplexLink: _str(fields[_tSimplex]),
        phone: _str(fields[_tPhone]),
        meshtasticNodeId: mt == null ? null : ByteReader(mt).u32(),
        meshcoreKey: fields[_tMeshcore],
        teamKey: fields[_tTeam],
      );
    } on ArgumentError catch (e) {
      throw FormatException('invalid contact card: ${e.message}');
    }
  }

  String toUri() => uriPrefix + base64Url.encode(encode()).replaceAll('=', '');

  static ContactCard fromUri(String uri) {
    final s = uri.trim();
    if (!s.startsWith(uriPrefix)) throw const FormatException('not an L0ck contact card');
    final b64 = s.substring(uriPrefix.length);
    final padded = b64.padRight(b64.length + (4 - b64.length % 4) % 4, '=');
    return decode(base64Url.decode(padded));
  }

  static String? _str(Uint8List? b) => b == null ? null : utf8.decode(b);

  static void _require32(List<int> k, String what) {
    if (k.length != 32) throw ArgumentError('$what must be 32 bytes');
  }
}
