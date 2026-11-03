// node tools/ecp_base/test/bundle_test.js [--write]
// Checks the base page's encoder and writes (or compares) the fixture the Dart decoder reads:
// packages/ecp_core/test/fixtures/group_bundle_js.txt (group_bundle_test.dart).
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const B = require('../bundle.js');

// Cards made by ContactCard.toUri() in ecp_core
const cards = [
  'l0ck://c/AgEABEFsZmECACABAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQUAECs0MjAgNjAwIDAwMCAwMDE',
  'l0ck://c/AgEABUJyYXZvAgAgAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEAClodHRwczovL3NpbXBsZXguZXhhbXBsZS9hIy8_dj0yJnNtcD10ZXN0Mg',
  'l0ck://c/AgEABcSMw6FwAgAgAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMFABArNDIxIDkwMCAwMDAgMDAz',
];
const teamCard =
  'l0ck://c/AgEABFTDvW0CACAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBBAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

const m = cards.map(B.parseCard);
assert.deepEqual(m.map((c) => c.name), ['Alfa', 'Bravo', 'Čáp']);
assert.equal(m[0].phone, '+420 600 000 001');
assert.equal(m[1].phone, null);
assert.equal(m[2].key, '03'.repeat(32));
assert.throws(() => B.parseCard(teamCard), /team-card/);
assert.throws(() => B.parseCard('l0ck://c/AgEA'), /bad-card/);
assert.throws(() => B.parseCard('https://example.org'), /not-card/);

// The base corrects a name and adds a number; the rest of the card stays
const edited = B.withNameAndPhone(m[1], 'Bravo 2', '+420 777 000 002');
const back2 = B.parseCard('l0ck://c/' + B.b64urlEncode(edited.bytes));
assert.deepEqual([back2.name, back2.phone, back2.key], ['Bravo 2', '+420 777 000 002', m[1].key]);
assert.deepEqual(back2.fields.get(0x04), m[1].fields.get(0x04), 'the SimpleX link is kept');
assert.equal(B.parseCard('l0ck://c/' + B.b64urlEncode(B.withNameAndPhone(m[0], 'Alfa', '').bytes)).phone, null);
assert.throws(() => B.withNameAndPhone(m[0], '', null), /name/);
assert.throws(() => B.withNameAndPhone(m[0], 'x'.repeat(25), null), /name/);
assert.throws(() => B.withNameAndPhone(m[0], 'Alfa', '12a'), /phone/);
// Only international numbers: +, country code, 8–15 digits
for (const ok of ['+420 600 123 456', '+420600123456', '+1 202 555 0143', '+44 20 7946 0958']) assert.ok(B.validPhone(ok), ok);
for (const bad of ['600 123 456', '00420 600 123 456', '+0 600 123 456', '+420 12', '+420 600 123 456 789 012', '+420-600-123']) {
  assert.ok(!B.validPhone(bad), bad);
}

const bundle = B.encodeBundle({
  members: m,
  teams: [
    { name: 'Hlídka', key: new Uint8Array(32).fill(9), members: [0, 1, 2] },
    { name: 'Spojka', key: new Uint8Array(32).fill(8), members: [1] },
  ],
  loraTeam: 0,
  pace: [1, 0, 2, 3],
});
assert.throws(() => B.encodeBundle({ members: m, teams: [{ name: '', key: new Uint8Array(32), members: [] }] }), /team-name/);
assert.throws(() => B.encodeBundle({ members: m, loraTeam: 0 }), /lora/);
assert.throws(() => B.encodeBundle({ members: m, pace: [0, 0, 1, 2] }), /pace/);

const parts = B.qrParts(bundle, 'c0ffee01', 120);
assert.equal(parts.length, Math.ceil(bundle.length / 120));
assert.ok(parts.every((p, i) => p.startsWith(`l0ck://g/c0ffee01/${i + 1}/${parts.length}/`)));
const back = parts.map((p) => B.b64urlDecode(p.split('/').pop()));
assert.deepEqual(Uint8Array.from(back.flatMap((b) => [...b])), bundle);

const fixture = path.join(__dirname, '../../../packages/ecp_core/test/fixtures/group_bundle_js.txt');
const text = parts.join('\n') + '\n';
if (process.argv.includes('--write')) fs.writeFileSync(fixture, text);
else assert.equal(fs.readFileSync(fixture, 'utf8'), text, 'fixture out of date: run with --write');
console.log(`ok: ${bundle.length} B in ${parts.length} QR codes`);
