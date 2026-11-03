// L0ck-ECP base page: scan every phone's contact QR, set up teams, LoRa and PACE, then show
// the group bundle as a series of QR codes for the phones (Contacts → Load group bundle).
// Everything lives in this tab's memory only; closing it or "Erase all" forgets it.
'use strict';

/** Czech plural: 1 telefon, 2–4 telefony, 5+ telefonů. */
const cz = (n, one, few, many) => `${n} ${n === 1 ? one : n >= 2 && n <= 4 ? few : many}`;

const T = {
  cs: {
    title: 'Základna · hromadné nastavení skupiny',
    wipe: 'Smazat vše',
    intro: 'Funguje bez internetu, nic neukládá. Postup: načti kontaktní QR všech telefonů, založ týmy, pak ukaž balíček skupiny a každý telefon ho načte v aplikaci (Kontakty → ikona skeneru → Načíst balíček skupiny).',
    s1: 'Členové',
    s1help: 'Na každém telefonu otevři Můj kontakt a podrž QR před kamerou. Odkaz jde i vložit.',
    camStart: 'Zapnout kameru', camStop: 'Vypnout kameru',
    pastePh: 'l0ck://c/…', load: 'Načíst',
    camOffHint: 'Zapni kameru a podrž QR telefonu ve čtverci.',
    stOff: 'KAMERA VYPNUTÁ', stReading: 'HLEDÁM QR', stFound: 'NAČTENO', stKnown: 'UŽ V SEZNAMU',
    stError: 'NEPLATNÝ QR', stEdit: 'ÚPRAVA',
    offMsg: 'Odkaz jde vložit i do pole pod kamerou.',
    readingMsg: 'Podrž kontaktní QR telefonu ve čtverci.',
    foundMsg: 'Zkontroluj jméno a číslo, pak Přidat.',
    nameLbl: 'Jméno', phoneLbl: 'Telefon (SMS)',
    accept: 'Přidat', save: 'Uložit', retry: 'Znovu', edit: 'Upravit',
    nameBad: 'Jméno musí mít 1–24 B.', phoneBad: 'Číslo může obsahovat jen +, číslice a mezery.',
    saved: (n) => `Uloženo: ${n}`,
    members: (n) => `Načteno: ${n}`,
    noMembers: 'Zatím nikdo.',
    added: (n) => `Přidán: ${n}`,
    known: (n) => `${n} už je v seznamu.`,
    'not-card': 'Tohle není kontaktní QR L0ck-ECP.',
    'bad-card': 'Kontaktní QR je poškozený.',
    'team-card': 'Tohle je týmový QR. Na telefonu ukaž Můj kontakt.',
    isBundle: 'Tohle je balíček skupiny, ne kontakt.',
    camErr: 'Kamera není dostupná. Povol ji prohlížeči, nebo odkazy vlož ručně.',
    remove: 'Smazat', qr: 'QR', close: 'Zavřít',
    cardHelp: 'Kontakt tak, jak ho dostanou ostatní (i s úpravami). Telefon ho načte jako běžný kontakt.',
    s2: 'Týmy',
    s2help: 'Každý tým dostane nový náhodný klíč. Telefon se připojí jen k týmům, kde je zaškrtnutý. Kanál LoRa: rádia členů vybraného týmu se přepnou na jeho soukromý kanál.',
    addTeam: 'Přidat tým', teamDefault: (n) => `Tým ${n}`,
    all: 'Všichni', lora: 'Kanál LoRa', loraNone: 'Rádia ponechat, jak jsou',
    deleteTeam: 'Smazat tým',
    s3: 'Pořadí PACE',
    paceOn: 'Nastavit všem stejné pořadí kanálů',
    layers: ['SimpleX', 'Bramble (Tor / Wi-Fi / BT)', 'LoRa', 'SMS'],
    s4: 'Balíček skupiny',
    s4warn: 'Balíček obsahuje klíče týmů. Ukazuj ho jen na základně, osobně. Po nastavení všech telefonů dej Smazat vše.',
    make: 'Vytvořit balíček',
    part: (i, n) => `QR ${i} z ${n}`,
    auto: 'Střídat samo (3 s)',
    size: (b, n) => `${b} B v ${n} QR. Po každé změně nahoře vytvoř balíček znovu.`,
    needMember: 'Načti aspoň jeden telefon.',
    needName: 'Každý tým potřebuje název (nejvýš 40 B).',
    needTeamMember: (t) => `Tým „${t}“ nemá žádného člena.`,
    wipeAsk: 'Smazat všechny načtené kontakty, týmy a klíče z této stránky?',
    author: 'autor',
    stMembers: (n) => (n ? cz(n, 'telefon', 'telefony', 'telefonů') : 'nikdo'),
    stTeams: (n) => (n ? cz(n, 'tým', 'týmy', 'týmů') : 'bez týmů'),
    stPace: (on) => (on ? 'nastaví se' : 'beze změny'),
    stBundle: (n) => (n ? `${n} QR připraveno` : 'nevytvořen'),
  },
  en: {
    title: 'Base · group setup',
    wipe: 'Erase all',
    intro: 'Works without internet and stores nothing. Steps: scan every phone\'s contact QR, set up teams, then show the group bundle; each phone loads it in the app (Contacts → scanner icon → Load group bundle).',
    s1: 'Members',
    s1help: 'On each phone open My contact and hold its QR up to the camera. A link can be pasted too.',
    camStart: 'Start camera', camStop: 'Stop camera',
    pastePh: 'l0ck://c/…', load: 'Load',
    camOffHint: 'Start the camera and hold the phone\'s QR inside the square.',
    stOff: 'CAMERA OFF', stReading: 'SCANNING', stFound: 'READ', stKnown: 'ALREADY LISTED',
    stError: 'INVALID QR', stEdit: 'EDIT',
    offMsg: 'A link can also be pasted below the camera.',
    readingMsg: 'Hold the phone\'s contact QR inside the square.',
    foundMsg: 'Check the name and number, then Add.',
    nameLbl: 'Name', phoneLbl: 'Phone (SMS)',
    accept: 'Add', save: 'Save', retry: 'Again', edit: 'Edit',
    nameBad: 'The name must be 1–24 B.', phoneBad: 'A number may hold only +, digits and spaces.',
    saved: (n) => `Saved: ${n}`,
    members: (n) => `Scanned: ${n}`,
    noMembers: 'Nobody yet.',
    added: (n) => `Added: ${n}`,
    known: (n) => `${n} is already on the list.`,
    'not-card': 'This is not an L0ck-ECP contact QR.',
    'bad-card': 'The contact QR is damaged.',
    'team-card': 'This is a team QR. Show My contact on the phone.',
    isBundle: 'This is a group bundle, not a contact.',
    camErr: 'No camera. Allow it in the browser, or paste the links.',
    remove: 'Delete', qr: 'QR', close: 'Close',
    cardHelp: 'The contact as the others will get it (with any changes). A phone reads it as an ordinary contact.',
    s2: 'Teams',
    s2help: 'Each team gets a new random key. A phone joins only the teams it is ticked in. LoRa channel: the radios of the chosen team\'s members move to its private channel.',
    addTeam: 'Add team', teamDefault: (n) => `Team ${n}`,
    all: 'Everyone', lora: 'LoRa channel', loraNone: 'Leave the radios as they are',
    deleteTeam: 'Delete team',
    s3: 'PACE order',
    paceOn: 'Give everyone the same channel order',
    layers: ['SimpleX', 'Bramble (Tor / Wi-Fi / BT)', 'LoRa', 'SMS'],
    s4: 'Group bundle',
    s4warn: 'The bundle carries the team keys. Show it only at the base, in person. Once every phone is set up, press Erase all.',
    make: 'Make the bundle',
    part: (i, n) => `QR ${i} of ${n}`,
    auto: 'Cycle by itself (3 s)',
    size: (b, n) => `${b} B in ${n} QR codes. After any change above, make the bundle again.`,
    needMember: 'Scan at least one phone.',
    needName: 'Every team needs a name (at most 40 B).',
    needTeamMember: (t) => `Team "${t}" has no members.`,
    wipeAsk: 'Erase every scanned contact, team and key from this page?',
    author: 'author',
    stMembers: (n) => (n === 1 ? '1 phone' : n ? `${n} phones` : 'nobody'),
    stTeams: (n) => (n === 1 ? '1 team' : n ? `${n} teams` : 'no teams'),
    stPace: (on) => (on ? 'will be set' : 'unchanged'),
    stBundle: (n) => (n ? `${n} QR ready` : 'not made'),
  },
};

const $ = (id) => document.getElementById(id);
let lang = (navigator.language || '').startsWith('cs') ? 'cs' : 'en';
const t = (k, ...a) => (typeof T[lang][k] === 'function' ? T[lang][k](...a) : T[lang][k]);

const state = {
  members: [], // {bytes, name, key, phone}
  teams: [], // {name, key: Uint8Array(32), members: Set(member key)}
  lora: -1,
  paceOn: false,
  pace: [0, 1, 2, 3],
  parts: null,
  shown: 0,
};

// --- rendering ---

function el(tag, props = {}, ...children) {
  const e = document.createElement(tag);
  Object.assign(e, props);
  for (const c of children) e.append(c);
  return e;
}

function renderTexts() {
  document.documentElement.lang = lang;
  for (const b of document.querySelectorAll('[data-lang]')) b.setAttribute('aria-pressed', b.dataset.lang === lang);
  for (const e of document.querySelectorAll('[data-t]')) e.textContent = t(e.dataset.t);
  for (const e of document.querySelectorAll('[data-tp]')) e.placeholder = t(e.dataset.tp);
  $('cam').textContent = stream ? t('camStop') : t('camStart');
}

/** Edit, QR and Delete for one member of the list. */
function actions(i) {
  const m = state.members[i];
  const edit = el('button', { className: 'small', textContent: t('edit') });
  edit.onclick = () => openCard(m, i);
  const qr = el('button', { className: 'small', textContent: t('qr') });
  qr.onclick = () => showCard(m);
  const rm = el('button', { className: 'small danger', textContent: t('remove') });
  rm.onclick = () => {
    state.members.splice(i, 1);
    for (const team of state.teams) team.members.delete(m.key);
    if (scan.mode === 'edit' && scan.index === i) setScan(idle());
    changed();
  };
  return el('span', { className: 'acts' }, edit, qr, rm);
}

function showCard(m) {
  $('cardTitle').textContent = m.phone ? `${m.name} · ${m.phone}` : m.name;
  drawQr($('cardQr'), 'l0ck://c/' + EcpBundle.b64urlEncode(m.bytes), 6);
  $('cardModal').hidden = false;
  $('cardClose').focus();
}

function renderMembers() {
  $('membersTitle').textContent = t('members', state.members.length);
  const ul = $('members');
  ul.replaceChildren();
  if (!state.members.length) ul.append(el('li', { className: 'meta', textContent: t('noMembers') }));
  state.members.forEach((m, i) => {
    ul.append(el('li', {},
      el('span', { className: 'dot' }),
      el('span', { className: 'meta', textContent: String(i + 1).padStart(2, '0') }),
      el('span', { className: 'name', textContent: m.name }),
      el('span', { className: 'meta', textContent: (m.phone ? m.phone + ' · ' : '') + m.key.slice(0, 8) }),
      actions(i)));
  });
}

function renderTeams() {
  const box = $('teams');
  box.replaceChildren();
  state.teams.forEach((team, ti) => {
    const name = el('input', { type: 'text', value: team.name, maxLength: 40 });
    name.oninput = () => { team.name = name.value; invalidate(); };
    const del = el('button', { className: 'small danger', textContent: t('deleteTeam') });
    del.onclick = () => {
      state.teams.splice(ti, 1);
      if (state.lora === ti) state.lora = -1;
      else if (state.lora > ti) state.lora--;
      changed();
    };
    const lora = el('input', { type: 'radio', name: 'lora', checked: state.lora === ti });
    lora.onchange = () => { state.lora = ti; invalidate(); };
    const all = el('input', { type: 'checkbox',
      checked: state.members.length > 0 && state.members.every((m) => team.members.has(m.key)) });
    all.onchange = () => {
      for (const m of state.members) all.checked ? team.members.add(m.key) : team.members.delete(m.key);
      changed();
    };
    const people = el('div');
    for (const m of state.members) {
      const c = el('input', { type: 'checkbox', checked: team.members.has(m.key) });
      c.onchange = () => { c.checked ? team.members.add(m.key) : team.members.delete(m.key); changed(); };
      people.append(el('label', {}, c, m.name));
    }
    box.append(el('div', { className: 'team' },
      el('div', { className: 'head' }, name, el('label', {}, lora, t('lora')), del),
      el('label', {}, all, el('b', { textContent: t('all') })),
      people));
  });
  $('loraNone').checked = state.lora === -1;
}

function renderPace() {
  $('paceOn').checked = state.paceOn;
  const ul = $('pace');
  ul.replaceChildren();
  state.pace.forEach((layer, i) => {
    const up = el('button', { className: 'small', textContent: '▲', disabled: !state.paceOn || i === 0 });
    const down = el('button', { className: 'small', textContent: '▼', disabled: !state.paceOn || i === 3 });
    const move = (d) => {
      [state.pace[i], state.pace[i + d]] = [state.pace[i + d], state.pace[i]];
      changed();
    };
    up.onclick = () => move(-1);
    down.onclick = () => move(1);
    ul.append(el('li', { style: state.paceOn ? '' : 'opacity:.5' },
      el('span', { className: 'n', textContent: 'PACE'[i] }),
      el('span', { style: 'flex:1', textContent: t('layers')[layer] }), up, down));
  });
}

/** The step strip under the header: a line per step, green when done, orange when ready. */
function renderSteps() {
  const steps = [
    [t('stMembers', state.members.length), state.members.length > 0],
    [t('stTeams', state.teams.length), state.teams.length > 0],
    [t('stPace', state.paceOn), state.paceOn],
    [t('stBundle', state.parts ? state.parts.length : 0), !!state.parts],
  ];
  steps.forEach(([text, done], i) => {
    const a = $(`st${i + 1}`);
    a.querySelector('.st').textContent = text;
    a.className = i === 3 && done ? 'ready' : done ? 'done' : '';
  });
}

function render() {
  renderTexts();
  renderScan();
  renderSteps();
  renderMembers();
  renderTeams();
  renderPace();
  renderBundle();
}

/** Anything changed: the bundle on screen no longer matches. */
function invalidate() {
  state.parts = null;
  setAuto(false);
  renderBundle();
}

function changed() {
  invalidate();
  render();
}

// --- members: camera and pasted links ---
// The camera only reads: a card read (or pasted) waits beside it, its name and number can be
// corrected, and it joins the list on Add. Again goes back to scanning.

let stream = null, scanTimer = null, lastCode = '', lastAt = 0;
const scan = { mode: 'off', card: null, index: -1, msg: '' };
let audio = null;

/** A short tone: high for a card read, low for a refused one. */
function beep(ok) {
  try {
    audio = audio || new AudioContext();
    const o = audio.createOscillator(), g = audio.createGain(), now = audio.currentTime;
    o.type = 'square';
    o.frequency.setValueAtTime(ok ? 1320 : 220, now);
    if (ok) o.frequency.setValueAtTime(1760, now + 0.09);
    g.gain.setValueAtTime(0.08, now);
    g.gain.exponentialRampToValueAtTime(0.0001, now + (ok ? 0.22 : 0.35));
    o.connect(g).connect(audio.destination);
    o.start(now);
    o.stop(now + 0.4);
  } catch (_) {
    // no sound: the panel still shows it
  }
}

function idle() {
  return stream ? 'reading' : 'off';
}

function renderScan() {
  const m = scan.mode;
  const look = { off: 'off', reading: 'reading', found: 'found', edit: 'found', known: 'warn', error: 'warn' }[m];
  $('status').className = `status ${look}`;
  $('camBox').classList.toggle('on', !!stream);
  $('camBox').classList.toggle('found', m === 'found' || m === 'edit');
  $('stateText').textContent = t({ off: 'stOff', reading: 'stReading', found: 'stFound', edit: 'stEdit',
    known: 'stKnown', error: 'stError' }[m]);
  $('stateMsg').textContent = scan.msg || { off: t('offMsg'), reading: t('readingMsg'),
    found: t('foundMsg'), edit: '' }[m] || '';
  const card = m === 'found' || m === 'edit';
  $('confirm').hidden = !card;
  $('accept').hidden = !card;
  $('accept').textContent = m === 'edit' ? t('save') : t('accept');
  $('retry').hidden = m === 'off' || m === 'reading';
  if (card) $('cKey').textContent = `ECP ${scan.card.key.slice(0, 16)}…`;
}

function setScan(mode, card = null, msg = '', index = -1) {
  Object.assign(scan, { mode, card, msg, index });
  $('cErr').textContent = '';
  if (card) {
    $('cName').value = card.name;
    $('cPhone').value = card.phone || '';
  }
  renderScan();
  if (mode === 'found' || mode === 'edit') $('cName').focus();
}

/** A scanned or pasted text: shown beside the camera, not added yet. */
function loadCard(text) {
  const s = String(text).trim();
  if (!s) return;
  if (s.startsWith('l0ck://g/')) {
    beep(false);
    return setScan('error', null, t('isBundle'));
  }
  let card;
  try {
    card = EcpBundle.parseCard(s);
  } catch (e) {
    beep(false);
    return setScan('error', null, t(e.message) || e.message);
  }
  beep(true);
  if (state.members.some((m) => m.key === card.key)) return setScan('known', null, t('known', card.name));
  setScan('found', card);
}

/** A member from the list back in the panel, to correct the name or number. */
function openCard(card, index) {
  setScan('edit', card, '', index);
}

function accept() {
  let card;
  try {
    card = EcpBundle.withNameAndPhone(scan.card, $('cName').value, $('cPhone').value);
  } catch (e) {
    $('cErr').textContent = t(e.message === 'name' ? 'nameBad' : 'phoneBad');
    return;
  }
  let msg;
  if (scan.mode === 'edit') {
    state.members[scan.index] = card; // same key: team ticks stay
    msg = t('saved', card.name);
  } else {
    if (state.members.length >= 250 || state.members.some((m) => m.key === card.key)) return setScan(idle());
    state.members.push(card);
    msg = t('added', card.name);
  }
  changed();
  setScan(idle(), null, msg);
}

function again() {
  lastCode = ''; // the same QR may be read again
  setScan(idle());
}

async function startCamera(deviceId) {
  try {
    stream = await navigator.mediaDevices.getUserMedia({
      video: deviceId ? { deviceId: { exact: deviceId } } : { facingMode: 'environment', width: { ideal: 1280 } },
      audio: false,
    });
  } catch (_) {
    stream = null;
    setScan('error', null, t('camErr'));
    renderTexts();
    return;
  }
  const video = $('video');
  video.srcObject = stream;
  await video.play();
  const cams = (await navigator.mediaDevices.enumerateDevices()).filter((d) => d.kind === 'videoinput');
  const sel = $('cams');
  sel.replaceChildren(...cams.map((d, i) => el('option', { value: d.deviceId, textContent: d.label || `Camera ${i + 1}` })));
  sel.value = stream.getVideoTracks()[0].getSettings().deviceId || '';
  sel.hidden = cams.length < 2;
  scanTimer = setInterval(scanFrame, 200);
  if (scan.mode === 'off' || scan.mode === 'error') setScan('reading');
  renderTexts();
}

function stopCamera() {
  clearInterval(scanTimer);
  scanTimer = null;
  if (stream) for (const tr of stream.getTracks()) tr.stop();
  stream = null;
  $('video').srcObject = null;
  $('cams').hidden = true;
  if (scan.mode === 'reading') setScan('off');
  else renderScan();
  renderTexts();
}

function scanFrame() {
  const video = $('video');
  if (scan.mode !== 'reading' || !video.videoWidth) return; // a card waits for Add or Again
  const scale = Math.min(1, 960 / video.videoWidth);
  const w = Math.round(video.videoWidth * scale), h = Math.round(video.videoHeight * scale);
  const c = $('frame');
  c.width = w;
  c.height = h;
  const g = c.getContext('2d', { willReadFrequently: true });
  g.drawImage(video, 0, 0, w, h);
  const code = jsQR(g.getImageData(0, 0, w, h).data, w, h, { inversionAttempts: 'dontInvert' });
  if (!code || !code.data) return;
  const now = Date.now();
  if (code.data === lastCode && now - lastAt < 4000) return; // the same phone still in view
  lastCode = code.data;
  lastAt = now;
  loadCard(code.data);
}

// --- the bundle ---

let autoTimer = null;

function setAuto(on) {
  $('auto').checked = on;
  clearInterval(autoTimer);
  autoTimer = on ? setInterval(() => show(state.shown + 1), 3000) : null;
}

function makeBundle() {
  $('makeErr').textContent = '';
  if (!state.members.length) return ($('makeErr').textContent = t('needMember'));
  const index = new Map(state.members.map((m, i) => [m.key, i]));
  for (const team of state.teams) {
    const n = new TextEncoder().encode(team.name.trim()).length;
    if (n < 1 || n > EcpBundle.MAX_TEAM_NAME) return ($('makeErr').textContent = t('needName'));
    if (!team.members.size) return ($('makeErr').textContent = t('needTeamMember', team.name));
  }
  const bytes = EcpBundle.encodeBundle({
    members: state.members,
    teams: state.teams.map((team) => ({
      name: team.name.trim(),
      key: team.key,
      members: [...team.members].map((k) => index.get(k)).sort((a, b) => a - b),
    })),
    loraTeam: state.lora >= 0 ? state.lora : null,
    pace: state.paceOn ? state.pace : null,
  });
  state.parts = EcpBundle.qrParts(bytes, EcpBundle.hex(EcpBundle.random(4)));
  state.size = bytes.length;
  show(0);
}

/** Draws [text] as a QR code on [canvas], with the quiet zone. */
function drawQr(canvas, text, cell = 8) {
  const qr = qrcode(0, 'M');
  qr.addData(text);
  qr.make();
  const n = qr.getModuleCount(), margin = 4;
  canvas.width = canvas.height = (n + 2 * margin) * cell;
  const g = canvas.getContext('2d');
  g.fillStyle = '#fff';
  g.fillRect(0, 0, canvas.width, canvas.height);
  g.fillStyle = '#000';
  for (let r = 0; r < n; r++) {
    for (let col = 0; col < n; col++) {
      if (qr.isDark(r, col)) g.fillRect((col + margin) * cell, (r + margin) * cell, cell, cell);
    }
  }
}

function show(i) {
  const parts = state.parts;
  if (!parts) return;
  state.shown = ((i % parts.length) + parts.length) % parts.length;
  drawQr($('qrc'), parts[state.shown]);
  renderBundle();
}

function renderBundle() {
  renderSteps();
  const parts = state.parts;
  $('show').hidden = !parts;
  if (!parts) return;
  $('part').textContent = t('part', state.shown + 1, parts.length);
  $('sizeInfo').textContent = t('size', state.size, parts.length);
  $('prev').disabled = $('next').disabled = parts.length < 2;
}

// --- wiring ---

for (const b of document.querySelectorAll('[data-lang]')) {
  b.onclick = () => { lang = b.dataset.lang; render(); };
}
$('cam').onclick = () => (stream ? stopCamera() : startCamera());
$('cams').onchange = () => { stopCamera(); startCamera($('cams').value); };
$('addPaste').onclick = () => { loadCard($('paste').value); $('paste').value = ''; };
$('accept').onclick = accept;
$('retry').onclick = again;
for (const f of ['cName', 'cPhone']) $(f).onkeydown = (e) => { if (e.key === 'Enter') accept(); };
$('paste').onkeydown = (e) => { if (e.key === 'Enter') $('addPaste').click(); };
$('addTeam').onclick = () => {
  state.teams.push({ name: t('teamDefault', state.teams.length + 1), key: EcpBundle.random(32),
    members: new Set(state.members.map((m) => m.key)) });
  changed();
};
$('loraNone').onchange = () => { state.lora = -1; invalidate(); };
$('paceOn').onchange = () => { state.paceOn = $('paceOn').checked; changed(); };
$('make').onclick = makeBundle;
$('prev').onclick = () => { setAuto(false); show(state.shown - 1); };
$('next').onclick = () => { setAuto(false); show(state.shown + 1); };
$('auto').onchange = () => setAuto($('auto').checked);
$('cardClose').onclick = () => { $('cardModal').hidden = true; };
$('cardModal').onclick = (e) => { if (e.target === $('cardModal')) $('cardModal').hidden = true; };
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') $('cardModal').hidden = true;
  if (!state.parts || e.target.tagName === 'INPUT') return;
  if (e.key === 'ArrowRight') $('next').click();
  if (e.key === 'ArrowLeft') $('prev').click();
});
$('wipe').onclick = () => {
  if (!confirm(t('wipeAsk'))) return;
  stopCamera();
  for (const team of state.teams) team.key.fill(0);
  location.reload();
};
render();
