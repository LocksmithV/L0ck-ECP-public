import 'dart:convert';

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
}
