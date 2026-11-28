import Foundation
import Testing
@testable import PlayerCore
#if canImport(CryptoKit)
import CryptoKit
#endif

// plan_nuvio_konto T1b: the Nuvio sign-in is sealed on the phone (PhoneSealScript, ChaCha20-Poly1305) and opened on
// the TV through an injected opener (CryptoKit in the app). Linux runs use stand-in openers; the real JavaScript cipher
// is checked under Node by tools/phone_seal_test.mjs, the CryptoKit cross-check below runs only where CryptoKit exists.

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let phone = "192.0.2.10"
let sealTestKey = Data((0..<32).map { UInt8(0x40 + $0) })

private func req(_ s: String) -> HTTPRequest {
    guard case .complete(let r) = HTTPRequest.parse(Data(s.utf8)) else { fatalError("parse") }
    return r
}

private func post(_ path: String, _ body: String) -> HTTPRequest {
    req("POST \(path) HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)")
}

private func head(_ s: String) -> RequestHead {
    guard case .complete(let h) = HTTPRequest.parseHead(Data(s.utf8)) else { fatalError("head") }
    return h
}

/// A session whose QR address was used (sealed posts only arrive after that).
func startedSealSession(key: Data = sealTestKey) -> PhoneSession {
    var s = PhoneSession(token: "tok", now: t0, pageKey: key)
    _ = s.authorize(queryToken: "tok", cookie: nil, peer: phone, now: t0)
    return s
}

/// Stand-in envelope for Linux: nonce || plaintext || 16 zero bytes. `toyOpen` returns the middle part; it is not a
/// cipher, it only lets the envelope, JSON and refusal rules run without CryptoKit.
func toySeal(_ json: String, nonce: UInt8 = 1) -> String {
    PhoneSeal.base64URL(Data(repeating: nonce, count: 12) + Data(json.utf8) + Data(count: 16))
}

let toyOpen: PhoneSealOpen = { key, _, box, aad in
    guard key == sealTestKey, aad == Data("player-nuvio-login-v1".utf8), box.count >= 16 else { return nil }
    return Data(box.dropLast(16))
}

func loginJSON(_ email: String, _ password: String) -> String {
    let d = try! JSONSerialization.data(withJSONObject: ["email": email, "password": password])
    return String(data: d, encoding: .utf8)!
}

func sealedBody(_ email: String, _ password: String, nonce: UInt8 = 1) -> String {
    "sealed=" + toySeal(loginJSON(email, password), nonce: nonce)
}

private struct Fixture: Decodable {
    let keyHex, nonceHex, aad, plaintext, email, password, sealed, ciphertextAndTagHex: String
}

private func fixture() throws -> Fixture {
    let url = try #require(Bundle.module.url(forResource: "phone-seal-vector.json", withExtension: nil, subdirectory: "Fixtures"))
    return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
}

private func unhex(_ s: String) -> Data {
    var d = Data(), i = s.startIndex
    while i < s.endIndex { let j = s.index(i, offsetBy: 2); d.append(UInt8(s[i..<j], radix: 16)!); i = j }
    return d
}

private func html(_ r: HTTPResponse) -> String { String(data: r.body, encoding: .utf8) ?? "" }

// MARK: Envelope

@Test func sealEnvelopeSplitsNonceAndCiphertext() throws {
    let f = try fixture()
    let env = try #require(PhoneSeal.envelope(f.sealed))
    #expect(env.nonce == unhex(f.nonceHex) && env.ciphertextAndTag == unhex(f.ciphertextAndTagHex))
    #expect(env.nonce.startIndex == 0 && env.ciphertextAndTag.startIndex == 0)
    #expect(PhoneSeal.base64URL(env.nonce + env.ciphertextAndTag) == f.sealed)
    // 12 + 16 bytes is the shortest envelope (empty plaintext).
    #expect(PhoneSeal.envelope(PhoneSeal.base64URL(Data(count: 28))) != nil)
    let refused = ["", PhoneSeal.base64URL(Data(count: 27)), f.sealed + "=", f.sealed.replacingOccurrences(of: "_", with: "/"),
                   "ab+c" + f.sealed, f.sealed + String(repeating: "A", count: (5 - f.sealed.count % 4) % 4) /* length % 4 == 1 is never base64 */, " " + f.sealed, String(repeating: "A", count: PhoneSeal.maxFieldLength + 4)]
    for t in refused { #expect(PhoneSeal.envelope(t) == nil, "\(t.prefix(20))") }
}

@Test func sealedLoginJSONNeedsTwoStrings() {
    #expect(PhoneSeal.login(fromJSON: Data(loginJSON("a@b", "p").utf8)) == PhoneNuvioLogin(email: PhoneSecret("a@b"), password: PhoneSecret("p")))
    for bad in ["", "{}", "[]", "{\"email\":\"a\"}", "{\"email\":1,\"password\":\"p\"}", "{\"email\":\"a\",\"password\":null}", "nope"] {
        #expect(PhoneSeal.login(fromJSON: Data(bad.utf8)) == nil, "\(bad)")
    }
}

// MARK: Key and QR address

@Test func qrAddressCarriesThePageKeyOnlyInTheFragment() throws {
    let s = PhoneSession(token: "tok", now: t0, pageKey: sealTestKey)
    let k = PhoneSeal.base64URL(sealTestKey)
    #expect(k.count == 43 && !k.contains("="))
    #expect(s.qrAddress(base: "http://192.0.2.1:8765", section: .nuvio) == "http://192.0.2.1:8765/?t=tok#nuvio&k=\(k)")
    #expect(s.qrAddress(base: "http://192.0.2.1:8765", section: nil) == "http://192.0.2.1:8765/?t=tok#k=\(k)")
    for section in PhoneSection.allCases {
        let url = try #require(URLComponents(string: s.qrAddress(base: "http://h:1", section: section)))
        #expect(url.query == "t=tok" && url.fragment == "\(section.rawValue)&k=\(k)")
    }
    // Random per session, 32 bytes.
    let a = PhoneSession(token: "x", now: t0), b = PhoneSession(token: "x", now: t0)
    #expect(a.pageKey.count == 32 && a.pageKey != b.pageKey)
}

@Test func sessionNeverPrintsItsPageKey() {
    let s = startedSealSession()
    var dumped = ""
    dump(s, to: &dumped)
    let k = PhoneSeal.base64URL(sealTestKey)
    for text in [String(describing: s), String(reflecting: s), dumped] {
        #expect(!text.contains(k) && !text.contains("64, 65, 66") && !text.contains("40414243"), "\(text)")
    }
}

// MARK: Opening in the session

@Test func sealedLoginOpensOnceWithTheSessionKey() {
    var s = startedSealSession()
    let body = toySeal(loginJSON("a@b.example", "pw"), nonce: 7)
    let seen = SealCalls()
    let open: PhoneSealOpen = { key, nonce, box, aad in seen.add(key, nonce, aad); return toyOpen(key, nonce, box, aad) }
    #expect(s.openNuvioLogin(body, open: open) == PhoneNuvioLogin(email: PhoneSecret("a@b.example"), password: PhoneSecret("pw")))
    #expect(seen.calls == [[sealTestKey, Data(repeating: 7, count: 12), Data("player-nuvio-login-v1".utf8)]])
    // The same nonce again (a replay of the captured post) is refused, a new one is fine.
    #expect(s.openNuvioLogin(body, open: open) == nil)
    #expect(s.openNuvioLogin(toySeal(loginJSON("a@b.example", "pw"), nonce: 8), open: open) != nil)
}

@Test func sealedLoginFailsClosed() {
    var s = startedSealSession()
    let body = toySeal(loginJSON("a@b", "p"))
    #expect(s.openNuvioLogin(body, open: nil) == nil)                       // no opener: every sealed post is refused
    #expect(s.openNuvioLogin(body, open: { _, _, _, _ in nil }) == nil)     // wrong key or tampered data
    #expect(s.openNuvioLogin("x", open: toyOpen) == nil)                    // no envelope
    #expect(s.openNuvioLogin(toySeal("{\"email\":\"a\"}", nonce: 3), open: toyOpen) == nil)
    // A failed open does not use up the nonce.
    #expect(s.openNuvioLogin(body, open: toyOpen) != nil)
    // Not started yet, or ended: nothing opens.
    var fresh = PhoneSession(token: "tok", now: t0, pageKey: sealTestKey)
    #expect(fresh.openNuvioLogin(toySeal(loginJSON("a@b", "p"), nonce: 4), open: toyOpen) == nil)
    s.end()
    #expect(s.openNuvioLogin(toySeal(loginJSON("a@b", "p"), nonce: 5), open: toyOpen) == nil)
    // A new session has a new key: a post sealed for the old one does not open.
    var next = startedSealSession(key: PhoneSession.randomPageKey())
    #expect(next.openNuvioLogin(toySeal(loginJSON("a@b", "p"), nonce: 6), open: toyOpen) == nil)
}

final class SealCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [[Data]] = []
    func add(_ k: Data, _ n: Data, _ a: Data) { lock.lock(); list.append([k, n, a]); lock.unlock() }
    var calls: [[Data]] { lock.lock(); defer { lock.unlock() }; return list }
}

// MARK: POST /nuvio

@Test func sealedNuvioPostGivesExactlyOneSignIn() {
    var s = startedSealSession()
    let page = PhoneInputPage()
    let (resp, cmds) = page.handle(post("/nuvio", sealedBody("  user@example.org \n", "FAKE-PASS-0013 &=+ä")), profileName: "Ich",
                                   nuvioLogin: { s.openNuvioLogin($0, open: toyOpen) }) { Data() }
    #expect(cmds == [.nuvioSignIn(email: PhoneSecret("user@example.org"), password: PhoneSecret("FAKE-PASS-0013 &=+ä"))])
    #expect(resp.status == 303 && resp.extraHeaders["Location"] == "/?nv=gesendet#nuvio" && resp.body.isEmpty)
}

@Test func cleartextNuvioFieldsAreRefused() {
    var s = startedSealSession()
    let page = PhoneInputPage()
    var asked = 0
    for body in ["email=a%40b&password=p", "email=a%40b", "password=p", "email=&password=",
                 sealedBody("a@b", "p") + "&password=p", "email=a%40b&" + sealedBody("a@b", "p", nonce: 2)] {
        let (resp, cmds) = page.handle(post("/nuvio", body), profileName: "Ich",
                                       nuvioLogin: { asked += 1; return s.openNuvioLogin($0, open: toyOpen) }) { Data() }
        #expect(cmds.isEmpty, "\(body)")
        #expect(resp.status == 303 && resp.extraHeaders["Location"] == "/?nv=krypto#nuvio")
        #expect(!(resp.extraHeaders["Location"] ?? "").contains("a@b") && resp.body.isEmpty)
    }
    #expect(asked == 0)
}

@Test func sealedNuvioPostWithoutOpenerOrWithFailedOpenGivesNoCommand() {
    let page = PhoneInputPage()
    // Default of the page: no opener at all.
    let (r1, c1) = page.handle(post("/nuvio", sealedBody("a@b", "p")), profileName: "Ich") { Data() }
    #expect(c1.isEmpty && r1.extraHeaders["Location"] == "/?nv=krypto#nuvio")
    var s = startedSealSession()
    for body in [sealedBody("a@b", "p"), "", "sealed=", "sealed=%%%"] {
        let (r, c) = page.handle(post("/nuvio", body), profileName: "Ich", nuvioLogin: { s.openNuvioLogin($0, open: nil) }) { Data() }
        #expect(c.isEmpty && r.extraHeaders["Location"] == "/?nv=krypto#nuvio", "\(body)")
    }
    let (r2, c2) = page.handle(post("/nuvio", sealedBody("a@b", "p")), profileName: "Ich",
                               nuvioLogin: { s.openNuvioLogin($0, open: { _, _, _, _ in nil }) }) { Data() }
    #expect(c2.isEmpty && r2.extraHeaders["Location"] == "/?nv=krypto#nuvio")
}

@Test func replayedSealedNuvioPostIsRefused() {
    var s = startedSealSession()
    let page = PhoneInputPage()
    let body = sealedBody("a@b", "p", nonce: 9)
    let (_, first) = page.handle(post("/nuvio", body), profileName: "Ich", nuvioLogin: { s.openNuvioLogin($0, open: toyOpen) }) { Data() }
    let (again, second) = page.handle(post("/nuvio", body), profileName: "Ich", nuvioLogin: { s.openNuvioLogin($0, open: toyOpen) }) { Data() }
    #expect(first.count == 1 && second.isEmpty && again.extraHeaders["Location"] == "/?nv=krypto#nuvio")
}

@Test func sealedNuvioPostKeepsTheFieldRules() {
    let page = PhoneInputPage()
    var s = startedSealSession()
    var n: UInt8 = 20
    func send(_ e: String, _ p: String, backups: PhoneBackupState = PhoneBackupState(), nuvio: PhoneNuvioState = .signedOut) -> (HTTPResponse, [PhoneCommand]) {
        n += 1
        return page.handle(post("/nuvio", sealedBody(e, p, nonce: n)), profileName: "Ich", backups: backups, nuvio: nuvio,
                           nuvioLogin: { s.openNuvioLogin($0, open: toyOpen) }) { Data() }
    }
    for (e, p) in [("", "p"), ("   ", "p"), ("a@b", ""), (String(repeating: "a", count: 257), "p"), ("a@b", String(repeating: "p", count: 257))] {
        let (r, c) = send(e, p)
        #expect(c.isEmpty && r.extraHeaders["Location"] == "/?nv=leer#nuvio")
    }
    #expect(send(String(repeating: "a", count: 256), String(repeating: "p", count: 256)).1.count == 1)
    let (busy, none) = send("a@b", "p", backups: PhoneBackupState(requestOpen: true))
    #expect(none.isEmpty && busy.extraHeaders["Location"] == "/?wt=offen#nuvio")
    for state: PhoneNuvioState in [.connected(profileName: "Wohnzimmer"), .busy] {
        let (r, c) = send("a@b", "p", nuvio: state)
        #expect(c.isEmpty && r.extraHeaders["Location"] == "/#nuvio")
    }
}

// MARK: The key never leaves the TV

@Test func pageKeyNeverAppearsInAnyResponse() {
    let key = Data((0..<32).map { UInt8(0xA0 + $0) })
    var s = PhoneSession(token: "tok", now: t0, pageKey: key)
    let forms = [Data(key), Data(PhoneSeal.base64URL(key).utf8), Data(key.base64EncodedString().utf8),
                 Data(key.map { String(format: "%02x", $0) }.joined().utf8)]
    var responses: [HTTPResponse] = []
    // Session paths: too large, first use (303 with cookie), denied.
    if case .respond(let r) = s.admit(head("POST /nuvio HTTP/1.1\r\nContent-Length: 999999\r\n\r\n"), peer: phone, now: t0) { responses.append(r) }
    guard case .respond(let first) = s.admit(head("GET /?t=tok HTTP/1.1\r\n\r\n"), peer: phone, now: t0) else { Issue.record("303"); return }
    responses.append(first)
    #expect(first.status == 303 && first.extraHeaders["Location"] == "/")
    if case .respond(let r) = s.admit(head("GET /?t=tok HTTP/1.1\r\n\r\n"), peer: "192.0.2.99", now: t0 + 1) { responses.append(r) }
    // Page paths: every Nuvio state and note, and every POST /nuvio outcome.
    let page = PhoneInputPage()
    for state: PhoneNuvioState in [.signedOut, .busy, .connected(profileName: "W")] {
        for q in ["", "?nv=gesendet", "?nv=leer", "?nv=krypto"] {
            responses.append(page.handle(req("GET /\(q) HTTP/1.1\r\n\r\n"), profileName: "Ich", nuvio: state) { Data() }.0)
        }
    }
    let open: PhoneSealOpen = { k, _, box, _ in k == key && box.count >= 16 ? Data(box.dropLast(16)) : nil }
    for body in [sealedBody("a@b", "p", nonce: 1), sealedBody("a@b", "p", nonce: 1), sealedBody("", "p", nonce: 2), "email=a&password=b", "sealed=zz", ""] {
        for backups in [PhoneBackupState(), PhoneBackupState(requestOpen: true)] {
            responses.append(page.handle(post("/nuvio", body), profileName: "Ich", backups: backups,
                                         nuvioLogin: { s.openNuvioLogin($0, open: open) }) { Data() }.0)
        }
    }
    responses.append(page.handle(req("GET /nirgends HTTP/1.1\r\n\r\n"), profileName: "Ich") { Data() }.0)
    #expect(responses.count == 28)
    for r in responses {
        let bytes = r.serialized
        for f in forms { #expect(bytes.range(of: f) == nil, "status \(r.status)") }
    }
}

// MARK: The page

@Test func nuvioFormHasNoNamedCredentialFieldsAndCarriesTheScript() {
    let out = PhoneInputPage().page(profileName: "Ich", note: nil)
    for bad in ["name=email", "name=\"email\"", "name=password", "name=\"password\"", "name='email'", "name='password'"] {
        #expect(!out.contains(bad), "\(bad)")
    }
    #expect(out.contains("id=nv_email") && out.contains("id=nv_password") && out.contains("type=\"password\""))
    #expect(out.contains("<script>" + PhoneSealScript.source + "</script>"))
    #expect(out.contains("E-Mail und Passwort werden auf dem Handy verschlüsselt, bevor sie zum Fernseher gehen. Das Passwort wird nicht gespeichert."))
    #expect(out.contains("Der Fernseher fragt nach, bevor er sich anmeldet."))
    #expect(!out.contains("unverschlüsselt durch dein WLAN"))
    // The failure note is there for the script, hidden until needed; without script a <noscript> says it.
    #expect(out.contains("<p id=nv_fail class=ok hidden>Verschlüsselung nicht möglich. Bitte den QR-Code am Fernseher neu scannen.</p>"))
    #expect(out.contains("<noscript><p class=ok>Verschlüsselung nicht möglich. Bitte den QR-Code am Fernseher neu scannen.</p></noscript>"))
    // The script also runs (and takes the key out of the address) when the form is not shown.
    #expect(PhoneInputPage().page(profileName: "Ich", note: nil, nuvio: .busy).contains(PhoneSealScript.source))
}

@Test func nuvioFailureNoteShowsAfterARefusedPost() {
    let page = PhoneInputPage()
    let out = html(page.handle(req("GET /?nv=krypto HTTP/1.1\r\n\r\n"), profileName: "Ich") { Data() }.0)
    #expect(out.contains("<p id=nv_fail class=ok>Verschlüsselung nicht möglich. Bitte den QR-Code am Fernseher neu scannen.</p>"))
}

/// The page serves `PhoneSealScript.source`; the Node test checks the text it cuts out of the Swift file. Same rule here.
@Test func phoneSealScriptIsTheSwiftConstant() throws {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/PlayerCore/Phone/PhoneSealScript.swift")
    let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
    let start = try #require(lines.firstIndex { $0.hasSuffix("public static let source = #\"\"\"") })
    let end = try #require(lines[(start + 1)...].firstIndex { $0 == "\"\"\"#" })
    #expect(lines[(start + 1)..<end].joined(separator: "\n") == PhoneSealScript.source)
}

// MARK: The JavaScript fixture

/// The envelope the JavaScript produced reaches the opener split exactly as CryptoKit needs it.
@Test func javaScriptFixtureReachesTheOpenerInParts() throws {
    let f = try fixture()
    var s = startedSealSession(key: unhex(f.keyHex))
    let plain = Data(f.plaintext.utf8), ct = unhex(f.ciphertextAndTagHex), key = unhex(f.keyHex), nonce = unhex(f.nonceHex)
    let open: PhoneSealOpen = { k, n, box, aad in
        k == key && n == nonce && box == ct && aad == Data(f.aad.utf8) ? plain : nil
    }
    #expect(f.aad == PhoneSeal.label)
    #expect(s.openNuvioLogin(f.sealed, open: open) == PhoneNuvioLogin(email: PhoneSecret(f.email), password: PhoneSecret(f.password)))
}

#if canImport(CryptoKit)
/// Cross-check JavaScript → CryptoKit: only where CryptoKit exists (Apple platforms). CI runs PlayerCore tests on Linux.
@Test func javaScriptFixtureOpensWithCryptoKit() throws {
    let f = try fixture()
    let ct = unhex(f.ciphertextAndTagHex)
    let box = try ChaChaPoly.SealedBox(nonce: ChaChaPoly.Nonce(data: unhex(f.nonceHex)), ciphertext: ct.dropLast(16), tag: ct.suffix(16))
    let plain = try ChaChaPoly.open(box, using: SymmetricKey(data: unhex(f.keyHex)), authenticating: Data(f.aad.utf8))
    #expect(String(data: plain, encoding: .utf8) == f.plaintext)
    // The same opener the app uses, through the session.
    let open: PhoneSealOpen = { key, nonce, box, aad in
        guard box.count >= 16, let n = try? ChaChaPoly.Nonce(data: nonce),
              let sealed = try? ChaChaPoly.SealedBox(nonce: n, ciphertext: box.dropLast(16), tag: box.suffix(16)) else { return nil }
        return try? ChaChaPoly.open(sealed, using: SymmetricKey(data: key), authenticating: aad)
    }
    var s = startedSealSession(key: unhex(f.keyHex))
    #expect(s.openNuvioLogin(f.sealed, open: open) == PhoneNuvioLogin(email: PhoneSecret(f.email), password: PhoneSecret(f.password)))
    var tampered = Array(f.sealed); tampered[30] = tampered[30] == "A" ? "B" : "A"
    var s2 = startedSealSession(key: unhex(f.keyHex))
    #expect(s2.openNuvioLogin(String(tampered), open: open) == nil)
}
#endif
