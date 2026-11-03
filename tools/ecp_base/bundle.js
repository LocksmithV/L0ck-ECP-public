// Group bundle for the base laptop: the same format as packages/ecp_core/lib/src/group_bundle.dart
// (docs/ARCHITECTURE_V2.md §5). Plain script: a global `EcpBundle` in the browser, a module in
// Node (test/bundle_test.js). Nothing here touches the network.
(function (root) {
  'use strict';

  const CARD_PREFIX = 'l0ck://c/';
  const QR_PREFIX = 'l0ck://g/';
  const CARD_VERSION = 2;
  const MAGIC = 0x47; // 'G'
  const VERSION = 1;
  const MAX_TEAM_NAME = 40;
  const utf8 = new TextEncoder();

  function b64urlDecode(s) {
    const b64 = s.replace(/-/g, '+').replace(/_/g, '/');
    const bin = atob(b64 + '='.repeat((4 - (b64.length % 4)) % 4));
    return Uint8Array.from(bin, (c) => c.charCodeAt(0));
  }

  function b64urlEncode(bytes) {
    let bin = '';
    for (const b of bytes) bin += String.fromCharCode(b);
    return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }

  function hex(bytes) {
    return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
  }

  function random(n) {
    return crypto.getRandomValues(new Uint8Array(n));
  }

  /** A phone's contact QR: its bytes, name and key. Team cards are refused (they carry a team key). */
  function parseCard(text) {
    const s = String(text).trim();
    if (!s.startsWith(CARD_PREFIX)) throw new Error('not-card');
    let bytes;
    try {
      bytes = b64urlDecode(s.slice(CARD_PREFIX.length));
    } catch (_) {
      throw new Error('bad-card');
    }
    if (bytes[0] !== CARD_VERSION) throw new Error('bad-card');
    const fields = new Map();
    let i = 1;
    while (i < bytes.length) {
      if (i + 3 > bytes.length) throw new Error('bad-card');
      const tag = bytes[i];
      const len = (bytes[i + 1] << 8) | bytes[i + 2];
      i += 3;
      if (i + len > bytes.length || fields.has(tag)) throw new Error('bad-card');
      fields.set(tag, bytes.slice(i, i + len));
      i += len;
    }
    const name = fields.get(0x01), key = fields.get(0x02);
    if (!name || !key || key.length !== 32) throw new Error('bad-card');
    if (fields.has(0x10)) throw new Error('team-card');
    const phone = fields.get(0x05);
    return {
      bytes,
      name: new TextDecoder().decode(name),
      key: hex(key),
      phone: phone ? new TextDecoder().decode(phone) : null,
    };
  }

  /**
   * members: [{bytes}], teams: [{name, key: Uint8Array(32), members: [index]}],
   * loraTeam: index or null, pace: [layer index ×4] or null.
   */
  function encodeBundle({ members, teams = [], loraTeam = null, pace = null }) {
    if (members.length < 1 || members.length > 250) throw new Error('members');
    if (teams.length > 250) throw new Error('teams');
    const out = [MAGIC, VERSION, members.length];
    for (const m of members) {
      out.push(m.bytes.length >> 8, m.bytes.length & 0xff, ...m.bytes);
    }
    out.push(teams.length);
    for (const t of teams) {
      const name = utf8.encode(t.name);
      if (name.length < 1 || name.length > MAX_TEAM_NAME) throw new Error('team-name');
      if (t.key.length !== 32) throw new Error('team-key');
      if (t.members.some((i) => i < 0 || i >= members.length)) throw new Error('team-member');
      out.push(name.length, ...name, ...t.key, t.members.length, ...t.members);
    }
    if (loraTeam !== null && (loraTeam < 0 || loraTeam >= teams.length)) throw new Error('lora');
    out.push(loraTeam === null ? 0xff : loraTeam);
    if (pace !== null) {
      if (pace.length !== 4 || new Set(pace).size !== 4 || pace.some((p) => p < 0 || p > 3)) throw new Error('pace');
      out.push(4, ...pace);
    } else {
      out.push(0);
    }
    return Uint8Array.from(out);
  }

  /** QR texts `l0ck://g/<id>/<i>/<n>/<base64url part>`, i from 1. */
  function qrParts(bytes, id, chunk = 700) {
    if (!/^[0-9a-f]{8}$/.test(id)) throw new Error('id');
    const n = Math.ceil(bytes.length / chunk);
    const parts = [];
    for (let i = 0; i < n; i++) {
      parts.push(`${QR_PREFIX}${id}/${i + 1}/${n}/${b64urlEncode(bytes.slice(i * chunk, (i + 1) * chunk))}`);
    }
    return parts;
  }

  const api = { parseCard, encodeBundle, qrParts, random, hex, b64urlEncode, b64urlDecode, MAX_TEAM_NAME };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.EcpBundle = api;
})(typeof self !== 'undefined' ? self : this);
