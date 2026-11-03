import 'dart:convert';
import 'dart:typed_data';

import 'package:ecp_core/ecp_core.dart';
import 'package:test/test.dart';

void main() {
  const prague = Position(
      lat: 50.0875411, lon: 14.4213304, altitude: 245, accuracy: 6, course: 87, speed: 1.4);

  group('position', () {
    test('is 13 bytes and keeps ~1 cm precision', () {
      final enc = prague.encode();
      expect(enc, hasLength(Position.length));
      final p = Position.decode(enc);
      expect((p.lat - prague.lat).abs(), lessThan(1e-7));
      expect((p.lon - prague.lon).abs(), lessThan(1e-7));
      expect(p.altitude, 245);
      expect(p.accuracy, 6);
      expect(p.course, 88); // 2° resolution
      expect(p.speed, 1.5); // 0.5 m/s resolution
    });

    test('unknown fields stay unknown, out-of-range values are clamped', () {
      final p = Position.decode(const Position(lat: -33.86, lon: 151.21).encode());
      expect(p.altitude, isNull);
      expect(p.accuracy, isNull);
      expect(p.course, isNull);
      expect(p.speed, isNull);
      final c = Position.decode(const Position(
              lat: 0, lon: 0, altitude: 100000, accuracy: 9999, course: 359, speed: 500)
          .encode());
      expect(c.altitude, 0x7fff);
      expect(c.accuracy, 254);
      expect(c.course, 0); // 359° rounds to 360° = 0°
      expect(c.speed, 127);
    });

    test('rejects impossible coordinates', () {
      expect(() => const Position(lat: 91, lon: 0).encode(), throwsArgumentError);
      expect(() => const Position(lat: 0, lon: -181).encode(), throwsArgumentError);
      expect(() => Position.decode([1, 2, 3]), throwsFormatException);
    });
  });

  group('reports', () {
    test('status with and without position', () {
      final s = Report.decode(const StatusReport(StatusCode.needHelp, prague).encode())
          as StatusReport;
      expect(s.status, StatusCode.needHelp);
      expect(s.position, isNotNull);
      final bare =
          Report.decode(const StatusReport(StatusCode.compromised).encode()) as StatusReport;
      expect(bare.status, StatusCode.compromised);
      expect(bare.position, isNull);
    });

    test('rally keeps place and time (to the second)', () {
      final at = DateTime.utc(2026, 11, 2, 5, 30);
      final r = Report.decode(RallyReport(prague, at).encode()) as RallyReport;
      expect(r.at, at);
      expect((r.point.lat - prague.lat).abs(), lessThan(1e-7));
    });

    test('MEDEVAC 9-line round-trips', () {
      final m = MedevacReport(
        location: prague,
        callsign: 'L0CK6',
        patientsByPrecedence: const [1, 0, 2, 0, 0],
        equipment: 0,
        litter: 1,
        ambulatory: 2,
        security: 1,
        marking: 2,
        nationality: 3,
        terrain: 0,
      );
      final d = Report.decode(m.encode()) as MedevacReport;
      expect(d.callsign, 'L0CK6');
      expect(d.patientsByPrecedence, [1, 0, 2, 0, 0]);
      expect([d.litter, d.ambulatory, d.security, d.marking, d.nationality],
          [1, 2, 1, 2, 3]);
      expect(() => MedevacReport(
            location: prague,
            callsign: 'TOO-LONG-CALL',
            patientsByPrecedence: const [0, 0, 0, 0, 0],
            equipment: 0,
            litter: 0,
            ambulatory: 0,
            security: 0,
            marking: 0,
            nationality: 0,
            terrain: 0,
          ), throwsArgumentError);
    });

    test('SITREP text is limited to 59 bytes', () {
      final s = SitrepReport(state: 1, persons: 4, position: prague, text: 'Přesun k bodu B');
      expect((Report.decode(s.encode()) as SitrepReport).text, 'Přesun k bodu B');
      expect(() => SitrepReport(state: 0, persons: 0, position: prague, text: 'x' * 60),
          throwsArgumentError);
    });

    test('unknown template and trailing bytes are rejected', () {
      expect(() => Report.decode([0x7f]), throwsFormatException);
      expect(() => Report.decode([...const StatusReport(StatusCode.ok).encode(), 0, 0]),
          throwsFormatException);
    });
  });

  group('size budget (docs §4): every report fits one SMS and one LoRa packet', () {
    // One GSM-7 SMS carries 160 characters; base64url of n bytes is ceil(4n/3) characters.
    int b64(int n) => (4 * n / 3).ceil();
    int envelope(int payload) =>
        EcpEnvelope.overhead + EcpEnvelope.innerHeaderLength + payload;

    final cases = {
      'position': prague.encode().length,
      'status + position': const StatusReport(StatusCode.ok, prague).encode().length,
      'ack': encodeAck(List.filled(8, 1)).length,
      'rally': RallyReport(prague, DateTime.utc(2026)).encode().length,
      'MEDEVAC (max callsign)': MedevacReport(
        location: prague,
        callsign: 'ABCDEFGH',
        patientsByPrecedence: const [1, 1, 1, 1, 1],
        equipment: 1,
        litter: 1,
        ambulatory: 1,
        security: 1,
        marking: 1,
        nationality: 1,
        terrain: 1,
      ).encode().length,
      'SITREP (max text)':
          SitrepReport(state: 1, persons: 9, position: prague, text: 'x' * 59).encode().length,
    };

    cases.forEach((name, payload) {
      test(name, () {
        final total = envelope(payload);
        expect(b64(total), lessThanOrEqualTo(160), reason: '$name: $total bytes');
      });
    });

    test('SALTER and 5W with full texts fit one LoRa packet, two SMS at most', () {
      final salter = SalterReport(
          size: 12,
          activity: 'a' * 30,
          location: prague,
          time: DateTime.utc(2026),
          equipment: 'e' * 30,
          remarks: 'r' * 30);
      final fiveW = FiveWReport(
          who: 'w' * 30, what: 'x' * 30, where: prague, when: DateTime.utc(2026), why: 'y' * 30);
      for (final r in [salter, fiveW]) {
        final total = envelope(r.encode().length);
        expect(total, lessThanOrEqualTo(165), reason: 'LoRa datagram');
        expect(b64(total), lessThanOrEqualTo(2 * 153), reason: 'two concatenated SMS');
        expect(Report.decode(r.encode()).templateId, r.templateId);
      }
      expect(() => FiveWReport(who: 'x' * 91, what: '', where: prague, when: DateTime.utc(2026)),
          throwsArgumentError);
      final back = Report.decode(salter.encode()) as SalterReport;
      expect(back.size, 12);
      expect(back.remarks, 'r' * 30);
    });

    test('documented sizes', () {
      expect(envelope(cases['position']!), 58);
      expect(envelope(cases['status + position']!), 60);
      expect(envelope(cases['ack']!), 53);
      expect(envelope(cases['MEDEVAC (max callsign)']!), 80);
    });
  });

  test('text and ack codecs', () {
    expect(decodeText(encodeText('Ahoj, jsem na místě')), 'Ahoj, jsem na místě');
    expect(() => decodeText([0xff, 0xfe]), throwsFormatException);
    expect(decodeAck(encodeAck(utf8.encode('12345678'))), utf8.encode('12345678'));
    expect(() => decodeAck([1, 2]), throwsFormatException);
  });

  test('voice: a clip is cut into parts that join again in any order', () {
    final audio = Uint8List.fromList(List.generate(20000, (i) => i % 251));
    final id = Uint8List.fromList([1, 2, 3, 4]);
    final parts = VoicePart.split(id, VoicePart.opus, 12345, audio);
    expect(parts.map((p) => (p.index, p.count, p.data.length)),
        [for (var i = 1; i <= 7; i++) (i, 7, i < 7 ? VoicePart.maxData : 20000 - 6 * VoicePart.maxData)]);
    final back = [for (final p in parts.reversed) VoicePart.decode(p.encode())];
    final clip = VoicePart.join(back);
    expect((clip.count, clip.codec, clip.durationMs, clip.clipHex), (1, VoicePart.opus, 12345, '01020304'));
    expect(clip.data, audio);
    expect(() => VoicePart.join(back.take(2).toList()), throwsArgumentError);
    expect(() => VoicePart.decode([1, 2, 3]), throwsFormatException);
    expect(() => VoicePart.decode([1, 2, 3, 4, 3, 2, 1, 0, 0]), throwsFormatException, reason: 'index > count');
    expect(VoicePart.split(id, VoicePart.aac, 900, Uint8List(100)).single.count, 1);
    // A part with its envelope fits a Bramble message (4096 B, plus its 1-byte kind)
    expect(VoicePart.headerLength + VoicePart.maxData + EcpEnvelope.overhead + EcpEnvelope.teamInnerHeaderLength + 2,
        lessThan(4096));
  });

  test('call signals: offer with SDP, end with a reason', () {
    final id = Uint8List.fromList(List.generate(8, (i) => i));
    final o = CallSignal.decode(CallSignal.sdp(id, CallSignal.offer, 'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111').encode());
    expect((o.callHex, o.kind, o.sdp.startsWith('v=0')), ('0001020304050607', CallSignal.offer, true));
    // A real-size offer (with candidates) shrinks enough for one Bramble message (4 KB)
    final big = List.generate(40, (i) => 'a=candidate:$i 1 udp 2122260223 192.0.2.$i 4${i}000 typ host generation 0\r\n').join();
    final packed = CallSignal.sdp(id, CallSignal.offer, 'v=0\r\n$big').encode();
    expect(packed.length, lessThan(2000));
    expect(CallSignal.decode(packed).sdp, 'v=0\r\n$big');
    expect(() => CallSignal(callId: id, kind: CallSignal.offer, data: Uint8List.fromList([1, 2])).sdp, throwsFormatException);
    final e = CallSignal.decode(CallSignal.ended(id, CallSignal.busy).encode());
    expect((e.kind, e.reason), (CallSignal.end, CallSignal.busy));
    expect(() => CallSignal.decode([1, 2, 3]), throwsFormatException);
    expect(() => CallSignal.decode([...id, 9]), throwsFormatException);
  });

  test('files: an attachment in parts joins again; every part fits a Bramble message', () {
    final photo = Attachment(
        kind: Attachment.photo, name: 'fotka.jpg', mime: 'image/jpeg', bytes: Uint8List.fromList(List.generate(10000, (i) => i % 256)));
    final parts = FilePart.split(Uint8List.fromList([9, 9, 9, 9]), photo.encode());
    expect(parts.length, 4);
    expect(parts.every((p) => p.encode().length + EcpEnvelope.overhead + EcpEnvelope.teamInnerHeaderLength + 2 < 4096), isTrue);
    final back = Attachment.decode(FilePart.join([for (final p in parts.reversed) FilePart.decode(p.encode())]));
    expect((back.kind, back.name, back.mime), (Attachment.photo, 'fotka.jpg', 'image/jpeg'));
    expect(back.bytes, photo.bytes);
    expect(() => FilePart.join(parts.skip(1).toList()), throwsArgumentError);
    expect(() => Attachment.decode([7]), throwsFormatException);
  });

  test('status: own position and a rally point, each optional; the old form still reads', () {
    const me = Position(lat: 50.1, lon: 14.4);
    const meet = Position(lat: 50.2, lon: 14.5);
    final at = DateTime.utc(2026, 11, 4, 13, 6);
    for (final (p, r) in [(null, null), (me, null), (null, (point: meet, at: at)), (me, (point: meet, at: at))]) {
      final back = Report.decode(StatusReport(StatusCode.moving, p, r).encode()) as StatusReport;
      expect(back.status, StatusCode.moving);
      expect(back.position?.lat, p == null ? isNull : closeTo(50.1, 1e-6));
      expect(back.rally?.point.lat, r == null ? isNull : closeTo(50.2, 1e-6));
      expect(back.rally?.at, r?.at);
    }
  });
}
