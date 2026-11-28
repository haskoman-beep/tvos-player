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

/// Review T1b: the `sealed` field may be as long as the body of `POST /nuvio` allows, so every input that fits the body
/// is opened and gets the field rules (`nv=leer` when too long), never `nv=krypto` for its size alone.
@Test func sealFieldLimitIsTheNuvioBodyLimit() {
    #expect(PhoneLimits.maxBody(for: PhoneInputPage.nuvioPath) == 16 * 1024)
    #expect(PhoneSeal.maxFieldLength == 16 * 1024 - "sealed=".utf8.count)
    let longest = PhoneSeal.base64URL(Data(count: 12_282)), over = PhoneSeal.base64URL(Data(count: 12_283))
    #expect(longest.utf8.count == PhoneSeal.maxFieldLength - 1 && over.utf8.count == PhoneSeal.maxFieldLength + 1)
    #expect(PhoneSeal.envelope(longest) != nil && PhoneSeal.envelope(over) == nil)
    // The page pads the sign-in to 1024 bytes (more for long fields); the largest allowed one is 4096 bytes.
    #expect(PhoneSeal.paddingBlock == 1024)
}

@Test func sealedLoginJSONIgnoresThePadding() {
    let padded = "{\"email\":\"a@b\",\"password\":\"p\",\"pad\":\"" + String(repeating: " ", count: 990) + "\"}"
    #expect(PhoneSeal.login(fromJSON: Data(padded.utf8)) == PhoneNuvioLogin(email: PhoneSecret("a@b"), password: PhoneSecret("p")))
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

/// Review T1b: `POST /nuvio` takes exactly one field, `sealed`; anything else is refused before opening.
@Test func nuvioPostAcceptsOnlyTheSealedField() {
    var s = startedSealSession()
    let page = PhoneInputPage()
    var asked = 0
    let good = sealedBody("a@b", "p", nonce: 40)
    for body in [good + "&x=1", "x=1&" + good, good + "&" + sealedBody("a@b", "p", nonce: 41), good + "&", good + "&=1",
                 good + "&sealed", "SEALED=" + toySeal(loginJSON("a@b", "p"), nonce: 42), "x=1", ""] {
        let (resp, cmds) = page.handle(post("/nuvio", body), profileName: "Ich",
                                       nuvioLogin: { asked += 1; return s.openNuvioLogin($0, open: toyOpen) }) { Data() }
        #expect(cmds.isEmpty, "\(body)")
        #expect(resp.status == 303 && resp.extraHeaders["Location"] == "/?nv=krypto#nuvio", "\(body)")
    }
    #expect(asked == 0)
    // The same envelope alone still goes through (the refusals above did not use up its nonce).
    let (ok, cmds) = page.handle(post("/nuvio", good), profileName: "Ich", nuvioLogin: { s.openNuvioLogin($0, open: toyOpen) }) { Data() }
    #expect(cmds.count == 1 && ok.extraHeaders["Location"] == "/?nv=gesendet#nuvio")
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
    // Review T1b: the limit counts UTF-8 bytes (as the page script does), not characters.
    let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"   // one grapheme, 25 UTF-8 bytes
    for (e, p) in [("", "p"), ("   ", "p"), ("a@b", ""), (String(repeating: "a", count: 257), "p"), ("a@b", String(repeating: "p", count: 257)),
                   ("a@b", String(repeating: "ä", count: 129)), (String(repeating: "ä", count: 129), "p"),
                   ("a@b", String(repeating: family, count: 11)), ("a@b", String(repeating: family, count: 256))] {
        let (r, c) = send(e, p)
        #expect(c.isEmpty && r.extraHeaders["Location"] == "/?nv=leer#nuvio", "\(e.utf8.count) \(p.utf8.count)")
    }
    #expect(send(String(repeating: "a", count: 256), String(repeating: "p", count: 256)).1.count == 1)
    #expect(send(String(repeating: "ä", count: 128), String(repeating: "ä", count: 128)).1.count == 1)
    #expect(send("a@b", String(repeating: family, count: 10)).1.count == 1)   // 250 bytes
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

/// Review T1b: a scanner that wrote `#` as `%23` sends the page key in the query. The key then crossed the Wi-Fi, so
/// the session ends at once and the TV shows a new code (`needsNewCode`).
@Test func pageKeyInTheRequestEndsTheSession() {
    let k = PhoneSeal.base64URL(sealTestKey)
    for target in ["/?t=tok%23nuvio&k=\(k)", "/?t=tok%23nuvio%26k%3D\(k)", "/?t=tok%23k=\(k)", "/?t=tok%23nuvio%26k%3d\(k)",
                   "/?k=\(k)", "/?t=tok&k=", "/?t=tok#nuvio&k=\(k)", "/nuvio?k=\(k)"] {
        var s = PhoneSession(token: "tok", now: t0, pageKey: sealTestKey)
        let method = target.hasPrefix("/nuvio") ? "POST" : "GET"
        guard case .respond(let r) = s.admit(head("\(method) \(target) HTTP/1.1\r\nContent-Length: 0\r\n\r\n"), peer: phone, now: t0) else {
            Issue.record("refusal expected: \(target)"); continue
        }
        #expect(r.status == 403 && r.extraHeaders["Set-Cookie"] == nil, "\(target)")
        #expect(s.ended && !s.tokenUsed && s.needsNewCode(now: t0), "\(target)")
        // The token of this code no longer opens anything.
        #expect(s.authorize(queryToken: "tok", cookie: nil, peer: phone, now: t0) == .denied)
    }
    // Also after the first use, with a valid cookie.
    var s = PhoneSession(token: "tok", now: t0, pageKey: sealTestKey)
    guard case .firstUse(let set) = s.authorize(queryToken: "tok", cookie: nil, peer: phone, now: t0) else { Issue.record("first use"); return }
    let c = String(set.split(separator: ";")[0])
    guard case .respond(let r) = s.admit(head("POST /nuvio?x=1&k=\(k) HTTP/1.1\r\nCookie: \(c)\r\nContent-Length: 10\r\n\r\n"), peer: phone, now: t0 + 1) else {
        Issue.record("refusal expected"); return
    }
    #expect(r.status == 403 && s.ended && !s.isConnected && s.needsNewCode(now: t0 + 1))
}

/// Parameters that only end in `k` (`ok`, `lk`) or carry `k=` inside a value are no page key.
@Test func pageKeyCheckLeavesOtherParametersAlone() {
    var s = PhoneSession(token: "tok", now: t0, pageKey: sealTestKey)
    guard case .respond(let first) = s.admit(head("GET /?t=tok&lk=3&ok=home HTTP/1.1\r\n\r\n"), peer: phone, now: t0) else { Issue.record("303"); return }
    #expect(first.status == 303 && !s.ended)
    let c = String((first.extraHeaders["Set-Cookie"] ?? "").split(separator: ";")[0])
    for target in ["/?ok=home", "/?lk=2&lku=1", "/?nv=gesendet", "/export?secrets=1", "/?imp=unknown&ok=leer"] {
        #expect(s.admit(head("GET \(target) HTTP/1.1\r\nCookie: \(c)\r\n\r\n"), peer: phone, now: t0 + 1) == .readBody(0), "\(target)")
    }
    #expect(!s.ended)
}

/// Review T1b: the "no access" answer carries the page script with the marker `nv_forget`, so the phone drops a
/// stored page key (and one in the address of an old QR code).
@Test func deniedAnswerTellsThePhoneToForgetTheKey() {
    var s = PhoneSession(token: "tok", now: t0, pageKey: sealTestKey)
    guard case .respond(let r) = s.admit(head("GET /?t=wrong HTTP/1.1\r\n\r\n"), peer: phone, now: t0) else { Issue.record("403"); return }
    let body = html(r)
    #expect(r.status == 403 && body.contains("<p id=nv_forget hidden></p>") && body.contains("<script>" + PhoneSealScript.source + "</script>"))
    #expect(body.contains("Diese Adresse gilt nicht mehr."))
    // The page itself has no such marker.
    #expect(!PhoneInputPage().page(profileName: "Ich", note: nil).contains("nv_forget hidden"))
}

// MARK: The page

/// The opening tags `<input …>` whose `id` is `id`.
private func inputTags(_ html: String, id: String) -> [String] {
    var tags: [String] = [], rest = html[...]
    while let r = rest.range(of: "<input", options: .caseInsensitive) {
        let tag = String(rest[r.lowerBound...].prefix { $0 != ">" })
        if tagAttributes(tag)["id"] == id { tags.append(tag) }
        rest = rest[r.upperBound...]
    }
    return tags
}

/// Attribute names (lower case) of an opening tag, with their values; quoted and unquoted values.
private func tagAttributes(_ tag: String) -> [String: String] {
    var out: [String: String] = [:]
    let open = tag.hasSuffix(">") ? tag.dropLast() : tag[...]
    var chars = Array(open.drop { $0 != " " && $0 != "\t" && $0 != "\n" })[...]
    func skipSpace() { while let c = chars.first, c == " " || c == "\t" || c == "\n" || c == "/" { chars = chars.dropFirst() } }
    skipSpace()
    while !chars.isEmpty {
        var name = ""
        while let c = chars.first, c != "=", c != " ", c != "\t", c != "\n", c != "/" { name.append(c); chars = chars.dropFirst() }
        var value = ""
        if chars.first == "=" {
            chars = chars.dropFirst()
            if let q = chars.first, q == "\"" || q == "'" {
                chars = chars.dropFirst()
                while let c = chars.first, c != q { value.append(c); chars = chars.dropFirst() }
                chars = chars.dropFirst()
            } else {
                while let c = chars.first, c != " ", c != "\t", c != "\n" { value.append(c); chars = chars.dropFirst() }
            }
        }
        if !name.isEmpty { out[name.lowercased()] = value }
        skipSpace()
    }
    return out
}

@Test func nuvioFormHasNoNamedCredentialFieldsAndCarriesTheScript() {
    let out = PhoneInputPage().page(profileName: "Ich", note: nil)
    // Review T1b: the e-mail and password inputs carry no `name` attribute at all (parsed, not two fixed names).
    for id in ["nv_email", "nv_password"] {
        let tags = inputTags(out, id: id)
        #expect(tags.count == 1, "\(id)")
        for tag in tags {
            let attrs = tagAttributes(tag)
            #expect(attrs["name"] == nil && !tag.lowercased().contains("name="), "\(tag)")
            #expect(attrs["form"] == "nuvioform" && attrs["value"] == nil, "\(tag)")
        }
    }
    // The parser itself: names in any case, quoted and unquoted values, an attribute without a value.
    #expect(tagAttributes("<input NAME=a id=q>")["name"] == "a" && tagAttributes("<input id=\"q r\" name='a'>") == ["id": "q r", "name": "a"])
    #expect(tagAttributes("<input name id=q>") == ["name": "", "id": "q"])
    #expect(inputTags(out, id: "nv_password").first.map { tagAttributes($0)["type"] } == "password")
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

/// The field limit the page script checks before sealing (`FIELD_LIMIT`) is the one the TV applies.
@Test func phoneSealScriptUsesTheServerFieldLimit() {
    #expect(PhoneInputPage.nuvioFieldLimit == 256)
    #expect(PhoneSealScript.source.contains("var FIELD_LIMIT = \(PhoneInputPage.nuvioFieldLimit);"))
    #expect(PhoneSealScript.source.contains("var PAD_BLOCK = \(PhoneSeal.paddingBlock);"))
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

/// Review T1b: the fixture's plaintext is padded to 1024 bytes and carries the member `pad`.
@Test func javaScriptFixtureIsPadded() throws {
    let f = try fixture()
    #expect(f.plaintext.utf8.count == 1024 && unhex(f.ciphertextAndTagHex).count == 1024 + 16)
    let obj = try #require(JSONSerialization.jsonObject(with: Data(f.plaintext.utf8)) as? [String: String])
    #expect(Set(obj.keys) == ["email", "password", "pad"] && obj["pad"]!.allSatisfy { $0 == " " })
}

#if canImport(CryptoKit)
/// Cross-check JavaScript → CryptoKit with the opener the app ships (`PhoneSeal.cryptoKitOpen`): only where CryptoKit
/// exists. CI runs these on the macOS runner (`swift test --filter javaScriptFixture`), the rest of the suite on Linux.
@Test func javaScriptFixtureOpensWithCryptoKit() throws {
    let f = try fixture()
    let ct = unhex(f.ciphertextAndTagHex)
    let box = try ChaChaPoly.SealedBox(nonce: ChaChaPoly.Nonce(data: unhex(f.nonceHex)), ciphertext: ct.dropLast(16), tag: ct.suffix(16))
    let plain = try ChaChaPoly.open(box, using: SymmetricKey(data: unhex(f.keyHex)), authenticating: Data(f.aad.utf8))
    #expect(String(data: plain, encoding: .utf8) == f.plaintext)
    #expect(PhoneSeal.cryptoKitOpen(unhex(f.keyHex), unhex(f.nonceHex), ct, PhoneSeal.aad) == Data(f.plaintext.utf8))
    // Through the session, as the app calls it.
    var s = startedSealSession(key: unhex(f.keyHex))
    #expect(s.openNuvioLogin(f.sealed, open: PhoneSeal.cryptoKitOpen) == PhoneNuvioLogin(email: PhoneSecret(f.email), password: PhoneSecret(f.password)))
    var tampered = Array(f.sealed); tampered[30] = tampered[30] == "A" ? "B" : "A"
    var s2 = startedSealSession(key: unhex(f.keyHex))
    #expect(s2.openNuvioLogin(String(tampered), open: PhoneSeal.cryptoKitOpen) == nil)
}

@Test func javaScriptFixtureRefusesWrongKeyOrAADWithCryptoKit() throws {
    let f = try fixture()
    let key = unhex(f.keyHex), nonce = unhex(f.nonceHex), ct = unhex(f.ciphertextAndTagHex)
    var otherKey = key; otherKey[0] ^= 1
    #expect(PhoneSeal.cryptoKitOpen(otherKey, nonce, ct, PhoneSeal.aad) == nil)
    #expect(PhoneSeal.cryptoKitOpen(key, nonce, ct, Data("player-nuvio-login-v2".utf8)) == nil)
    #expect(PhoneSeal.cryptoKitOpen(key, nonce, ct, Data()) == nil)
    // Malformed parts: short key, short nonce, box shorter than a tag.
    #expect(PhoneSeal.cryptoKitOpen(key.prefix(31), nonce, ct, PhoneSeal.aad) == nil)
    #expect(PhoneSeal.cryptoKitOpen(key, nonce.prefix(11), ct, PhoneSeal.aad) == nil)
    #expect(PhoneSeal.cryptoKitOpen(key, nonce, ct.prefix(15), PhoneSeal.aad) == nil)
    // Through the session: a session with another key does not open the fixture.
    var s = startedSealSession(key: otherKey)
    #expect(s.openNuvioLogin(f.sealed, open: PhoneSeal.cryptoKitOpen) == nil)
}
#endif
