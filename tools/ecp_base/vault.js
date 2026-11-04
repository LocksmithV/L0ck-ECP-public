// Saving the base page's whole set-up (members, teams with their keys, LoRa, PACE) to a file
// that only a password opens: PBKDF2-SHA256 (600 000 rounds) → AES-256-GCM, WebCrypto only.
// Plain script: a global `EcpVault` in the browser, a module in Node (test/bundle_test.js).
(function (root) {
  'use strict';

  const FORMAT = 'l0ck-ecp-base';
  const VERSION = 1;
  const ROUNDS = 600000;
  const MIN_PASSWORD = 12;

  function b64(bytes) {
    let s = '';
    for (const b of bytes) s += String.fromCharCode(b);
    return btoa(s);
  }

  function unb64(s) {
    return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
  }

  async function key(password, salt, rounds) {
    const base = await crypto.subtle.importKey('raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveKey']);
    return crypto.subtle.deriveKey(
      { name: 'PBKDF2', hash: 'SHA-256', salt, iterations: rounds },
      base,
      { name: 'AES-GCM', length: 256 },
      false,
      ['encrypt', 'decrypt'],
    );
  }

  /** The file's text: the set-up encrypted under [password]. */
  async function seal(setup, password) {
    if (String(password).length < MIN_PASSWORD) throw new Error('short');
    const salt = crypto.getRandomValues(new Uint8Array(16));
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const plain = new TextEncoder().encode(JSON.stringify(setup));
    const data = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await key(password, salt, ROUNDS), plain));
    plain.fill(0);
    return JSON.stringify({ format: FORMAT, v: VERSION, kdf: 'PBKDF2-SHA256', rounds: ROUNDS, salt: b64(salt), iv: b64(iv), data: b64(data) });
  }

  /** The set-up from a file's text; throws 'format' for another file, 'password' when it does not open. */
  async function open(text, password) {
    let f;
    try {
      f = JSON.parse(text);
    } catch (_) {
      throw new Error('format');
    }
    if (!f || f.format !== FORMAT || f.v !== VERSION || typeof f.data !== 'string') throw new Error('format');
    let plain;
    try {
      const k = await key(password, unb64(f.salt), f.rounds);
      plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: unb64(f.iv) }, k, unb64(f.data));
    } catch (_) {
      throw new Error('password'); // AES-GCM refuses a wrong key and any change to the file
    }
    return JSON.parse(new TextDecoder().decode(plain));
  }

  const api = { seal, open, b64, unb64, MIN_PASSWORD };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.EcpVault = api;
})(typeof self !== 'undefined' ? self : this);
