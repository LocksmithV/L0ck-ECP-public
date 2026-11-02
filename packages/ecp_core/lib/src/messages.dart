import 'dart:convert';
import 'dart:typed_data';

import 'bytes.dart';
import 'envelope.dart';

/// Payload types carried in [InnerMessage.type] (docs/ARCHITECTURE_V2.md §4).
abstract final class MessageType {
  static const position = 0x01;
  static const text = 0x02;
  static const report = 0x03;
  static const ack = 0x04;
  static const control = 0x05; // reserved: key rotation, team key over P/A
}

/// 13-byte position: small enough that a report plus envelope fits one SMS / LoRa packet.
class Position {
  const Position({
    required this.lat,
    required this.lon,
    this.altitude,
    this.accuracy,
    this.course,
    this.speed,
  });

  static const length = 13;
  static const _unknownAlt = -0x8000;
  static const _unknownU8 = 0xff;

  final double lat;
  final double lon;

  /// Metres; null when unknown.
  final int? altitude;

  /// Metres, capped at 254; null when unknown.
  final int? accuracy;

  /// Degrees, 2° resolution; null when unknown.
  final double? course;

  /// m/s, 0.5 m/s resolution, capped at 127 m/s; null when unknown.
  final double? speed;

  void writeTo(ByteWriter w) {
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      throw ArgumentError('coordinates out of range: $lat, $lon');
    }
    w
      ..i32((lat * 1e7).round())
      ..i32((lon * 1e7).round())
      ..i16(altitude == null ? _unknownAlt : altitude!.clamp(-0x7fff, 0x7fff))
      ..u8(accuracy == null ? _unknownU8 : accuracy!.clamp(0, 254))
      ..u8(course == null ? _unknownU8 : ((course! % 360) / 2).round() % 180)
      ..u8(speed == null ? _unknownU8 : (speed! * 2).round().clamp(0, 254));
  }

  static Position readFrom(ByteReader r) {
    final lat = r.i32() / 1e7;
    final lon = r.i32() / 1e7;
    final alt = r.i16();
    final acc = r.u8();
    final crs = r.u8();
    final spd = r.u8();
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      throw const FormatException('coordinates out of range');
    }
    return Position(
      lat: lat,
      lon: lon,
      altitude: alt == _unknownAlt ? null : alt,
      accuracy: acc == _unknownU8 ? null : acc,
      course: crs == _unknownU8 ? null : crs * 2.0,
      speed: spd == _unknownU8 ? null : spd / 2.0,
    );
  }

  Uint8List encode() {
    final w = ByteWriter();
    writeTo(w);
    return w.toBytes();
  }

  static Position decode(List<int> data) {
    final r = ByteReader(data);
    final p = readFrom(r);
    if (r.remaining != 0) throw const FormatException('trailing bytes after position');
    return p;
  }

  @override
  String toString() => 'Position($lat, $lon, alt=$altitude, acc=$accuracy)';
}

Uint8List encodeText(String text) => Uint8List.fromList(utf8.encode(text));

String decodeText(List<int> data) => utf8.decode(data); // throws FormatException on bad UTF-8

Uint8List encodeAck(List<int> messageId) {
  if (messageId.length != 8) throw ArgumentError('message id must be 8 bytes');
  return Uint8List.fromList(messageId);
}

Uint8List decodeAck(List<int> data) {
  if (data.length != 8) throw const FormatException('ack must carry an 8-byte id');
  return Uint8List.fromList(data);
}

// --- reports (§4, "Šablony hlášení") ---

abstract final class ReportTemplate {
  static const status = 0x01;
  static const rally = 0x02;
  static const medevac = 0x03;
  static const sitrep = 0x04;
  static const salter = 0x05;
  static const fiveW = 0x06;
}

enum StatusCode {
  ok(0),
  needHelp(1),
  compromised(2),
  injured(3),
  moving(4),
  inPosition(5);

  const StatusCode(this.code);
  final int code;

  static StatusCode fromCode(int c) => StatusCode.values.firstWhere(
        (s) => s.code == c,
        orElse: () => throw FormatException('unknown status code $c'),
      );
}

sealed class Report {
  const Report();

  int get templateId;

  void _writeFields(ByteWriter w);

  Uint8List encode() {
    final w = ByteWriter()..u8(templateId);
    _writeFields(w);
    return w.toBytes();
  }

  static Report decode(List<int> data) {
    final r = ByteReader(data);
    final report = switch (r.u8()) {
      ReportTemplate.status => StatusReport._read(r),
      ReportTemplate.rally => RallyReport._read(r),
      ReportTemplate.medevac => MedevacReport._read(r),
      ReportTemplate.sitrep => SitrepReport._read(r),
      ReportTemplate.salter => SalterReport._read(r),
      ReportTemplate.fiveW => FiveWReport._read(r),
      final t => throw FormatException('unknown report template $t'),
    };
    if (r.remaining != 0) throw const FormatException('trailing bytes after report');
    return report;
  }
}

class StatusReport extends Report {
  const StatusReport(this.status, [this.position]);

  final StatusCode status;
  final Position? position;

  @override
  int get templateId => ReportTemplate.status;

  @override
  void _writeFields(ByteWriter w) {
    w.u8(status.code);
    position?.writeTo(w);
  }

  static StatusReport _read(ByteReader r) {
    final status = StatusCode.fromCode(r.u8());
    return StatusReport(status, r.remaining > 0 ? Position.readFrom(r) : null);
  }
}

class RallyReport extends Report {
  const RallyReport(this.point, this.at);

  final Position point;
  final DateTime at;

  @override
  int get templateId => ReportTemplate.rally;

  @override
  void _writeFields(ByteWriter w) {
    point.writeTo(w);
    w.u32(ecpTime(at));
  }

  static RallyReport _read(ByteReader r) =>
      RallyReport(Position.readFrom(r), fromEcpTime(r.u32()));
}

/// Standard 9-line MEDEVAC request, encoded as enum codes; the UI maps codes to labels.
class MedevacReport extends Report {
  MedevacReport({
    required this.location,
    required this.callsign,
    required this.patientsByPrecedence,
    required this.equipment,
    required this.litter,
    required this.ambulatory,
    required this.security,
    required this.marking,
    required this.nationality,
    required this.terrain,
  }) {
    if (patientsByPrecedence.length != 5) {
      throw ArgumentError('line 3 needs 5 counts (A urgent … E convenience)');
    }
    final cs = ascii.encode(callsign); // throws on non-ASCII
    if (cs.length > maxCallsign) throw ArgumentError('callsign longer than $maxCallsign');
  }

  static const maxCallsign = 8;

  final Position location; // line 1
  final String callsign; // line 2
  final List<int> patientsByPrecedence; // line 3: A urgent, B urgent-surgical, C priority, D routine, E convenience
  final int equipment; // line 4
  final int litter; // line 5
  final int ambulatory; // line 5
  final int security; // line 6
  final int marking; // line 7
  final int nationality; // line 8
  final int terrain; // line 9

  @override
  int get templateId => ReportTemplate.medevac;

  @override
  void _writeFields(ByteWriter w) {
    location.writeTo(w);
    final cs = ascii.encode(callsign);
    w
      ..u8(cs.length)
      ..bytes(cs);
    patientsByPrecedence.forEach(w.u8);
    w
      ..u8(equipment)
      ..u8(litter)
      ..u8(ambulatory)
      ..u8(security)
      ..u8(marking)
      ..u8(nationality)
      ..u8(terrain);
  }

  static MedevacReport _read(ByteReader r) {
    final location = Position.readFrom(r);
    final csLen = r.u8();
    if (csLen > maxCallsign) throw const FormatException('callsign too long');
    final callsign = ascii.decode(r.take(csLen));
    return MedevacReport(
      location: location,
      callsign: callsign,
      patientsByPrecedence: [for (var i = 0; i < 5; i++) r.u8()],
      equipment: r.u8(),
      litter: r.u8(),
      ambulatory: r.u8(),
      security: r.u8(),
      marking: r.u8(),
      nationality: r.u8(),
      terrain: r.u8(),
    );
  }
}

class SitrepReport extends Report {
  SitrepReport({
    required this.state,
    required this.persons,
    required this.position,
    this.text = '',
  }) {
    if (utf8.encode(text).length > maxText) {
      throw ArgumentError('SITREP text longer than $maxText bytes');
    }
  }

  // 59, not 60: one more byte pushes envelope + SITREP past one 160-character SMS
  static const maxText = 59;

  final int state;
  final int persons;
  final Position position;
  final String text;

  @override
  int get templateId => ReportTemplate.sitrep;

  @override
  void _writeFields(ByteWriter w) {
    w
      ..u8(state)
      ..u8(persons);
    position.writeTo(w);
    w.bytes(utf8.encode(text));
  }

  static SitrepReport _read(ByteReader r) {
    final state = r.u8();
    final persons = r.u8();
    final position = Position.readFrom(r);
    final text = utf8.decode(r.rest());
    if (utf8.encode(text).length > maxText) throw const FormatException('SITREP text too long');
    return SitrepReport(state: state, persons: persons, position: position, text: text);
  }
}

/// Short texts in the observation reports: u8 length + UTF-8 each, all of them together at
/// most [maxReportText] bytes, so a report stays within one LoRa packet (two SMS at most).
const maxReportText = 90;

void _texts(ByteWriter w, List<String> texts) {
  final enc = [for (final t in texts) utf8.encode(t)];
  if (enc.fold<int>(0, (n, e) => n + e.length) > maxReportText) {
    throw ArgumentError('report texts longer than $maxReportText bytes together');
  }
  for (final e in enc) {
    w
      ..u8(e.length)
      ..bytes(e);
  }
}

List<String> _readTexts(ByteReader r, int n) {
  final out = [for (var i = 0; i < n; i++) utf8.decode(r.take(r.u8()))];
  if (out.fold<int>(0, (s, t) => s + utf8.encode(t).length) > maxReportText) {
    throw const FormatException('report texts too long');
  }
  return out;
}

/// SALTER observation: Size, Activity, Location, Time, Equipment, Remarks.
class SalterReport extends Report {
  SalterReport({
    required this.size,
    required this.activity,
    required this.location,
    required this.time,
    this.equipment = '',
    this.remarks = '',
  }) {
    if (size < 0 || size > 0xffff) throw ArgumentError('size out of range');
    _texts(ByteWriter(), [activity, equipment, remarks]); // validates the length
  }

  /// How many (persons, vehicles…), as counted.
  final int size;
  final String activity;
  final Position location;
  final DateTime time;
  final String equipment;
  final String remarks;

  @override
  int get templateId => ReportTemplate.salter;

  @override
  void _writeFields(ByteWriter w) {
    w.u16(size);
    location.writeTo(w);
    w.u32(ecpTime(time));
    _texts(w, [activity, equipment, remarks]);
  }

  static SalterReport _read(ByteReader r) {
    final size = r.u16();
    final location = Position.readFrom(r);
    final time = fromEcpTime(r.u32());
    final t = _readTexts(r, 3);
    return SalterReport(
        size: size, activity: t[0], location: location, time: time, equipment: t[1], remarks: t[2]);
  }
}

/// 5W: Who, What, Where, When, Why.
class FiveWReport extends Report {
  FiveWReport({
    required this.who,
    required this.what,
    required this.where,
    required this.when,
    this.why = '',
  }) {
    _texts(ByteWriter(), [who, what, why]);
  }

  final String who;
  final String what;
  final Position where;
  final DateTime when;
  final String why;

  @override
  int get templateId => ReportTemplate.fiveW;

  @override
  void _writeFields(ByteWriter w) {
    where.writeTo(w);
    w.u32(ecpTime(when));
    _texts(w, [who, what, why]);
  }

  static FiveWReport _read(ByteReader r) {
    final where = Position.readFrom(r);
    final when = fromEcpTime(r.u32());
    final t = _readTexts(r, 3);
    return FiveWReport(who: t[0], what: t[1], where: where, when: when, why: t[2]);
  }
}
