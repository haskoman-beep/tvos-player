import Foundation

// plan_nuvio_konto T1b: the script that seals the Nuvio sign-in on the phone. What it protects and what it does not
// is written at the top of PhoneSeal.swift.

/// The phone page's sealing script: ChaCha20-Poly1305 AEAD as in RFC 8439, written from the RFC in plain JavaScript
/// (`crypto.subtle` exists only on secure origins, the page is plain HTTP). It defines `PlayerSeal` and, when a document
/// is there, binds the form `nuvioform`.
///
/// Test contract: `tools/phone_seal_test.mjs` (Node) cuts the text between the line ending in `= #"""` and the line
/// `"""#` out of this file and checks the RFC 8439 vectors on exactly those bytes; `phoneSealScriptIsTheSwiftConstant`
/// (Swift) checks that this constant equals the same cut. The page embeds the constant unchanged in its own `<script>`.
/// Keep the closing delimiter in column 0 (no indentation is stripped) and never write a backslash followed by `#`.
public enum PhoneSealScript {
    public static let source = #"""
(function (g) {
'use strict';
// ChaCha20-Poly1305 AEAD, RFC 8439 sections 2.3, 2.4, 2.5, 2.8. Protects the sign-in against a listener on the
// Wi-Fi only; anyone who can change traffic can change this script.
var SIGMA = [0x61707865, 0x3320646e, 0x79622d32, 0x6b206574];
var LABEL = 'player-nuvio-login-v1';
function u32le(b, i) { return (b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)) >>> 0; }
function rotl(v, n) { return ((v << n) | (v >>> (32 - n))) >>> 0; }
function quarter(x, a, b, c, d) {
  x[a] = (x[a] + x[b]) >>> 0; x[d] = rotl(x[d] ^ x[a], 16);
  x[c] = (x[c] + x[d]) >>> 0; x[b] = rotl(x[b] ^ x[c], 12);
  x[a] = (x[a] + x[b]) >>> 0; x[d] = rotl(x[d] ^ x[a], 8);
  x[c] = (x[c] + x[d]) >>> 0; x[b] = rotl(x[b] ^ x[c], 7);
}
function chachaBlock(key, counter, nonce) {
  if (key.length !== 32 || nonce.length !== 12 || counter < 0 || counter > 0xffffffff) throw new Error('chacha20 input');
  var s = new Array(16), i;
  for (i = 0; i < 4; i++) s[i] = SIGMA[i];
  for (i = 0; i < 8; i++) s[4 + i] = u32le(key, 4 * i);
  s[12] = counter >>> 0;
  for (i = 0; i < 3; i++) s[13 + i] = u32le(nonce, 4 * i);
  var x = s.slice();
  for (i = 0; i < 10; i++) {
    quarter(x, 0, 4, 8, 12); quarter(x, 1, 5, 9, 13); quarter(x, 2, 6, 10, 14); quarter(x, 3, 7, 11, 15);
    quarter(x, 0, 5, 10, 15); quarter(x, 1, 6, 11, 12); quarter(x, 2, 7, 8, 13); quarter(x, 3, 4, 9, 14);
  }
  var out = new Uint8Array(64);
  for (i = 0; i < 16; i++) {
    var v = (x[i] + s[i]) >>> 0;
    out[4 * i] = v & 255; out[4 * i + 1] = (v >>> 8) & 255; out[4 * i + 2] = (v >>> 16) & 255; out[4 * i + 3] = v >>> 24;
  }
  return out;
}
function chachaXor(key, counter, nonce, data) {
  var out = new Uint8Array(data.length);
  for (var off = 0, j = 0; off < data.length; off += 64, j++) {
    var ks = chachaBlock(key, counter + j, nonce);
    for (var i = 0; i < 64 && off + i < data.length; i++) out[off + i] = data[off + i] ^ ks[i];
  }
  return out;
}
function leNumber(b, from, to) {
  var n = BigInt(0);
  for (var i = to - 1; i >= from; i--) n = (n << BigInt(8)) | BigInt(b[i]);
  return n;
}
function poly1305(key, msg) {
  if (key.length !== 32) throw new Error('poly1305 key');
  var p = (BigInt(1) << BigInt(130)) - BigInt(5);
  var r = leNumber(key, 0, 16) & BigInt('0x0ffffffc0ffffffc0ffffffc0fffffff');
  var s = leNumber(key, 16, 32), acc = BigInt(0), i;
  for (i = 0; i < msg.length; i += 16) {
    var end = Math.min(i + 16, msg.length);
    acc = ((acc + (leNumber(msg, i, end) | (BigInt(1) << BigInt(8 * (end - i))))) * r) % p;
  }
  acc = (acc + s) & ((BigInt(1) << BigInt(128)) - BigInt(1));
  var tag = new Uint8Array(16);
  for (i = 0; i < 16; i++) { tag[i] = Number(acc & BigInt(255)); acc = acc >> BigInt(8); }
  return tag;
}
function pad16(n) { return (16 - (n % 16)) % 16; }
function le64(n) {
  var b = new Uint8Array(8);
  for (var i = 0; i < 8; i++) { b[i] = n % 256; n = Math.floor(n / 256); }
  return b;
}
// Returns ciphertext || tag (16 bytes).
function seal(key, nonce, plaintext, aad) {
  var otk = chachaBlock(key, 0, nonce).subarray(0, 32);
  var ct = chachaXor(key, 1, nonce, plaintext);
  var m = new Uint8Array(aad.length + pad16(aad.length) + ct.length + pad16(ct.length) + 16), o = 0;
  m.set(aad, o); o += aad.length + pad16(aad.length);
  m.set(ct, o); o += ct.length + pad16(ct.length);
  m.set(le64(aad.length), o); m.set(le64(ct.length), o + 8);
  var out = new Uint8Array(ct.length + 16);
  out.set(ct); out.set(poly1305(otk, m), ct.length);
  return out;
}
function b64u(bytes) {
  var s = '';
  for (var i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return g.btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function unb64u(t) {
  if (typeof t !== 'string' || !/^[A-Za-z0-9_-]*$/.test(t) || t.length % 4 === 1) return null;
  var s = t.replace(/-/g, '+').replace(/_/g, '/'), bin;
  while (s.length % 4) s += '=';
  try { bin = g.atob(s); } catch (e) { return null; }
  var out = new Uint8Array(bin.length);
  for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
function utf8(s) {
  if (typeof g.TextEncoder !== 'function') throw new Error('no TextEncoder');
  return new g.TextEncoder().encode(s);
}
// The field "sealed": base64url(nonce || ciphertext || tag) of the UTF-8 JSON {"email":…,"password":…}, AAD = LABEL.
function sealLogin(key, nonce, email, password) {
  if (typeof BigInt !== 'function' || key.length !== 32 || nonce.length !== 12) throw new Error('seal input');
  var box = seal(key, nonce, utf8(JSON.stringify({ email: String(email), password: String(password) })), utf8(LABEL));
  var env = new Uint8Array(12 + box.length);
  env.set(nonce); env.set(box, 12);
  return b64u(env);
}
g.PlayerSeal = { chachaBlock: chachaBlock, chachaXor: chachaXor, poly1305: poly1305, seal: seal, b64u: b64u, unb64u: unb64u,
                 sealLogin: sealLogin, label: LABEL };

var doc = g.document, loc = g.location;
if (!doc || !loc) return;
// The QR address carries the page key in the fragment ("#nuvio&k=…" or "#k=…"); browsers never send a fragment and
// keep it across the session's 303. Here it moves to sessionStorage and out of the visible address.
var STORE = 'player_nuvio_k', mem = null;
function storedKey() {
  var k = mem;
  if (!k) { try { k = g.sessionStorage.getItem(STORE); } catch (e) { k = null; } }
  var b = k ? unb64u(k) : null;
  return b && b.length === 32 ? b : null;
}
(function () {
  var h = loc.hash ? String(loc.hash).slice(1) : '';
  if (!h) return;
  var parts = h.split('&'), keep = [], k = null;
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].indexOf('k=') === 0) k = parts[i].slice(2); else if (parts[i]) keep.push(parts[i]);
  }
  if (k === null) return;
  mem = k;
  try { g.sessionStorage.setItem(STORE, k); } catch (e) {}
  var anchor = keep.join('&');
  try { g.history.replaceState(g.history.state, '', loc.pathname + loc.search + (anchor ? '#' + anchor : '')); } catch (e) {}
  var target = anchor ? doc.getElementById(anchor) : null;
  if (target && target.scrollIntoView) target.scrollIntoView();
})();
var form = doc.getElementById('nuvioform');
if (!form) return;
var email = doc.getElementById('nv_email'), password = doc.getElementById('nv_password'), fail = doc.getElementById('nv_fail');
function refuse() { if (fail) fail.hidden = false; }
if (!storedKey()) refuse();
form.addEventListener('submit', function (e) {
  e.preventDefault();
  var envelope = null;
  try {
    var key = storedKey(), c = g.crypto;
    if (key && email && password && c && typeof c.getRandomValues === 'function') {
      var nonce = new Uint8Array(12);
      c.getRandomValues(nonce);
      envelope = sealLogin(key, nonce, email.value, password.value);
    }
  } catch (x) { envelope = null; }
  if (!envelope) { refuse(); return; }
  var old = form.querySelector('input[name=sealed]');
  if (old) form.removeChild(old);
  var field = doc.createElement('input');
  field.type = 'hidden'; field.name = 'sealed'; field.value = envelope;
  form.appendChild(field);
  password.value = '';
  if (fail) fail.hidden = true;
  form.submit();
});
})(typeof globalThis !== 'undefined' ? globalThis : (typeof window !== 'undefined' ? window : this));
"""#
}
