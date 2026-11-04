// node tools/ecp_base/test/vault_test.js — the encrypted set-up file opens only with its password.
'use strict';
const assert = require('node:assert/strict');
const V = require('../vault.js');

(async () => {
  const setup = { members: ['AgEABEFsZmE='], teams: [{ name: 'Hlídka', key: V.b64(new Uint8Array(32).fill(9)), members: [] }], lora: 0, paceOn: true, pace: [1, 0, 2, 3] };
  const file = await V.seal(setup, 'dlouhé heslo 123');
  assert.ok(!file.includes('Hlídka') && !file.includes('AgEABEFsZmE'), 'nothing readable in the file');
  assert.deepEqual(await V.open(file, 'dlouhé heslo 123'), setup);
  await assert.rejects(V.open(file, 'jiné heslo 1234'), /password/);
  const f = JSON.parse(file);
  f.data = f.data.slice(0, -4) + (f.data.endsWith('AAAA') ? 'BBBB' : 'AAAA');
  await assert.rejects(V.open(JSON.stringify(f), 'dlouhé heslo 123'), /password/, 'a changed file does not open');
  await assert.rejects(V.open('{"format":"jiny"}', 'x'), /format/);
  await assert.rejects(V.open('neni json', 'x'), /format/);
  await assert.rejects(V.seal(setup, 'krátké'), /short/);
  console.log('ok: vault');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
