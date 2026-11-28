// Checks the phone page's sealing script (PlayerCore `PhoneSealScript.source`) under Node:
//   node tools/phone_seal_test.mjs                 run all checks, compare the committed fixture
//   node tools/phone_seal_test.mjs --write-fixture also (re)write the fixture for the CryptoKit cross-check
//
// The script is not copied: it is cut out of the Swift file with the same rule the Swift test
// `phoneSealScriptIsTheSwiftConstant` uses (the text between the line ending in `= #"""` and the line `"""#`),
// so the bytes checked here are the bytes the page serves.
//
// Checks: RFC 8439 test vectors (2.3.2 ChaCha20 block, 2.4.2 ChaCha20 encryption, 2.5.2 Poly1305, 2.6.2 Poly1305
// key generation, 2.8.2 AEAD), a differential run against Node's own OpenSSL ChaCha20-Poly1305 over random sizes,
// the login envelope (open with OpenSSL), and the page binding in a small fake DOM.

import { readFileSync, writeFileSync } from 'node:fs';
import { createCipheriv, createDecipheriv, randomBytes, webcrypto } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import vm from 'node:vm';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const swiftFile = path.join(root, 'Packages/PlayerCore/Sources/PlayerCore/Phone/PhoneSealScript.swift');
const fixtureFile = path.join(root, 'Packages/PlayerCore/Tests/PlayerCoreTests/Fixtures/phone-seal-vector.json');

let failures = 0, passes = 0;
function check(name, ok, detail) {
  if (ok) { passes++; console.log('ok   ' + name); } else { failures++; console.log('FAIL ' + name + (detail ? ' :: ' + detail : '')); }
}
const hex = (b) => Buffer.from(b).toString('hex');
const unhex = (s) => new Uint8Array(Buffer.from(s.replace(/[^0-9a-f]/gi, ''), 'hex'));
const range = (a, n) => new Uint8Array(Array.from({ length: n }, (_, i) => (a + i) & 255));

// --- extract the script --------------------------------------------------------------------------------------------
export function extract(swiftText) {
  const lines = swiftText.split('\n');
  const start = lines.findIndex((l) => l.endsWith('public static let source = #"""'));
  const end = lines.findIndex((l, i) => i > start && l === '"""#');
  if (start < 0 || end < 0) throw new Error('script markers not found');
  return lines.slice(start + 1, end).join('\n');
}
const source = extract(readFileSync(swiftFile, 'utf8'));
check('script: no Swift raw-string escape (\\#), no </script and no <!--', !source.includes('\\#') && !/<\/script/i.test(source) && !source.includes('<!--'));

function load(extra = {}) {
  const ctx = vm.createContext({ TextEncoder, btoa, atob, ...extra });
  vm.runInContext(source, ctx, { filename: 'PhoneSealScript.source' });
  return ctx;
}
const lib = load().PlayerSeal;
check('script defines PlayerSeal without a document', !!lib && typeof lib.seal === 'function');

// --- RFC 8439 vectors ------------------------------------------------------------------------------------------------
{ // 2.3.2
  const key = range(0, 32), nonce = unhex('000000090000004a00000000');
  const want = '10f1e7e4d13b5915500fdd1fa32071c4c7d1f4c733c068030422aa9ac3d46c4e' +
               'd2826446079faa0914c2d705d98b02a2b5129cd1de164eb9cbd083e8a2503c4e';
  check('RFC 8439 2.3.2 ChaCha20 block', hex(lib.chachaBlock(key, 1, nonce)) === want, hex(lib.chachaBlock(key, 1, nonce)));
}
const sunscreen = new TextEncoder().encode("Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.");
{ // 2.4.2
  const key = range(0, 32), nonce = unhex('000000000000004a00000000');
  const want = '6e2e359a2568f98041ba0728dd0d6981e97e7aec1d4360c20a27afccfd9fae0b' +
               'f91b65c5524733ab8f593dabcd62b3571639d624e65152ab8f530c359f0861d8' +
               '07ca0dbf500d6a6156a38e088a22b65e52bc514d16ccf806818ce91ab7793736' +
               '5af90bbf74a35be6b40b8eedf2785e42874d';
  const got = hex(lib.chachaXor(key, 1, nonce, sunscreen));
  check('RFC 8439 2.4.2 ChaCha20 encryption', got === want, got);
}
{ // 2.5.2
  const key = unhex('85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b');
  const msg = new TextEncoder().encode('Cryptographic Forum Research Group');
  const got = hex(lib.poly1305(key, msg));
  check('RFC 8439 2.5.2 Poly1305', got === 'a8061dc1305136c6c22b8baf0c0127a9', got);
}
{ // 2.6.2
  const key = range(0x80, 32), nonce = unhex('000000000001020304050607');
  const got = hex(lib.chachaBlock(key, 0, nonce).subarray(0, 32));
  check('RFC 8439 2.6.2 Poly1305 key generation', got === '8ad5a08b905f81cc815040274ab29471a833b637e3fd0da508dbb8e2fdd1a646', got);
}
{ // 2.8.2
  const key = range(0x80, 32), nonce = unhex('070000004041424344454647'), aad = unhex('50515253c0c1c2c3c4c5c6c7');
  const wantCt = 'd31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d6' +
                 '3dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b36' +
                 '92ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc' +
                 '3ff4def08e4b7a9de576d26586cec64b6116';
  const got = hex(lib.seal(key, nonce, sunscreen, aad));
  check('RFC 8439 2.8.2 AEAD ciphertext and tag', got === wantCt + '1ae10b594f09e26a7e902ecbd0600691', got);
}

// --- differential run against OpenSSL -------------------------------------------------------------------------------
function opensslSeal(key, nonce, pt, aad) {
  const c = createCipheriv('chacha20-poly1305', key, nonce, { authTagLength: 16 });
  c.setAAD(aad, { plaintextLength: pt.length });
  return Buffer.concat([c.update(pt), c.final(), c.getAuthTag()]);
}
function opensslOpen(key, nonce, box, aad) {
  const d = createDecipheriv('chacha20-poly1305', key, nonce, { authTagLength: 16 });
  d.setAAD(aad, { plaintextLength: box.length - 16 });
  d.setAuthTag(box.subarray(box.length - 16));
  return Buffer.concat([d.update(box.subarray(0, box.length - 16)), d.final()]);
}
{
  let bad = null;
  const sizes = [0, 1, 15, 16, 17, 31, 32, 33, 63, 64, 65, 127, 128, 129, 255, 256, 257, 1000, 4097];
  for (let round = 0; round < 400 && !bad; round++) {
    const n = round < sizes.length ? sizes[round] : (randomBytes(2).readUInt16LE() % 700);
    const a = round < sizes.length ? sizes[(round * 7) % sizes.length] % 300 : (randomBytes(1)[0] % 70);
    const key = randomBytes(32), nonce = randomBytes(12), pt = randomBytes(n), aad = randomBytes(a);
    const mine = Buffer.from(lib.seal(new Uint8Array(key), new Uint8Array(nonce), new Uint8Array(pt), new Uint8Array(aad)));
    if (!mine.equals(opensslSeal(key, nonce, pt, aad))) bad = `pt ${n} aad ${a}`;
  }
  check('AEAD equals OpenSSL chacha20-poly1305 (400 random sizes, partial blocks)', bad === null, bad);
}
{ // keystream of later blocks equals OpenSSL's raw chacha20 (16-byte IV = little-endian counter || nonce)
  const key = randomBytes(32), nonce = randomBytes(12), zeros = new Uint8Array(64 * 5);
  const iv = Buffer.concat([Buffer.from([7, 0, 0, 0]), nonce]);
  const c = createCipheriv('chacha20', key, iv);
  const want = Buffer.concat([c.update(zeros), c.final()]);
  check('ChaCha20 keystream from counter 7 equals OpenSSL', hex(lib.chachaXor(new Uint8Array(key), 7, new Uint8Array(nonce), zeros)) === hex(want));
}
{ // base64url
  const b = randomBytes(61);
  const t = lib.b64u(new Uint8Array(b));
  check('base64url: no padding, url alphabet, round trip', /^[A-Za-z0-9_-]+$/.test(t) && Buffer.from(lib.unb64u(t)).equals(b) &&
        t === b.toString('base64url'));
  check('base64url: refuses other characters', lib.unb64u('ab+c') === null && lib.unb64u('abc=') === null && lib.unb64u('a') === null);
}

// --- the login envelope ---------------------------------------------------------------------------------------------
const fixtureKey = range(0x20, 32), fixtureNonce = unhex('a0a1a2a3a4a5a6a7a8a9aaab');
const fixtureMail = 'user@example.org', fixturePass = 'FAKE-PASS-0011 äö€ "&=+\\';
{
  const env = lib.sealLogin(fixtureKey, fixtureNonce, fixtureMail, fixturePass);
  const raw = Buffer.from(env, 'base64url');
  check('envelope = nonce || ciphertext || tag', raw.subarray(0, 12).equals(Buffer.from(fixtureNonce)));
  const pt = opensslOpen(Buffer.from(fixtureKey), raw.subarray(0, 12), raw.subarray(12), Buffer.from(lib.label, 'ascii'));
  const json = JSON.parse(pt.toString('utf8'));
  check('envelope opens with OpenSSL, AAD = label, JSON {email,password,pad}',
        lib.label === 'player-nuvio-login-v1' && json.email === fixtureMail && json.password === fixturePass &&
        Object.keys(json).join() === 'email,password,pad' && /^ *$/.test(json.pad));
  check('envelope plaintext is padded to exactly 1024 bytes', pt.length === 1024 && raw.length === 12 + 1024 + 16, String(pt.length));
  let tamperedOpens = false;
  const t = Buffer.from(raw); t[20] ^= 1;
  try { opensslOpen(Buffer.from(fixtureKey), t.subarray(0, 12), t.subarray(12), Buffer.from(lib.label)); tamperedOpens = true; } catch (e) {}
  check('one flipped bit does not open', !tamperedOpens);
  const fixture = {
    comment: 'Made by tools/phone_seal_test.mjs --write-fixture from PhoneSealScript.source (JavaScript ChaCha20-Poly1305). ' +
             'Opened by the CryptoKit test in PhoneSealTests.swift and by the envelope test there.',
    keyHex: hex(fixtureKey), nonceHex: hex(fixtureNonce), aad: lib.label,
    plaintext: pt.toString('utf8'), email: fixtureMail, password: fixturePass,
    sealed: env, ciphertextAndTagHex: hex(raw.subarray(12)),
  };
  const text = JSON.stringify(fixture, null, 2) + '\n';
  if (process.argv.includes('--write-fixture')) { writeFileSync(fixtureFile, text); console.log('wrote ' + path.relative(root, fixtureFile)); }
  let committed = null;
  try { committed = readFileSync(fixtureFile, 'utf8'); } catch (e) {}
  check('committed fixture equals what the script produces now', committed === text);
}

// --- padding: the envelope does not tell the password length --------------------------------------------------------
const swiftInput = readFileSync(path.join(root, 'Packages/PlayerCore/Sources/PlayerCore/Phone/PhoneInput.swift'), 'utf8');
const serverFieldLimit = Number((swiftInput.match(/static let nuvioFieldLimit = (\d+)/) || [])[1]);
check('script field limit equals PhoneInputPage.nuvioFieldLimit (UTF-8 bytes)', lib.fieldLimit === 256 && lib.fieldLimit === serverFieldLimit,
      `${lib.fieldLimit} vs ${serverFieldLimit}`);
function plainOf(env, key = fixtureKey) {
  const raw = Buffer.from(env, 'base64url');
  return opensslOpen(Buffer.from(key), raw.subarray(0, 12), raw.subarray(12), Buffer.from(lib.label));
}
{
  const lengths = [1, 8, 20, 200].map((n) => lib.sealLogin(fixtureKey, fixtureNonce, fixtureMail, 'p'.repeat(n)).length);
  check('envelopes for passwords of 1, 8, 20 and 200 characters have identical length', new Set(lengths).size === 1, lengths.join());
  const mixed = [1, 8, 20, 200].map((n) => lib.sealLogin(fixtureKey, fixtureNonce, 'a@b.example', '€'.repeat(Math.floor(n / 3) || 1)).length);
  check('envelopes for multi-byte passwords have that same length too', new Set([...lengths, ...mixed]).size === 1, mixed.join());
  let allBlocks = true, worst = 0;
  for (const [e, p] of [['', ''], ['a@b', 'p'], ['x'.repeat(256), 'y'.repeat(256)], ['\u0001'.repeat(256), '\u0001'.repeat(256)],
                        ['"'.repeat(256), '\\'.repeat(256)], ['a@b', '\ud800'.repeat(85)]]) {
    const env = lib.sealLogin(fixtureKey, fixtureNonce, e, p), pt = plainOf(env), j = JSON.parse(pt.toString('utf8'));
    if (pt.length % 1024 !== 0 || pt.length < 1024 || j.email !== e || (j.password !== p && !p.startsWith('\ud800'))) allBlocks = false;
    worst = Math.max(worst, env.length);
  }
  check('plaintext is always a multiple of 1024 bytes (at least 1024), fields unchanged', allBlocks);
  // PhoneLimits.maxBody(for: "/nuvio") = 16 KiB; PhoneSeal.maxFieldLength = that minus "sealed=".
  check('largest allowed sign-in (escaped JSON) fits the TV limits', worst + 'sealed='.length <= 16 * 1024 && worst <= 16 * 1024 - 7, String(worst));
  check('largest allowed sign-in pads to 4096 bytes', plainOf(lib.sealLogin(fixtureKey, fixtureNonce, '\u0001'.repeat(256), '\u0001'.repeat(256))).length === 4096);
  check('fieldsTooLong counts UTF-8 bytes after trimming the e-mail',
        !lib.fieldsTooLong('a'.repeat(256), 'p'.repeat(256)) && lib.fieldsTooLong('a'.repeat(257), 'p') && lib.fieldsTooLong('a@b', 'p'.repeat(257)) &&
        !lib.fieldsTooLong('ä'.repeat(128), 'ä'.repeat(128)) && lib.fieldsTooLong('a@b', 'ä'.repeat(129)) &&
        lib.fieldsTooLong('a@b', '\u{1F468}‍\u{1F469}‍\u{1F467}‍\u{1F466}'.repeat(256)) &&
        !lib.fieldsTooLong('  ' + 'a'.repeat(256) + ' \n', 'p'));
}

// --- page binding in a fake DOM -------------------------------------------------------------------------------------
function fakePage({ hash, search = '', storage = new Map(), randomValues = true, keyInStorage, forgetMarker = false }) {
  const replaced = [], scrolled = [], assigned = [];
  const el = (id, extra = {}) => ({ id, value: '', hidden: true, scrollIntoView() { scrolled.push(id); }, ...extra });
  const form = el('nuvioform', {
    children: [], listeners: {}, posted: null,
    addEventListener(t, f) { this.listeners[t] = f; },
    querySelector(sel) { return sel === 'input[name=sealed]' ? (this.children.find((c) => c.name === 'sealed') || null) : null; },
    appendChild(c) { c.parentNode = this; this.children.push(c); },
    removeChild(c) { this.children = this.children.filter((x) => x !== c); },
    submit() { this.posted = this.children.filter((c) => c.name).map((c) => [c.name, c.value]); },
  });
  const els = forgetMarker ? { nv_forget: el('nv_forget') }
    : { nuvioform: form, nv_email: el('nv_email'), nv_password: el('nv_password'), nv_fail: el('nv_fail'), nuvio: el('nuvio') };
  const location = { hash, pathname: '/', search, assign(u) { assigned.push(u); } };
  const document = { getElementById: (id) => els[id] || null, createElement: () => ({}) };
  const history = { state: null, replaceState(s, t, url) { replaced.push(url); const i = url.indexOf('#'); location.hash = i < 0 ? '' : url.slice(i); } };
  if (keyInStorage) storage.set('player_nuvio_k', keyInStorage);
  const sessionStorage = { getItem: (k) => (storage.has(k) ? storage.get(k) : null), setItem: (k, v) => storage.set(k, String(v)),
                           removeItem: (k) => storage.delete(k) };
  const crypto = randomValues ? { getRandomValues: (a) => webcrypto.getRandomValues(a) } : {};
  load({ document, location, history, sessionStorage, crypto });
  const submit = () => { let prevented = false; form.listeners.submit({ preventDefault() { prevented = true; } }); return prevented; };
  return { els, form, replaced, scrolled, storage, location, assigned, submit };
}
const pageKey = randomBytes(32), pageKeyText = pageKey.toString('base64url');
{
  const p = fakePage({ hash: '#nuvio&k=' + pageKeyText });
  check('page: key moves from the address to sessionStorage, anchor stays',
        p.storage.get('player_nuvio_k') === pageKeyText && p.replaced.length === 1 && p.replaced[0] === '/#nuvio' && p.location.hash === '#nuvio');
  check('page: scrolls to the kept anchor', p.scrolled.join() === 'nuvio');
  check('page: no failure note while the key is there', p.els.nv_fail.hidden === true);
  p.els.nv_email.value = 'a@b.example'; p.els.nv_password.value = 'FAKE-PASS-0012 ü';
  const prevented = p.submit();
  const posted = p.form.posted || [];
  check('page: submit posts exactly one field "sealed"', prevented && posted.length === 1 && posted[0][0] === 'sealed', JSON.stringify(posted));
  const raw = Buffer.from(posted[0] ? posted[0][1] : '', 'base64url');
  let json = null;
  try { json = JSON.parse(opensslOpen(pageKey, raw.subarray(0, 12), raw.subarray(12), Buffer.from('player-nuvio-login-v1')).toString('utf8')); } catch (e) {}
  check('page: the sealed field opens with the page key (OpenSSL)', json && json.email === 'a@b.example' && json.password === 'FAKE-PASS-0012 ü');
  check('page: the password field is emptied, the posted text holds no cleartext',
        p.els.nv_password.value === '' && !posted.flat().join().includes('FAKE'));
  p.submit();
  check('page: a second submit sends one field with a fresh nonce', p.form.posted.length === 1 &&
        Buffer.from(p.form.posted[0][1], 'base64url').subarray(0, 12).compare(raw.subarray(0, 12)) !== 0);
  // After a 303 that did not send the sign-in on (here "/?nv=leer#nuvio") the address has no key: the stored one is used.
  const q = fakePage({ hash: '#nuvio', search: '?nv=leer', storage: p.storage });
  q.els.nv_email.value = 'x@y.example'; q.els.nv_password.value = 'p';
  q.submit();
  check('page: later page in the same tab keeps working from sessionStorage, address untouched',
        q.replaced.length === 0 && q.form.posted && q.form.posted.length === 1);
}
{
  const p = fakePage({ hash: '#k=' + pageKeyText });
  check('page: key without a section leaves an address without fragment', p.replaced[0] === '/' && p.scrolled.length === 0);
}
{
  const p = fakePage({ hash: '#nuvio' });
  p.els.nv_email.value = 'a@b.example'; p.els.nv_password.value = 'x';
  const prevented = p.submit();
  check('page: no key -> nothing sent, failure note shown', prevented && p.form.posted === null && p.els.nv_fail.hidden === false);
}
{
  const p = fakePage({ hash: '#nuvio&k=' + pageKeyText, randomValues: false });
  p.els.nv_email.value = 'a@b.example'; p.els.nv_password.value = 'x';
  p.submit();
  check('page: no crypto.getRandomValues -> nothing sent, failure note shown', p.form.posted === null && p.els.nv_fail.hidden === false);
}
{
  const p = fakePage({ hash: '#nuvio&k=' + pageKey.subarray(0, 31).toString('base64url') });
  p.els.nv_email.value = 'a@b.example'; p.els.nv_password.value = 'x';
  p.submit();
  check('page: a key that is not 32 bytes -> nothing sent', p.form.posted === null && p.els.nv_fail.hidden === false);
}

{ // review T1b: the e-mail is sent trimmed; the envelope length does not change with the password
  const p = fakePage({ hash: '#nuvio&k=' + pageKeyText });
  p.els.nv_email.value = '  a@b.example \n'; p.els.nv_password.value = 'x';
  p.submit();
  const a = p.form.posted[0][1];
  p.els.nv_password.value = 'FAKE-PASS-0014 longer password with €';
  p.submit();
  const b = p.form.posted[0][1];
  const j = JSON.parse(plainOf(a, pageKey).toString('utf8'));
  check('page: e-mail sent trimmed, envelopes of different passwords equally long', j.email === 'a@b.example' && a.length === b.length,
        `${a.length} ${b.length}`);
}
{ // review T1b: over-long input is not sealed; the page shows the existing "nv=leer" note
  for (const [mail, pass, label] of [['a@b.example', 'p'.repeat(257), '257-byte password'],
                                     ['a@b.example', '\u{1F468}‍\u{1F469}‍\u{1F467}‍\u{1F466}'.repeat(256), '256 family emoji'],
                                     ['a'.repeat(250) + '@b.example', 'p', '260-byte e-mail']]) {
    const p = fakePage({ hash: '#nuvio&k=' + pageKeyText });
    p.els.nv_email.value = mail; p.els.nv_password.value = pass;
    const prevented = p.submit();
    check('page: ' + label + ' -> nothing sealed or sent, address /?nv=leer#nuvio, password emptied',
          prevented && p.form.posted === null && p.assigned.join() === '/?nv=leer#nuvio' && p.els.nv_password.value === '' &&
          p.els.nv_fail.hidden === true, JSON.stringify(p.assigned));
  }
}
{ // review T1b: once the sign-in went to the TV ("nv=gesendet") the page key is dropped from storage and memory
  const storage = new Map();
  const first = fakePage({ hash: '#nuvio&k=' + pageKeyText, storage });
  check('page: key stored before sending', storage.get('player_nuvio_k') === pageKeyText && first.els.nv_fail.hidden === true);
  const p = fakePage({ hash: '#nuvio', search: '?nv=gesendet', storage });
  check('page: nv=gesendet removes the key from sessionStorage, no failure note on load',
        !storage.has('player_nuvio_k') && p.els.nv_fail.hidden === true);
  p.els.nv_email.value = 'a@b.example'; p.els.nv_password.value = 'x';
  p.submit();
  check('page: after nv=gesendet nothing can be sealed any more', p.form.posted === null && p.els.nv_fail.hidden === false);
  // The same in one page load: key in the address and the note together (memory copy dropped too).
  const s2 = new Map();
  const both = fakePage({ hash: '#nuvio&k=' + pageKeyText, search: '?ok=1&nv=gesendet', storage: s2 });
  both.els.nv_email.value = 'a@b.example'; both.els.nv_password.value = 'x';
  both.submit();
  check('page: key in the address plus nv=gesendet -> address cleaned, nothing stored, nothing sent',
        !s2.has('player_nuvio_k') && both.replaced[0] === '/?ok=1&nv=gesendet#nuvio' && both.form.posted === null);
  // Notes that only look similar keep the key.
  const s3 = new Map([['player_nuvio_k', pageKeyText]]);
  fakePage({ hash: '#nuvio', search: '?nv=gesendetx', storage: s3 });
  fakePage({ hash: '#nuvio', search: '?xnv=gesendet', storage: s3 });
  check('page: other notes keep the key', s3.get('player_nuvio_k') === pageKeyText);
}
{ // review T1b: the 403 page ("Kein Zugang") carries the marker nv_forget: the key goes, also one in an old QR address
  const storage = new Map([['player_nuvio_k', pageKeyText]]);
  fakePage({ hash: '', storage, forgetMarker: true });
  check('page: 403 marker removes a stored key', !storage.has('player_nuvio_k'));
  const s2 = new Map();
  const p = fakePage({ hash: '#nuvio&k=' + pageKeyText, search: '?t=old', storage: s2, forgetMarker: true });
  check('page: 403 marker with a key in the address -> not stored, address cleaned', !s2.has('player_nuvio_k') && p.replaced[0] === '/?t=old#nuvio');
}

console.log(`\n${passes} passed, ${failures} failed`);
process.exit(failures ? 1 : 0);
