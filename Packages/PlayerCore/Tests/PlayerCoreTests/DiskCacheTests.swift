import Foundation
import Testing
@testable import PlayerCore

// MARK: Range

@Test func rangeParsesClosedOpenAndSuffix() {
    #expect(HTTPByteRangeRequest.parse("bytes=0-99", total: 1000) == .partial(0...99))
    #expect(HTTPByteRangeRequest.parse("bytes=500-", total: 1000) == .partial(500...999))
    #expect(HTTPByteRangeRequest.parse("bytes=-100", total: 1000) == .partial(900...999))
    #expect(HTTPByteRangeRequest.parse("bytes=1-1", total: 1000) == .partial(1...1))
    #expect(HTTPByteRangeRequest.parse("Bytes = 10 - 20 ", total: 1000) == .full)   // „Bytes =“ ist kein gültiger Präfix
    #expect(HTTPByteRangeRequest.parse("bytes= 10 - 20", total: 1000) == .partial(10...20))
}

@Test func rangeClampsAndRejects() {
    #expect(HTTPByteRangeRequest.parse("bytes=900-5000", total: 1000) == .partial(900...999))
    #expect(HTTPByteRangeRequest.parse("bytes=-5000", total: 1000) == .partial(0...999))
    #expect(HTTPByteRangeRequest.parse("bytes=1000-", total: 1000) == .unsatisfiable)
    #expect(HTTPByteRangeRequest.parse("bytes=-0", total: 1000) == .unsatisfiable)
    #expect(HTTPByteRangeRequest.parse("bytes=0-", total: 0) == .unsatisfiable)
    #expect(HTTPByteRangeRequest.parse(nil, total: 1000) == .full)
    #expect(HTTPByteRangeRequest.parse("items=0-5", total: 1000) == .full)
    #expect(HTTPByteRangeRequest.parse("bytes=20-10", total: 1000) == .full)
    #expect(HTTPByteRangeRequest.parse("bytes=abc", total: 1000) == .full)
    // Mehrere Bereiche: nur der erste.
    #expect(HTTPByteRangeRequest.parse("bytes=0-9, 50-59", total: 1000) == .partial(0...9))
}

@Test func contentRangeParses() {
    #expect(HTTPContentRange.parse("bytes 0-0/1234") == HTTPContentRange(range: 0...0, total: 1234))
    #expect(HTTPContentRange.parse("bytes 100-199/*") == HTTPContentRange(range: 100...199, total: nil))
    #expect(HTTPContentRange.parse("bytes */1234") == HTTPContentRange(range: nil, total: 1234))
    #expect(HTTPContentRange.parse("bytes 0-1234/1234") == nil)   // Ende hinter der Größe
    #expect(HTTPContentRange.parse("bytes 9-3/100") == nil)
    #expect(HTTPContentRange.parse("bytes */*") == nil)
    #expect(HTTPContentRange.parse("0-1/2") == nil)
    #expect(HTTPContentRange.parse(nil) == nil)
    #expect(HTTPContentRange(range: 5...9, total: 10).headerValue == "bytes 5-9/10")
    #expect(HTTPContentRange(range: nil, total: 10).headerValue == "bytes */10")
}

// MARK: Blockplan

@Test func blockPlanMath() {
    let p = DiskCacheBlockPlan(blockSize: 100, totalLength: 1050)
    #expect(p.blockCount == 11)
    #expect(p.block(at: 0) == 0)
    #expect(p.block(at: 99) == 0)
    #expect(p.block(at: 100) == 1)
    #expect(p.block(at: 1049) == 10)
    #expect(p.block(at: 99_999) == 10)   // geklemmt
    #expect(p.range(of: 10) == 1000...1049)
    #expect(p.length(of: 10) == 50)
    #expect(p.blocks(covering: 150...420) == 1...4)
    #expect(p.slice(of: 1, within: 150...420) == 50..<100)
    #expect(p.slice(of: 4, within: 150...420) == 0..<21)
    #expect(p.slice(of: 2, within: 150...420) == 0..<100)
    #expect(p.slice(of: 5, within: 150...420) == nil)
    #expect(DiskCacheBlockPlan(blockSize: 100, totalLength: 0).blockCount == 0)
    #expect(DiskCacheBlockPlan(blockSize: 100, totalLength: 100).blockCount == 1)
}

// MARK: Vorlauf und Verdrängung

@Test func prefetchPicksNearestMissingInWindow() {
    var i = DiskCacheIndex(plan: DiskCacheBlockPlan(blockSize: 100, totalLength: 2000))
    i.insert(5); i.insert(6)
    #expect(i.nextPrefetch(readPosition: 520, aheadBytes: 400, excluding: []) == 7)
    #expect(i.nextPrefetch(readPosition: 520, aheadBytes: 400, excluding: [7]) == 8)
    #expect(i.nextPrefetch(readPosition: 520, aheadBytes: 400, excluding: [7, 8]) == 9)
    #expect(i.nextPrefetch(readPosition: 520, aheadBytes: 400, excluding: [7, 8, 9]) == nil)   // Fenster 5…9 (520…919) voll/belegt
    #expect(i.nextPrefetch(readPosition: 1990, aheadBytes: 1000, excluding: []) == 19)       // Dateiende
    i.insert(19)
    #expect(i.nextPrefetch(readPosition: 1990, aheadBytes: 1000, excluding: []) == nil)
    #expect(i.nextPrefetch(readPosition: 0, aheadBytes: 0, excluding: []) == nil)
}

@Test func indexIgnoresBlocksOutsidePlan() {
    var i = DiskCacheIndex(plan: DiskCacheBlockPlan(blockSize: 100, totalLength: 250))
    i.insert(3); i.insert(-1); i.insert(2)
    #expect(i.cached == [2])
    #expect(i.cachedBytes == 50)
}

@Test func evictionFarBehindFirstThenFarAhead() {
    var i = DiskCacheIndex(plan: DiskCacheBlockPlan(blockSize: 100, totalLength: 10_000))
    for b in [0, 1, 40, 45, 48, 50, 51, 52, 90, 95] { i.insert(b) }
    // Leser bei Block 50, Rückfenster 3 Blöcke, Vorlauf 5 Blöcke. Budget 6 Blöcke → 4 müssen weg.
    let v = i.evictionVictims(budgetBytes: 600, readPosition: 5_000, aheadBytes: 500, backWindowBytes: 300)
    #expect(v == [0, 1, 40, 45])
    // Noch knapper: danach weit voraus (90), dann im Rückfenster (48), dann im Vorlauf (fernster zuerst).
    let w = i.evictionVictims(budgetBytes: 200, readPosition: 5_000, aheadBytes: 500, backWindowBytes: 300)
    #expect(w == [0, 1, 40, 45, 95, 90, 48, 52])
    #expect(!w.contains(50))   // Block an der Leseposition bleibt
}

@Test func evictionKeepsProtectedAndStopsWithinBudget() {
    var i = DiskCacheIndex(plan: DiskCacheBlockPlan(blockSize: 100, totalLength: 1000))
    for b in 0..<10 { i.insert(b) }
    #expect(i.evictionVictims(budgetBytes: 1000, readPosition: 0, aheadBytes: 300, backWindowBytes: 0).isEmpty)
    let v = i.evictionVictims(budgetBytes: 700, readPosition: 0, aheadBytes: 300, backWindowBytes: 0, protected: [9])
    #expect(v == [8, 7, 6])
    // Letzter Block ist kürzer: die Byte-Rechnung zählt echte Längen.
    var j = DiskCacheIndex(plan: DiskCacheBlockPlan(blockSize: 100, totalLength: 950))
    for b in 0..<10 { j.insert(b) }
    #expect(j.cachedBytes == 950)
    #expect(j.evictionVictims(budgetBytes: 900, readPosition: 0, aheadBytes: 100, backWindowBytes: 0) == [9])
}

// MARK: Platz

@Test func budgetFollowsFreeSpace() {
    let gb: Int64 = 1_000_000_000
    // Viel frei: Einstellung zählt.
    #expect(DiskCacheBudget.limit(settingBytes: 8 * gb, freeBytes: 100 * gb, ownBytes: 0, reserve: 2 * gb) == 8 * gb)
    // Wenig frei: nie unter 2 GB Rest; eigene Belegung zählt als verfügbar.
    #expect(DiskCacheBudget.limit(settingBytes: 8 * gb, freeBytes: 5 * gb, ownBytes: 0, reserve: 2 * gb) == 3 * gb)
    #expect(DiskCacheBudget.limit(settingBytes: 8 * gb, freeBytes: 1 * gb, ownBytes: 2 * gb, reserve: 2 * gb) == 1 * gb)
    #expect(DiskCacheBudget.limit(settingBytes: 8 * gb, freeBytes: 1 * gb, ownBytes: 0, reserve: 2 * gb) == 0)
    #expect(DiskCacheBudget.limit(settingBytes: 8 * gb, freeBytes: nil, ownBytes: 0, reserve: 2 * gb) == 0)
    #expect(DiskCacheBudget.mayWrite(blockBytes: 4, freeBytes: 2 * gb + 4, reserve: 2 * gb))
    #expect(!DiskCacheBudget.mayWrite(blockBytes: 5, freeBytes: 2 * gb + 4, reserve: 2 * gb))
    #expect(!DiskCacheBudget.mayWrite(blockBytes: 1, freeBytes: nil, reserve: 0))
}

@Test func policyReadAheadIsAtMostHalfTheBudget() {
    let p = DiskCachePolicy()
    #expect(p.readAhead(budget: 8_000_000_000) == p.readAheadBytes)
    #expect(p.readAhead(budget: 200 * 1024 * 1024) == 100 * 1024 * 1024)
    #expect(p.readAhead(budget: 1) == p.blockSize)
}

// MARK: Quelle

@Test func sourceDecision() {
    let u = { (s: String) in URL(string: s)! }
    #expect(DiskCacheSource.decide(u("https://cdn.example.com/a/Film.2020.mkv?token=x"), nativeHLS: false) == .cache)
    #expect(DiskCacheSource.decide(u("https://cdn.example.com/a/film.MP4"), nativeHLS: false) == .cache)
    #expect(DiskCacheSource.decide(u("https://cdn.example.com/a/master.m3u8"), nativeHLS: false) == .bypass("HLS/DASH"))
    #expect(DiskCacheSource.decide(u("https://cdn.example.com/a/film.mkv"), nativeHLS: true) == .bypass("HLS"))
    #expect(DiskCacheSource.decide(u("https://cdn.example.com/dl/12345"), nativeHLS: false) == .checkContentType)
    #expect(DiskCacheSource.decide(u("http://127.0.0.1:8080/x.mkv"), nativeHLS: false) == .bypass("lokal"))
    #expect(DiskCacheSource.decide(u("file:///tmp/x.mkv"), nativeHLS: false) == .bypass("kein http"))
}

@Test func contentTypesAndProxyName() {
    #expect(DiskCacheSource.contentTypeAllowed("video/x-matroska"))
    #expect(DiskCacheSource.contentTypeAllowed("application/octet-stream"))
    #expect(DiskCacheSource.contentTypeAllowed("video/mp4; charset=binary"))
    #expect(!DiskCacheSource.contentTypeAllowed("application/vnd.apple.mpegurl"))
    #expect(!DiskCacheSource.contentTypeAllowed("text/html"))
    #expect(!DiskCacheSource.contentTypeAllowed(nil))
    let u = URL(string: "https://cdn.example.com/a/Geheimer.Name.mkv")!
    #expect(DiskCacheSource.proxyFileName(for: u, contentType: nil) == "media.mkv")
    let n = URL(string: "https://cdn.example.com/dl/123")!
    #expect(DiskCacheSource.proxyFileName(for: n, contentType: "video/x-matroska") == "media.mkv")
    #expect(DiskCacheSource.proxyFileName(for: n, contentType: "video/mp4") == "media.mp4")
    #expect(DiskCacheSource.proxyFileName(for: n, contentType: "application/octet-stream") == "media")
}

// MARK: Kopfzeilen

@Test func responseHeads() {
    let h = DiskCacheHTTP.mediaHead(status: 206, contentType: "video/x-matroska", range: 100...199, total: 1000)
    #expect(h.hasPrefix("HTTP/1.1 206 Partial Content\r\n"))
    #expect(h.contains("Content-Length: 100\r\n"))
    #expect(h.contains("Content-Range: bytes 100-199/1000\r\n"))
    #expect(h.contains("Accept-Ranges: bytes\r\n"))
    #expect(h.hasSuffix("\r\n\r\n"))
    let f = DiskCacheHTTP.mediaHead(status: 200, contentType: "video/mp4", range: nil, total: 1000)
    #expect(f.contains("Content-Length: 1000\r\n"))
    #expect(!f.contains("Content-Range"))
    let r = DiskCacheHTTP.plainHead(status: 307, headers: [("Location", "https://cdn.example.com/a.mkv")])
    #expect(r.hasPrefix("HTTP/1.1 307 Temporary Redirect\r\n"))
    #expect(r.contains("Location: https://cdn.example.com/a.mkv\r\n"))
    #expect(DiskCacheHTTP.token(fromPath: "/c/ABC/media.mkv") == "ABC")
    #expect(DiskCacheHTTP.token(fromPath: "/x/ABC/media.mkv") == nil)
    #expect(DiskCacheHTTP.token(fromPath: "/c") == nil)
}

// MARK: Einstellung

@Test func diskCacheSettingsDefaultsAndOldProfiles() throws {
    #expect(DiskCacheSettings().enabled == false)
    #expect(DiskCacheSettings().limitGB == 8)
    #expect(DiskCacheSettings(limitGB: 16).limitBytes == 16_000_000_000)
    let s = try JSONDecoder().decode(DiskCacheSettings.self, from: Data("{}".utf8))
    #expect(s == DiskCacheSettings())
    // Altes Profil ohne Feld lädt mit Standard (aus).
    let old = try JSONEncoder().encode(Profile(name: "A"))
    var obj = try JSONSerialization.jsonObject(with: old) as! [String: Any]
    obj.removeValue(forKey: "diskCache")
    let p = try JSONDecoder().decode(Profile.self, from: JSONSerialization.data(withJSONObject: obj))
    #expect(p.diskCache == DiskCacheSettings())
    var on = Profile(name: "B"); on.diskCache = DiskCacheSettings(enabled: true, limitGB: 32)
    let back = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(on))
    #expect(back.diskCache.enabled && back.diskCache.limitGB == 32)
}
