import Foundation
import Testing
@testable import PlayerCore

// Welle C-b: Startseite vom Plattencache, Quellen-Cache mit Hintergrund-Erneuerung, Bildgrößen,
// Hänger-Erkennung, Fokus-Gedächtnis.

private func meta(_ id: String) -> MetaPreview { MetaPreview(id: id, type: "movie", name: "Titel \(id)") }

private func entries(_ rows: [String: (count: Int, at: Date)]) -> [String: TimedCache<[MetaPreview]>.Entry] {
    var c = TimedCache<[MetaPreview]>()
    for (k, r) in rows { c.store((0..<r.count).map { meta("\(k)-\($0)") }, for: k, now: r.at) }
    return c.entries
}

// MARK: TimedCache.restore

@Test func timedCacheRestoreMarksForRefreshOnce() {
    var c = TimedCache<[Int]>(lifetime: 100, retryAfter: 10)
    let t0 = Date(timeIntervalSince1970: 1000)
    let ok = c.restore([1], for: "a", storedAt: t0, generation: c.generation); #expect(ok)
    #expect(c["a"] == [1] && !c.isStale("a", now: t0 + 1))
    #expect(c.needsRefresh("a", now: t0 + 1))                 // frisch, aber aus der Platte: einmal erneuern
    c.markFailed("a", now: t0 + 2)
    #expect(!c.needsRefresh("a", now: t0 + 5) && c.needsRefresh("a", now: t0 + 12))
    c.store([2], for: "a", now: t0 + 20)
    #expect(!c.needsRefresh("a", now: t0 + 21))               // nach echter Ablage normaler Ablauf
}

@Test func timedCacheRestoreNeverOverwritesOrCrossesClear() {
    var c = TimedCache<[Int]>()
    c.store([9], for: "a")
    let r1 = c.restore([1], for: "a", storedAt: Date(), generation: c.generation); #expect(!r1)
    #expect(c["a"] == [9])
    let g = c.generation
    c.removeAll()
    let r2 = c.restore([1], for: "b", storedAt: Date(), generation: g); #expect(!r2)   // Profilwechsel dazwischen
    #expect(c["b"] == nil)
}

// MARK: CatalogSnapshot

@Test func catalogSnapshotRoundTripRestoresRows() throws {
    let now = Date(timeIntervalSince1970: 2_000_000)
    let e = entries(["a": (3, now - 60), "b": (0, now), "c": (2, now - 3600)])
    let data = try #require(CatalogSnapshot.encode(entries: e))
    let snap = try #require(CatalogSnapshot.decode(data, now: now))
    #expect(Set(snap.rows.keys) == ["a", "c"])                // leere Reihe nicht gespeichert
    #expect(snap.rows["a"]?.items.count == 3 && snap.rows["a"]?.storedAt == now - 60)
    #expect(snap.oldestAge(now: now) == 3600)
    var cache = TimedCache<[MetaPreview]>()
    let v1 = snap.restore(into: &cache, generation: cache.generation)
    #expect(v1 == 2)
    #expect(cache["a"]?.map(\.id) == ["a-0", "a-1", "a-2"] && cache.needsRefresh("a", now: now))
}

@Test func catalogSnapshotDropsOldFutureAndBroken() throws {
    let now = Date(timeIntervalSince1970: 5_000_000)
    let e = entries(["alt": (2, now - CatalogSnapshot.maxAge - 1), "zukunft": (1, now + 500), "ok": (1, now - 10)])
    let data = try #require(CatalogSnapshot.encode(entries: e))
    let snap = try #require(CatalogSnapshot.decode(data, now: now))
    #expect(Set(snap.rows.keys) == ["zukunft", "ok"])
    #expect(snap.rows["zukunft"]?.storedAt == now)
    #expect(CatalogSnapshot.decode(Data("kaputt".utf8)) == nil)
    var wrong = snap; wrong.version = 99
    let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
    #expect(CatalogSnapshot.decode(try enc.encode(wrong), now: now) == nil)
    #expect(CatalogSnapshot.encode(entries: [:]) == nil)
}

@Test func catalogSnapshotCapsItemsAndSize() throws {
    let now = Date()
    let e = entries(["a": (250, now)])
    let full = try #require(CatalogSnapshot.encode(entries: e))
    let snap = try #require(CatalogSnapshot.decode(full))
    #expect(snap.rows["a"]?.items.count == CatalogSnapshot.maxItemsPerRow)
    // Zu groß: Einträge je Reihe werden halbiert, bis es passt.
    let small = try #require(CatalogSnapshot.encode(entries: e, maxBytes: full.count / 3))
    #expect(small.count <= full.count / 3)
    #expect((CatalogSnapshot.decode(small)?.rows["a"]?.items.count ?? 0) < CatalogSnapshot.maxItemsPerRow)
    #expect(CatalogSnapshot.encode(entries: e, maxBytes: 10) == nil)
}

@Test func catalogSnapshotKeepsNewestRows() {
    let now = Date()
    var rows: [String: (count: Int, at: Date)] = [:]
    for i in 0..<(CatalogSnapshot.maxRows + 5) { rows["r\(i)"] = (1, now - Double(i)) }
    let snap = CatalogSnapshot(entries: entries(rows))
    #expect(snap.rows.count == CatalogSnapshot.maxRows && snap.rows["r0"] != nil && snap.rows["r\(CatalogSnapshot.maxRows + 4)"] == nil)
}

@Test func catalogSnapshotFileNamePerProfile() {
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    #expect(CatalogSnapshot.fileName(profile: id) == "catalog-00000000-0000-0000-0000-000000000001.json")
}

// MARK: RevalidationPolicy

@Test func revalidationPolicyStates() {
    let p = RevalidationPolicy(freshFor: 90, usableFor: 1800)
    #expect(p.state(age: 0) == .fresh && p.state(age: 89) == .fresh)
    #expect(p.state(age: 90) == .stale && p.state(age: 1799) == .stale)
    #expect(p.state(age: 1800) == .expired)
    #expect(p.state(age: -5) == .stale)
    let t = Date(timeIntervalSince1970: 100)
    #expect(p.isUsable(storedAt: t, now: t + 1000) && !p.isUsable(storedAt: t, now: t + 2000))
    #expect(RevalidationPolicy(freshFor: 100, usableFor: 10).usableFor == 100)
    #expect(RevalidationPolicy.streams.freshFor == 90 && RevalidationPolicy.streams.usableFor == 1800)
}

// MARK: ImageTarget / ImageURLVariant

@Test func imageTargetStepsAndZeroSize() {
    #expect(ImageTarget(points: 0, 360, scale: 2, fit: false) == nil)
    #expect(ImageTarget(points: 240, 360, scale: 0, fit: false) == nil)
    let t = ImageTarget(points: 240, 360, scale: 2, fit: false)
    #expect(t == ImageTarget(width: 512, height: 768, fit: false))
    let t2 = ImageTarget(points: 250, 370, scale: 2, fit: false)
    #expect(t2 == ImageTarget(width: 512, height: 768, fit: false))   // gleiche Stufe → gleiches Bitmap
    #expect(ImageTarget(points: 1920, 1080, scale: 2, fit: false) == ImageTarget(width: 3840, height: 2560, fit: false))
    #expect(ImageTarget.step(99_999) == 3840 && ImageTarget.step(1) == 64)
    #expect(t?.cacheKey == "512x768c")
}

@Test func imageTargetDecodeSize() {
    let fill = ImageTarget(width: 512, height: 768, fit: false)
    // Poster 2:3 aus 1000×1500: Fläche füllen → 768 lang
    #expect(fill.decodeMaxPixels(imageWidth: 1000, imageHeight: 1500) == 768)
    // Hintergrund 16:9 in Hochformat-Kachel: Höhe muss decken → 768 hoch, 1366 breit
    #expect(fill.decodeMaxPixels(imageWidth: 1920, imageHeight: 1080) == 1366)
    // Nie größer als das Original
    #expect(fill.decodeMaxPixels(imageWidth: 300, imageHeight: 450) == 450)
    let logo = ImageTarget(width: 1280, height: 384, fit: true)
    #expect(logo.decodeMaxPixels(imageWidth: 2000, imageHeight: 500) == 1280)
    // Alte Aufrufe (Quadrat): längere Seite höchstens maxPixels
    #expect(ImageTarget.square(720).decodeMaxPixels(imageWidth: 2000, imageHeight: 3000) == 720)
    #expect(fill.decodeMaxPixels(imageWidth: 0, imageHeight: 0) == 768)
}

@Test func imageNeededSourceWidth() {
    #expect(ImageTarget(width: 512, height: 768, fit: false).neededSourceWidth == 512)
    #expect(ImageTarget(width: 3840, height: 2560, fit: false).neededSourceWidth == 3840)
    #expect(ImageTarget(width: 256, height: 768, fit: false).neededSourceWidth == 512)
    #expect(ImageTarget(width: 1280, height: 384, fit: true).neededSourceWidth == 1280)
}

@Test func tmdbOriginalIsSizedDown() {
    let o = "https://image.tmdb.org/t/p/original/abc.jpg"
    #expect(ImageURLVariant.candidates(for: o, neededWidth: 480) == ["https://image.tmdb.org/t/p/w500/abc.jpg", o])
    #expect(ImageURLVariant.candidates(for: o, neededWidth: 300) == ["https://image.tmdb.org/t/p/w342/abc.jpg", o])
    #expect(ImageURLVariant.candidates(for: o, neededWidth: 1280) == ["https://image.tmdb.org/t/p/w1280/abc.jpg", o])
    #expect(ImageURLVariant.candidates(for: o, neededWidth: 3840) == [o])                    // 4K-Vollbild: Original
    #expect(ImageURLVariant.candidates(for: "https://image.tmdb.org/t/p/original/l.svg", neededWidth: 300).count == 1)
}

@Test func tmdbSmallSizeUpgradedOnlyWhenNeeded() {
    let w = "https://image.tmdb.org/t/p/w500/p.jpg"
    #expect(ImageURLVariant.candidates(for: w, neededWidth: 480) == [w])
    #expect(ImageURLVariant.candidates(for: w, neededWidth: 700) == ["https://image.tmdb.org/t/p/w780/p.jpg", w])
    #expect(ImageURLVariant.candidates(for: w, neededWidth: 3840) == ["https://image.tmdb.org/t/p/original/p.jpg", w])
    let h = "https://image.tmdb.org/t/p/h632/x.jpg"
    #expect(ImageURLVariant.candidates(for: h, neededWidth: 2000) == [h])
    let small = "https://image.tmdb.org/t/p/w92/x.jpg"
    #expect(ImageURLVariant.candidates(for: small, neededWidth: 200) == ["https://image.tmdb.org/t/p/w342/x.jpg", small])
}

@Test func metahubPosterUpgradedOnly() {
    let m = "https://images.metahub.space/poster/small/tt1234567/img"
    #expect(ImageURLVariant.candidates(for: m, neededWidth: 150) == [m])
    #expect(ImageURLVariant.candidates(for: m, neededWidth: 300) == ["https://images.metahub.space/poster/medium/tt1234567/img", m])
    #expect(ImageURLVariant.candidates(for: m, neededWidth: 512) == ["https://images.metahub.space/poster/large/tt1234567/img", m])
    let l = "https://images.metahub.space/poster/large/tt1/img"
    #expect(ImageURLVariant.candidates(for: l, neededWidth: 3840) == [l])
    let bg = "https://images.metahub.space/background/medium/tt1/img"
    #expect(ImageURLVariant.candidates(for: bg, neededWidth: 3840) == [bg])
    #expect(ImageURLVariant.candidates(for: "https://example.com/a.jpg", neededWidth: 100) == ["https://example.com/a.jpg"])
}

// MARK: HitchDetector

@Test func hitchDetectorReportsGapsOverThreshold() {
    var d = HitchDetector(threshold: 0.25, minInterval: 1)
    let v2 = d.step(at: 10)
    #expect(v2 == nil)                             // erster Schritt: nichts zu messen
    let v3 = d.step(at: 10.1)
    #expect(v3 == nil)
    let h = d.step(at: 10.5)
    #expect(h == HitchDetector.Hitch(milliseconds: 400, suppressed: 0, suppressedMax: 0))
    d.willSleep()
    let v4 = d.step(at: 20)
    #expect(v4 == nil)                             // Schlaf zählt nicht
}

@Test func hitchDetectorRateLimitsAndCountsSuppressed() {
    var d = HitchDetector(threshold: 0.25, minInterval: 1)
    _ = d.step(at: 0)
    let v5 = d.step(at: 0.3)
    #expect(v5?.milliseconds == 300)
    let v6 = d.step(at: 0.6)
    #expect(v6 == nil)                            // zu dicht: gezählt
    let v7 = d.step(at: 1.1)
    #expect(v7 == nil)                            // 500 ms, noch innerhalb 1 s nach Meldung bei 0,3
    let h = d.step(at: 1.5)
    #expect(h == HitchDetector.Hitch(milliseconds: 400, suppressed: 2, suppressedMax: 500))
    #expect(HitchDetector.text(h!, note: "Fokus tt1", footprintMB: 400)
            == "Hauptthread hing 400 ms · zuletzt: Fokus tt1 · belegt 400 MB · dazu 2 weitere (bis 500 ms)")
    #expect(HitchDetector.text(HitchDetector.Hitch(milliseconds: 260, suppressed: 0, suppressedMax: 0), note: nil, footprintMB: nil)
            == "Hauptthread hing 260 ms")
}

// MARK: RowFocusMemory

@Test func rowFocusMemoryIgnoresCoveredPages() {
    var m = RowFocusMemory()
    let v8 = m.record(row: "r1", item: "a")
    #expect(v8)
    m.covered = true
    let v9 = m.record(row: "r1", item: "b")
    #expect(!v9)
    #expect(m.remembered(row: "r1") == "a")
    m.covered = false
    m.record(row: "r1", item: "c")
    #expect(m.remembered(row: "r1", among: ["a", "c"]) == "c")
    #expect(m.remembered(row: "r1", among: ["a"]) == nil)       // Kachel nicht mehr in der Reihe
    m.forget(row: "r1")
    #expect(m.remembered(row: "r1") == nil)
}

@Test func rowFocusMemoryIsBounded() {
    var m = RowFocusMemory()
    for i in 0..<(RowFocusMemory.maxRows + 3) { m.record(row: "r\(i)", item: "x") }
    #expect(m.remembered(row: "r0") == nil && m.remembered(row: "r3") == "x")
    m.record(row: "r3", item: "y")                              // erneute Nutzung: wird jüngste
    for i in 100..<(100 + RowFocusMemory.maxRows - 1) { m.record(row: "r\(i)", item: "x") }
    #expect(m.remembered(row: "r3") == "y")
}
