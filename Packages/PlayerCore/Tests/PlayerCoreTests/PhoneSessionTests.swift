import Foundation
import Testing
@testable import PlayerCore

// Task 1.4: phone page session (one-time address, cookie), limits before the body, confirmation on the TV,
// export without secrets, encrypted backup file.

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let phone = "192.0.2.10"

private func head(_ s: String) -> RequestHead {
    guard case .complete(let h) = HTTPRequest.parseHead(Data(s.utf8)) else { fatalError("head") }
    return h
}

private func cookieHeader(_ auth: PhoneAuth) -> String {
    guard case .firstUse(let set) = auth else { fatalError("no cookie") }
    return String(set.split(separator: ";")[0])   // "name=value", as the browser sends it back
}

/// Deterministic stand-in for CryptoKit (test target only): keystream and tag from FNV-1a over code, salt and nonce.
/// Not secure; it only lets the file format, the round trip and the error paths run on Linux.
private struct ToyCipher: BackupCipher {
    struct Mismatch: Error {}
    static func fnv(_ parts: [Data], seed: UInt64 = 0xcbf2_9ce4_8422_2325) -> UInt64 {
        var h = seed
        for p in parts { for b in p { h ^= UInt64(b); h = h &* 0x0000_0100_0000_01b3 } ; h ^= 0xff; h = h &* 0x0000_0100_0000_01b3 }
        return h
    }
    func stream(_ n: Int, code: String, salt: Data, nonce: Data) -> [UInt8] {
        var x = Self.fnv([Data(code.utf8), salt, nonce]) | 1
        return (0..<n).map { _ in x ^= x << 13; x ^= x >> 7; x ^= x << 17; return UInt8(truncatingIfNeeded: x) }
    }
    func tag(_ c: Data, code: String, salt: Data, nonce: Data, header: Data) -> Data {
        let a = Self.fnv([Data(code.utf8), salt, nonce, header, c]), b = Self.fnv([c, header, Data(code.utf8)], seed: a)
        return withUnsafeBytes(of: a.bigEndian) { Data($0) } + withUnsafeBytes(of: b.bigEndian) { Data($0) }
    }
    func seal(_ plaintext: Data, code: String, salt: Data, nonce: Data, header: Data) throws -> (ciphertext: Data, tag: Data) {
        let c = Data(zip(plaintext, stream(plaintext.count, code: code, salt: salt, nonce: nonce)).map { $0 ^ $1 })
        return (c, tag(c, code: code, salt: salt, nonce: nonce, header: header))
    }
    func open(_ ciphertext: Data, tag t: Data, code: String, salt: Data, nonce: Data, header: Data) throws -> Data {
        guard tag(ciphertext, code: code, salt: salt, nonce: nonce, header: header) == t else { throw Mismatch() }
        return Data(zip(ciphertext, stream(ciphertext.count, code: code, salt: salt, nonce: nonce)).map { $0 ^ $1 })
    }
}

private let crypto = BackupCrypto(cipher: ToyCipher())

// MARK: Brief step 1 (10 tests)

@Test func phoneTokenWorksExactlyOnce() {
    var s = PhoneSession(token: "tok", now: t0)
    let first = s.authorize(queryToken: "tok", cookie: nil, peer: phone, now: t0)
    guard case .firstUse(let set) = first else { Issue.record("first use expected"); return }
    #expect(set.contains("HttpOnly") && set.contains("SameSite=Lax") && set.contains("Path=/"))
    #expect(s.authorize(queryToken: nil, cookie: cookieHeader(first), peer: phone, now: t0 + 5) == .ok)
    // The address in the QR code is spent: the same token again (other device or other browser) gets nothing.
    #expect(s.authorize(queryToken: "tok", cookie: nil, peer: "192.0.2.11", now: t0 + 6) == .denied)
}

@Test func phoneSecondCallWithoutCookieIsDenied() {
    var s = PhoneSession(token: "tok", now: t0)
    _ = s.authorize(queryToken: "tok", cookie: nil, peer: phone, now: t0)
    #expect(s.authorize(queryToken: "tok", cookie: nil, peer: phone, now: t0 + 1) == .denied)
    #expect(s.authorize(queryToken: nil, cookie: nil, peer: phone, now: t0 + 1) == .denied)
    #expect(s.authorize(queryToken: nil, cookie: "\(PhoneSession.cookieName)=geraten", peer: phone, now: t0 + 1) == .denied)
}

@Test func phoneTokenExpiresAfterTenMinutes() {
    var late = PhoneSession(token: "tok", now: t0)
    #expect(late.authorize(queryToken: "tok", cookie: nil, peer: phone, now: t0 + 10 * 60) == .denied)
    #expect(late.needsNewCode(now: t0 + 10 * 60))
    var inTime = PhoneSession(token: "tok", now: t0)
    #expect(!inTime.needsNewCode(now: t0 + 599))
    if case .firstUse = inTime.authorize(queryToken: "tok", cookie: nil, peer: phone, now: t0 + 599) {} else { Issue.record("still valid at 9:59") }
}

@Test func phoneBodyIsNotReadForWrongToken() {
    var s = PhoneSession(token: "tok", now: t0)
    let h = head("POST /submit?t=falsch HTTP/1.1\r\nContent-Length: 4000000\r\n\r\n")
    guard case .respond(let r) = s.admit(h, peer: phone, now: t0) else { Issue.record("must answer before the body"); return }
    #expect(r.status == 403)
    // The token is not spent by a wrong try.
    if case .respond(let ok) = s.admit(head("GET /?t=tok HTTP/1.1\r\n\r\n"), peer: phone, now: t0 + 1) {
        #expect(ok.status == 303 && ok.extraHeaders["Set-Cookie"] != nil && ok.extraHeaders["Location"] == "/")
    } else { Issue.record("first use redirects") }
}

@Test func phoneHomeBodyOverLimitIs413() {
    var s = PhoneSession(token: "tok", now: t0)
    let c = cookieHeader(s.authorize(queryToken: "tok", cookie: nil, peer: phone, now: t0))
    let big = s.admit(head("POST /home HTTP/1.1\r\nCookie: \(c)\r\nContent-Length: \(20 * 1024)\r\n\r\n"), peer: phone, now: t0 + 1)
    guard case .respond(let r) = big else { Issue.record("413 expected"); return }
    #expect(r.status == 413)
    #expect(s.admit(head("POST /home HTTP/1.1\r\nCookie: \(c)\r\nContent-Length: 30\r\n\r\n"), peer: phone, now: t0 + 2) == .readBody(30))
    #expect(PhoneLimits.maxBody(for: "/home") == 16 * 1024 && PhoneLimits.maxBody(for: "/submit") == 8 * 1024 * 1024)
    #expect(PhoneLimits.maxConnections == 4 && PhoneLimits.requestDeadline == 10)
}

@Test func plainExportHoldsNoneOfTheFixtureSecrets() throws {
    let data = try fixture("build249-profiles.json")
    var s = try ProfileStore.decode(data)
    s.profiles[0].addons.append(InstalledAddon(manifestURL: "https://nutzer:FAKE-PASS-0003@addon3.example/eyJGQUtFLUNPTkZJRy0wMDA0Ijp0cnVlfQ/manifest.json?key=FAKE-KEY-0005",
                                               manifest: s.profiles[0].addons[0].manifest))
    let store = ProfileStore(directory: tempDir())
    let out = String(data: try store.exportData(s, includeSecrets: false), encoding: .utf8)!
    for secret in ["FAKE-KEY-0000", "FAKE-KEY-0001", "fake-access", "fake-refresh", "FAKE-PASS-0003", "nutzer",
                   "eyJGQUtFLUNPTkZJRy0wMDA0Ijp0cnVlfQ", "FAKE-KEY-0005"] {
        #expect(!out.contains(secret), "\(secret)")
    }
    #expect(out.contains("addon3.example") && out.contains("Beispiel-Quellen"))
}

@Test func sealedExportIsUnreadableWithoutCode() throws {
    let plain = Data(#"{"apiKeys":{"tmdb":"FAKE-KEY-0000"}}"#.utf8)
    let file = try crypto.seal(plain, code: "K7QM-2XPA-9DRT")
    let text = String(data: file, encoding: .utf8)!
    #expect(text.hasPrefix(BackupCrypto.armorLine + "\n") && !text.contains("FAKE-KEY") && BackupCrypto.isSealed(file))
    #expect(throws: BackupCryptoError.invalidCode) { try crypto.open(file, code: "") }
    // Fix round 1: case, dashes and spaces do not matter.
    for typed in ["K7QM-2XPA-9DRT", "k7qm-2xpa-9drt", "K7QM2XPA9DRT", " k7qm 2xpa 9drt ", "K7Qm 2xPA-9dRT"] {
        #expect(try crypto.open(file, code: typed) == plain, "\(typed)")
    }
}

@Test func sealedExportWithWrongCodeFails() throws {
    let file = try crypto.seal(Data("geheim".utf8), code: "K7QM-2XPA-9DRT")
    #expect(throws: BackupCryptoError.wrongCodeOrDamaged) { try crypto.open(file, code: "K7QM-2XPA-9DRU") }
    #expect(throws: BackupCryptoError.wrongCodeOrDamaged) { try crypto.open(file, code: "ABCD-EFGH-JKMN") }
}

@Test func backupCodeNormalisationAndShape() {
    #expect(BackupCrypto.normalizedCode("k7qm-2xpa-9drt") == "K7QM2XPA9DRT")
    #expect(BackupCrypto.normalizedCode(" K7QM 2XPA\t9DRT ") == "K7QM2XPA9DRT")
    #expect(BackupCrypto.groupedCode("k7qm2xpa9drt") == "K7QM-2XPA-9DRT")
    // Too short, too long, the six digits of the first draft, and the look-alikes 0/O/1/I/L.
    for bad in ["", "123456", "K7QM-2XPA-9DR", "K7QM-2XPA-9DRTX", "K7QM-2XPA-9DR0", "K7QM-2XPA-9DRO", "K7QM-2XPA-9DR1",
                "K7QM-2XPA-9DRI", "K7QM-2XPA-9DRL", "K7QM-2XPA-9DR!", "K7QM-2XPA-9DRÄ"] {
        #expect(BackupCrypto.normalizedCode(bad) == nil, "\(bad)")
    }
    #expect(BackupCrypto.codeAlphabet.count == 31 && !BackupCrypto.codeAlphabet.contains(where: { "0O1IL".contains($0) }))
    var seen = Set<String>()
    for _ in 0..<200 {
        let code = BackupCrypto.makeCode()
        let groups = code.split(separator: "-")
        #expect(code.count == 14 && groups.count == 3 && groups.allSatisfy { $0.count == 4 }, "\(code)")
        #expect(BackupCrypto.normalizedCode(code) != nil && BackupCrypto.groupedCode(code) == code, "\(code)")
        seen.insert(code)
    }
    #expect(seen.count == 200)
    // Uniform over the alphabet: a fixed generator reaches every character.
    var g = SplitMix(seed: 7), chars = Set<Character>()
    for _ in 0..<100 { chars.formUnion(BackupCrypto.makeCode(using: &g).filter { $0 != "-" }) }
    #expect(chars == Set(BackupCrypto.codeAlphabet))
}

private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Test func backupJsonNeedsConfirmation() {
    let page = PhoneInputPage()
    let json = #"{"schemaVersion":1,"profiles":[{"id":"00000000-0000-4000-8000-000000000001","name":"A"}]}"#
    let body = "backup_json=" + json.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    let (_, cmds) = page.handle(req("POST /submit HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"), profileName: "Ich") { Data() }
    #expect(cmds == [.importBackup(Data(json.utf8))])
    guard case .needsConfirmation(let summary) = cmds[0].sensitivity else { Issue.record("confirmation expected"); return }
    #expect(summary.contains("ersetzt alle Profile") && summary.contains("1 Profil"))
}

@Test func addonCommandNeedsConfirmation() {
    guard case .needsConfirmation(let summary) = PhoneCommand.addAddon("https://addon.example/FAKE-CONFIG-0006/manifest.json").sensitivity else {
        Issue.record("confirmation expected"); return
    }
    #expect(summary.contains("addon.example") && !summary.contains("FAKE-CONFIG"))
    guard case .needsConfirmation(let http) = PhoneCommand.addAddon("http://192.0.2.20:7000/manifest.json").sensitivity else { return }
    #expect(http.contains("unverschlüsselt"))
}

// MARK: Additional rules

@Test func phoneSessionEndsAfterThirtyMinutesOnCloseAndForOtherDevices() {
    var s = PhoneSession(token: "tok", now: t0)
    let c = cookieHeader(s.authorize(queryToken: "tok", cookie: nil, peer: phone, now: t0))
    #expect(s.isConnected && !s.needsNewCode(now: t0 + 60))
    #expect(s.authorize(queryToken: nil, cookie: "a=b; \(c)", peer: phone, now: t0 + 29 * 60) == .ok)
    #expect(s.authorize(queryToken: nil, cookie: c, peer: "192.0.2.99", now: t0 + 29 * 60) == .denied)   // bound to the first device
    #expect(s.authorize(queryToken: nil, cookie: c, peer: phone, now: t0 + 30 * 60) == .denied)
    #expect(s.needsNewCode(now: t0 + 30 * 60))
    var closed = PhoneSession(token: "tok", now: t0)
    let c2 = cookieHeader(closed.authorize(queryToken: "tok", cookie: nil, peer: phone, now: t0))
    closed.end()
    #expect(closed.authorize(queryToken: nil, cookie: c2, peer: phone, now: t0 + 1) == .denied && closed.needsNewCode(now: t0 + 1))
    #expect(PhoneInputPage.randomToken().count == 10 && PhoneSession.randomCookie() != PhoneSession.randomCookie())
}

@Test func headIsParsedBeforeTheBody() {
    #expect(HTTPRequest.parseHead(Data("GET /?t=x HTTP/1.1\r\nHost: a".utf8)) == .incomplete)
    #expect(HTTPRequest.parseHead(Data("MÜLL\r\n\r\n".utf8)) == .invalid)
    #expect(HTTPRequest.parseHead(Data("POST /a HTTP/1.1\r\nContent-Length: -1\r\n\r\n".utf8)) == .invalid)
    #expect(HTTPRequest.parseHead(Data(repeating: 65, count: 70 * 1024)) == .invalid)
    let h = head("POST /submit?t=x&y=1 HTTP/1.1\r\nCookie: k=v\r\nContent-Length: 12\r\n\r\naddon=")
    #expect(h.method == "POST" && h.path == "/submit" && h.query == ["t": "x", "y": "1"] && h.headers["cookie"] == "k=v")
    #expect(h.contentLength == 12 && h.bodyStart == 66)
}

@Test func sensitiveCommandsAndSummaries() {
    func summary(_ c: PhoneCommand) -> String? { if case .needsConfirmation(let s) = c.sensitivity { s } else { nil } }
    let key = summary(.setKey(service: "torbox", value: "FAKE-KEY-0007-abcd"))
    #expect(key?.contains("TorBox") == true && key?.contains("…cd") == true && key?.contains("FAKE-KEY-0007") == false)
    #expect(summary(.setKey(service: "atvloadly", value: "http://pi.example:5533"))?.contains("pi.example") == true)
    #expect(summary(.setKey(service: "playerlog", value: "FAKE-SECRET-0008"))?.contains("Fern-Log") == true)
    #expect(summary(.setKey(service: "tmdb", value: "abc"))?.contains("abc") == false)
    #expect(summary(.exportSecrets) != nil)
    let sealed = (try? crypto.seal(Data("{}".utf8), code: "ABCD-EFGH-JKMN")) ?? Data()
    #expect(summary(.importBackup(sealed))?.contains("Code") == true && PhoneCommand.importBackup(sealed).needsBackupCode)
    #expect(!PhoneCommand.importBackup(Data("{}".utf8)).needsBackupCode)
    for plain: PhoneCommand in [.addTMDBLink("list:5"), .importCollectionLink("https://a.example/x.json"), .moveRow(id: UUID(), to: 0),
                                .setRatingIconSet("https://a.example/i.json"), .importFusionURL("https://a.example/k.json")] {
        #expect(plain.sensitivity == .plain, "\(plain)")
    }
}

@Test func confirmGateHoldsOneRequestForSixtySeconds() {
    var g = PhoneConfirmGate()
    let addon = PhoneCommand.addAddon("https://addon.example/manifest.json"), link = PhoneCommand.addTMDBLink("list:5")
    let first = g.offer([link, addon, .setKey(service: "tmdb", value: "FAKE-KEY-0009")], now: t0)
    #expect(first.plain == [link] && first.refused.isEmpty)
    #expect(g.current(now: t0 + 1)?.commands == [addon, .setKey(service: "tmdb", value: "FAKE-KEY-0009")])
    #expect(g.current(now: t0 + 1)?.summary.count == 2)
    // Only one open request: a second sensitive command is refused, plain ones still go through.
    let second = g.offer([.setKey(service: "mdblist", value: "x"), link], now: t0 + 2)
    #expect(second.plain == [link] && second.refused == [.setKey(service: "mdblist", value: "x")])
    #expect(g.resolve(allow: true, now: t0 + 3) == [addon, .setKey(service: "tmdb", value: "FAKE-KEY-0009")] && g.current(now: t0 + 3) == nil)
    _ = g.offer([addon], now: t0 + 10)
    #expect(g.resolve(allow: false, now: t0 + 11).isEmpty && g.current(now: t0 + 11) == nil)
    _ = g.offer([addon], now: t0 + 20)
    #expect(g.current(now: t0 + 80) == nil && g.resolve(allow: true, now: t0 + 80).isEmpty)   // expired after 60 s
}

@Test func sealedFileFormatRoundTripAndTamper() throws {
    let plain = Data((0..<300).map { UInt8($0 % 251) })
    let a = try crypto.seal(plain, code: "K7QM-2XPA-9DRT"), b = try crypto.seal(plain, code: "K7QM-2XPA-9DRT")
    #expect(a != b)   // fresh salt and nonce each time
    #expect(try crypto.open(a, code: "K7QM-2XPA-9DRT") == plain)
    let bin = try BackupCrypto.unarmor(a)
    #expect(bin.prefix(4) == Data("PLYS".utf8) && bin[4] == 1 && bin[5] == 2)
    #expect(bin.count == 4 + 1 + 1 + 16 + 12 + plain.count + 16)
    func rearm(_ d: Data) -> Data { Data((BackupCrypto.armorLine + "\n" + d.base64EncodedString() + "\n").utf8) }
    for i in [6, 30, 40, bin.count - 1] {   // salt, nonce, ciphertext, tag
        var t = bin; t[i] ^= 0x01
        #expect(throws: BackupCryptoError.wrongCodeOrDamaged) { try crypto.open(rearm(t), code: "K7QM-2XPA-9DRT") }
    }
    var v = bin; v[4] = 2
    #expect(throws: BackupCryptoError.unsupportedVersion(2)) { try crypto.open(rearm(v), code: "K7QM-2XPA-9DRT") }
    #expect(throws: BackupCryptoError.damaged) { try crypto.open(rearm(bin.prefix(40)), code: "K7QM-2XPA-9DRT") }
    #expect(throws: BackupCryptoError.notSealed) { try crypto.open(Data("{}".utf8), code: "K7QM-2XPA-9DRT") }
    #expect(throws: BackupCryptoError.invalidCode) { try crypto.seal(plain, code: "12345") }
    #expect(throws: BackupCryptoError.invalidCode) { try crypto.seal(plain, code: "123456") }
    // Fix round 1: a file of the six-digit draft (key derivation 1) is refused explicitly, also with a valid code.
    var old = bin; old[5] = 1
    #expect(throws: BackupCryptoError.unsupportedCode(1)) { try crypto.open(rearm(old), code: "K7QM-2XPA-9DRT") }
    #expect(throws: BackupCryptoError.invalidCode) { try crypto.open(rearm(old), code: "123456") }
    var other = bin; other[5] = 9
    #expect(throws: BackupCryptoError.unsupportedCode(9)) { try crypto.open(rearm(other), code: "K7QM-2XPA-9DRT") }
}

@Test func plainExportStaysCompatibleWithBuild249() throws {
    let data = try fixture("build249-profiles.json")
    let s = try ProfileStore.decode(data)
    let store = ProfileStore(directory: tempDir())
    #expect(try store.exportData(s, includeSecrets: true) == data)   // full export unchanged, byte for byte
    let plain = try store.exportData(s, includeSecrets: false)
    let back = try store.importData(plain)
    #expect(back.profiles.map(\.id) == s.profiles.map(\.id) && back.profiles[0].collections == s.profiles[0].collections)
    #expect(back.profiles.allSatisfy { $0.apiKeys.isEmpty && $0.syncTokens.isEmpty })
    #expect(back.profiles[0].addons.map(\.manifestURL) == s.profiles[0].addons.map(\.manifestURL))   // no access part there
    // Same keys as build 249 writes (empty maps stay present), so build 249 reads the file.
    let keys = { (d: Data) throws -> [String] in
        let o = try JSONSerialization.jsonObject(with: d) as! [String: Any]
        return ((o["profiles"] as! [[String: Any]])[0]).keys.sorted()
    }
    #expect(try keys(plain) == keys(data))
    #expect(AddonAccess.publicManifestURL("https://u:p@a.example/c/providers=yts|realdebrid=X/manifest.json?v=1#f") == "https://a.example/c/manifest.json")
    #expect(AddonAccess.publicManifestURL("https://a.example/stremio/v1/manifest.json") == "https://a.example/stremio/v1/manifest.json")
    // Fix round 1: a last segment other than manifest.json goes through the same filter as the others.
    #expect(AddonAccess.publicManifestURL("https://a.example/c/FAKE-CONFIG-0009-abcdefghijklmnop") == "https://a.example/c")
    #expect(AddonAccess.publicManifestURL("https://a.example/c/providers=yts|debrid=FAKE-KEY-0010") == "https://a.example/c")
    #expect(AddonAccess.publicManifestURL("https://a.example/stremio/v1/catalog") == "https://a.example/stremio/v1/catalog")
    #expect(AddonAccess.publicManifestURL("https://a.example/FAKE-CONFIG-0011-abcdefghijkl/Manifest.JSON") == "https://a.example/Manifest.JSON")
    #expect(AddonAccess.publicManifestURL("https://a.example/eyJGQUtFLUNPTkZJRy0wMDEyIjp0cnVlfQ") == "https://a.example")
}

@Test func phonePageRoutesForSessionExportAndLockedProfiles() {
    let page = PhoneInputPage()
    let (plain, none) = page.handle(req("GET /export HTTP/1.1\r\n\r\n"), profileName: "Ich") { Data("{}".utf8) }
    #expect(plain.status == 200 && none.isEmpty && plain.extraHeaders["Content-Disposition"]?.contains("player-profile.json") == true)
    let (wait, cmds) = page.handle(req("GET /export?secrets=1 HTTP/1.1\r\n\r\n"), profileName: "Ich") { Data() }
    #expect(wait.status == 200 && cmds == [.exportSecrets] && String(data: wait.body, encoding: .utf8)!.contains(PhoneInputPage.sealedPath))
    let (pending, _) = page.handle(req("GET \(PhoneInputPage.sealedPath) HTTP/1.1\r\n\r\n"), profileName: "Ich") { Data() }
    #expect(pending.status == 200 && pending.contentType.hasPrefix("text/html") && String(data: pending.body, encoding: .utf8)!.contains("refresh"))
    let file = Data("PLAYER-SICHERUNG-1\nAAAA\n".utf8)
    let (ready, _) = page.handle(req("GET \(PhoneInputPage.sealedPath) HTTP/1.1\r\n\r\n"), profileName: "Ich",
                                 backups: PhoneBackupState(sealedFile: file)) { Data() }
    #expect(ready.body == file && ready.extraHeaders["Content-Disposition"]?.contains(BackupCrypto.fileName) == true)
    let (done, doneCmds) = page.handle(req("GET \(PhoneInputPage.sealedPath) HTTP/1.1\r\n\r\n"), profileName: "Ich",
                                       backups: PhoneBackupState(sealedDelivered: true)) { Data() }
    #expect(doneCmds.isEmpty && !String(data: done.body, encoding: .utf8)!.contains("refresh"))
    // Fix round 1: declined, lapsed, refused or failed on the TV – the waiting page ends with a message.
    for o: PhoneSealedOutcome in [.declined, .lapsed, .busy, .failed] {
        let (end, endCmds) = page.handle(req("GET \(PhoneInputPage.sealedPath) HTTP/1.1\r\n\r\n"), profileName: "Ich",
                                         backups: PhoneBackupState(sealedOutcome: o)) { Data() }
        let text = String(data: end.body, encoding: .utf8)!
        #expect(end.status == 200 && endCmds.isEmpty && !text.contains("refresh") && text.contains(PhoneInputPage.escape(o.text)), "\(o)")
    }
    // A file that is ready wins over an older outcome.
    let (again, _) = page.handle(req("GET \(PhoneInputPage.sealedPath) HTTP/1.1\r\n\r\n"), profileName: "Ich",
                                 backups: PhoneBackupState(sealedFile: file, sealedOutcome: .declined)) { Data() }
    #expect(again.body == file)
    // Fix round 1: while a request waits on the TV, the phone hears it at once.
    let waiting = PhoneBackupState(requestOpen: true)
    let (busyExport, busyCmds) = page.handle(req("GET /export?secrets=1 HTTP/1.1\r\n\r\n"), profileName: "Ich", backups: waiting) { Data() }
    let busyText = String(data: busyExport.body, encoding: .utf8)!
    #expect(busyCmds.isEmpty && !busyText.contains("refresh") && busyText.contains("wartet schon"))
    let mixed = "addon=https%3A%2F%2Faddon.example%2Fmanifest.json&tmdb_link=list%3A5"
    let (busySubmit, kept) = page.handle(req("POST /submit HTTP/1.1\r\nContent-Length: \(mixed.utf8.count)\r\n\r\n\(mixed)"),
                                         profileName: "Ich", backups: waiting) { Data() }
    #expect(kept == [.addTMDBLink("list:5")] && busySubmit.extraHeaders["Location"] == "/?ok=1&wt=offen")
    let onlySensitive = "key_tmdb=K"
    let (busyOnly, none2) = page.handle(req("POST /submit HTTP/1.1\r\nContent-Length: \(onlySensitive.utf8.count)\r\n\r\n\(onlySensitive)"),
                                        profileName: "Ich", backups: waiting) { Data() }
    #expect(none2.isEmpty && busyOnly.extraHeaders["Location"] == "/?wt=offen")
    let (busyPage, _) = page.handle(req("GET /?wt=offen HTTP/1.1\r\n\r\n"), profileName: "Ich") { Data() }
    #expect(String(data: busyPage.body, encoding: .utf8)!.contains("wartet schon"))
    let (calm, _) = page.handle(req("GET /?ok=1 HTTP/1.1\r\n\r\n"), profileName: "Ich") { Data() }
    #expect(!String(data: calm.body, encoding: .utf8)!.contains("wartet schon"))
    // Task 1.3 interface: while the profiles are unreadable, no backup leaves and none comes in.
    let locked = PhoneBackupState(blocked: true)
    for path in ["/export", "/export?secrets=1", PhoneInputPage.sealedPath] {
        let (r, c) = page.handle(req("GET \(path) HTTP/1.1\r\n\r\n"), profileName: "Ich", backups: locked) { Data("{}".utf8) }
        #expect(r.status == 409 && c.isEmpty && String(data: r.body, encoding: .utf8)!.contains("nicht lesbar"), "\(path)")
    }
    let body = "backup_json=%7B%7D&key_tmdb=K"
    let (r, c) = page.handle(req("POST /submit HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"), profileName: "Ich", backups: locked) { Data() }
    #expect(c == [.setKey(service: "tmdb", value: "K")] && r.extraHeaders["Location"] == "/?ok=1&bk=gesperrt")
    let (shown, _) = page.handle(req("GET /?ok=1&bk=gesperrt HTTP/1.1\r\n\r\n"), profileName: "Ich", backups: locked) { Data() }
    let html = String(data: shown.body, encoding: .utf8)!
    #expect(html.contains("nicht lesbar") && !html.contains("href=\"/export"))
    // The page itself never carries the token any more.
    let (open, _) = page.handle(req("GET / HTTP/1.1\r\n\r\n"), profileName: "Ich") { Data() }
    let openHTML = String(data: open.body, encoding: .utf8)!
    #expect(openHTML.contains("action=\"/submit\"") && openHTML.contains("/export?secrets=1") && !openHTML.contains("?t="))
}

private func req(_ s: String) -> HTTPRequest {
    guard case .complete(let r) = HTTPRequest.parse(Data(s.utf8)) else { fatalError("parse") }
    return r
}

// MARK: Final review of build 1

@Test func sealedRestoreRequestLastsFiveMinutesOthersOne() throws {
    let sealed = try crypto.seal(Data("{}".utf8), code: "ABCD-EFGH-JKMN")
    #expect(PhoneConfirmGate.lifetime(for: [.importBackup(sealed)]) == 5 * 60)
    #expect(PhoneConfirmGate.lifetime(for: [.addAddon("https://addon.example/manifest.json")]) == 60)
    var g = PhoneConfirmGate()
    _ = g.offer([.importBackup(sealed)], now: t0)
    #expect(g.current(now: t0 + 299)?.needsCode == true)
    #expect(g.current(now: t0 + 299)?.lapseText.contains("fünf Minuten") == true)
    #expect(g.current(now: t0 + 300) == nil)
    _ = g.offer([.addAddon("https://addon.example/manifest.json")], now: t0 + 400)
    #expect(g.current(now: t0 + 459)?.lapseText.contains("einer Minute") == true)
    #expect(g.current(now: t0 + 460) == nil)
}

@Test func wrongBackupCodeKeepsTheRequestOpen() throws {
    let sealed = try crypto.seal(Data("{}".utf8), code: "ABCD-EFGH-JKMN")
    let addon = PhoneCommand.addAddon("https://addon.example/manifest.json")
    var g = PhoneConfirmGate()
    _ = g.offer([.importBackup(sealed), addon], now: t0)
    #expect(g.answer(allow: true, now: t0 + 10) { _ in nil } == .codeRejected)
    #expect(g.current(now: t0 + 11) != nil)   // a typo does not end the request
    let plain = Data("{\"x\":1}".utf8)
    #expect(g.answer(allow: true, now: t0 + 20) { d in d == sealed ? plain : nil } == .allowed([.importBackup(plain), addon]))
    #expect(g.current(now: t0 + 21) == nil)
    _ = g.offer([.importBackup(sealed)], now: t0 + 30)
    #expect(g.answer(allow: false, now: t0 + 31) { _ in Issue.record("not opened on decline"); return nil } == .declined)
    #expect(g.current(now: t0 + 32) == nil)
    _ = g.offer([addon], now: t0 + 40)
    #expect(g.answer(allow: true, now: t0 + 41) { _ in nil } == .allowed([addon]))   // nothing sealed: no code needed
    _ = g.offer([.importBackup(sealed)], now: t0 + 50)
    #expect(g.answer(allow: true, now: t0 + 50 + 300) { _ in plain } == .lapsed)
}

@Test func plainExportDropsDuplicateAndUnreadableAddons() throws {
    let data = try fixture("build249-profiles.json")
    var s = try ProfileStore.decode(data)
    let m = s.profiles[0].addons[0].manifest
    s.profiles[0].addons = [
        InstalledAddon(manifestURL: "https://addon4.example/providers=yts|debrid=FAKE-KEY-0013/manifest.json", manifest: m),
        InstalledAddon(manifestURL: "keine adresse", manifest: m),
        InstalledAddon(manifestURL: "https://addon4.example/providers=eztv|debrid=FAKE-KEY-0014/manifest.json", manifest: m),
        InstalledAddon(manifestURL: "https://addon5.example/manifest.json", manifest: m),
    ]
    let out = s.withoutSecrets()
    #expect(out.profiles[0].addons.map(\.manifestURL) == ["https://addon4.example/manifest.json", "https://addon5.example/manifest.json"])
    let store = ProfileStore(directory: tempDir())
    let file = try store.exportData(s, includeSecrets: false)
    #expect(try store.importData(file).profiles[0].addons.count == 2)
    guard case .needsConfirmation(let summary) = PhoneCommand.importBackup(file).sensitivity else { Issue.record("confirmation"); return }
    #expect(summary.contains("Addons mit Zugangsdaten"))
    guard case .needsConfirmation(let full) = PhoneCommand.importBackup(try store.exportData(s, includeSecrets: true)).sensitivity else { return }
    #expect(!full.contains("Addons mit Zugangsdaten"))
    s.profiles = s.profiles.map { var p = $0; p.addons = []; return p }
    guard case .needsConfirmation(let none) = PhoneCommand.importBackup(try store.exportData(s, includeSecrets: false)).sensitivity else { return }
    #expect(!none.contains("Addons mit Zugangsdaten"))
}

@Test func importOfNewerBuildFileReportsIgnoredValues() throws {
    let json = #"{"schemaVersion":1,"profiles":[{"id":"00000000-0000-4000-8000-000000000001","name":"A","appearance":{"accent":"turquoise"}}]}"#
    let (s, report) = try ProfileStore(directory: tempDir()).importDataReporting(Data(json.utf8))
    #expect(s.profiles.count == 1 && !report.isEmpty)
    #expect(report.ignored.allSatisfy { !$0.contains("turquoise") })   // paths only, no values
}
