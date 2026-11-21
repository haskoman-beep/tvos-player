import Foundation
import Testing
@testable import PlayerCore

// Welle D-b: Nacharbeiten aus Welle C (Profilwechsel, Icon-Satz, lückenhafte Quellen, Sendezeiten).

// MARK: M1 – laufende Abfragen und Profilwechsel

@Test @MainActor func taskSlotsShareRunningTask() async {
    var slots = TaskSlots<Int>()
    let t = Task { 7 }
    let ticket = slots.begin("tt1", t)
    #expect(slots["tt1"] != nil && slots.count == 1)
    #expect(await slots["tt1"]?.value == 7)
    slots.finish("tt1", ticket)
    #expect(slots["tt1"] == nil)
}

@Test @MainActor func taskSlotsResetForgetsOldTasksAndKeepsNewer() async {
    var slots = TaskSlots<String>()
    let epochA = slots.currentEpoch
    let old = slots.begin("tt1", Task { "A" })
    // Profilwechsel: ein neuer Aufruf darf nicht auf die alte Abfrage warten …
    slots.reset()
    #expect(slots["tt1"] == nil)
    #expect(!slots.isCurrent(old) && !slots.isCurrent(epoch: epochA))
    // … startet eine eigene; das späte Ende der alten räumt die neue nicht weg.
    let new = slots.begin("tt1", Task { "B" })
    slots.finish("tt1", old)
    #expect(await slots["tt1"]?.value == "B")
    #expect(slots.isCurrent(new))
    slots.finish("tt1", new)
    #expect(slots.count == 0)
}

// MARK: M2 – erneuter Versuch nach der Sperre

@Test func retryGateStartsRetryOnlyOnce() {
    let t0 = Date()
    var g = FetchRetryGate()
    #expect(!g.retryDue("a", now: t0) && !g.isBlocked("a", now: t0))
    g.failed("a", error: "Nicht erreichbar", now: t0)
    #expect(g.isBlocked("a", now: t0.addingTimeInterval(299)) && g.lastError == "Nicht erreichbar")
    #expect(!g.isBlocked("b", now: t0))
    let later = t0.addingTimeInterval(301)
    #expect(g.retryDue("a", now: later))
    g.begin("a")
    // Läuft: weitere `ensure` dürfen ihn weder abbrechen noch neu starten, gesperrt ist er aber auch nicht.
    #expect(!g.retryDue("a", now: later) && !g.isBlocked("a", now: later))
    g.failed("a", error: "Fehler 500", now: later)
    #expect(g.isBlocked("a", now: later.addingTimeInterval(10)) && !g.retrying)
    g.begin("a"); g.succeeded("a")
    #expect(g.failedKey == nil && !g.retryDue("a", now: later.addingTimeInterval(400)))
}

@Test func retryGateCancelledRetryIsDueAgain() {
    let t0 = Date()
    var g = FetchRetryGate()
    g.failed("a", error: "x", now: t0)
    let later = t0.addingTimeInterval(400)
    g.begin("a")
    // Wechsel auf eine andere Adresse bricht den Versuch ab: zurück auf "a" → sofort neu versuchen.
    g.cancelled(now: later)
    g.begin("b")
    #expect(g.retryDue("a", now: later) && !g.isBlocked("a", now: later))
}

// MARK: M3 – lückenhafter Stand

@Test func partialStaleListAwaitsRefresh() {
    let now = Date()
    let at = RevalidationPolicy.streams.storedAt(now: now, freshFor: AddonSearch.partialCacheSeconds)
    func check(_ partial: Bool, after s: TimeInterval, emptyUntil: Date? = nil, allEmptyAt: Date? = nil) -> Bool {
        StreamCacheUpdate.awaitsPartialRefresh(partial: partial, storedAt: at, emptyUntil: emptyUntil, allEmptyAt: allEmptyAt,
                                               pause: 300, now: now.addingTimeInterval(s))
    }
    #expect(!check(true, after: 30))            // noch frisch
    #expect(check(true, after: 120))            // veraltet, lückenhaft → Erneuerung übernehmen
    #expect(!check(false, after: 120))          // vollständig: alter Stand bleibt unter dem Fokus
    #expect(!check(true, after: 31 * 60))       // abgelaufen: normaler Neuladeweg
    #expect(!check(true, after: 120, emptyUntil: now.addingTimeInterval(200)))
    #expect(!check(true, after: 120, allEmptyAt: now))
}

// MARK: N-M3 – Grenzen während des Downloads

private struct Bytes: AsyncSequence {
    typealias Element = UInt8
    let count: Int
    struct AsyncIterator: AsyncIteratorProtocol {
        var left: Int
        var read: @Sendable () -> Void
        mutating func next() async -> UInt8? {
            guard left > 0 else { return nil }
            left -= 1; read()
            return 0x41
        }
    }
    var read: @Sendable () -> Void = {}
    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(left: count, read: read) }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func add() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

@Test func iconSetDownloadStopsAtLimit() async throws {
    #expect(try await RatingIconSet.collect(Bytes(count: 100), limit: 100).count == 100)
    // Zu groß: bricht beim ersten Byte über der Grenze ab, liest nicht den ganzen Strom.
    let c = Counter()
    await #expect(throws: RatingIconSet.DownloadError.tooLarge) {
        try await RatingIconSet.collect(Bytes(count: 10_000, read: { c.add() }), limit: 100)
    }
    #expect(c.value == 101)
    // Angekündigte Länge über der Grenze: gar nicht erst lesen.
    let d = Counter()
    await #expect(throws: RatingIconSet.DownloadError.tooLarge) {
        try await RatingIconSet.collect(Bytes(count: 10, read: { d.add() }), expectedLength: 1_000, limit: 100)
    }
    #expect(d.value == 0)
}

@Test func iconSetDownloadHasTotalDeadline() async throws {
    #expect(try await RatingIconSet.withDeadline(5) { 3 } == 3)
    let t0 = Date()
    await #expect(throws: RatingIconSet.DownloadError.timedOut) {
        try await RatingIconSet.withDeadline(0.1) {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return 1
        }
    }
    #expect(Date().timeIntervalSince(t0) < 3)
}

// MARK: N-M4 – Vergleich nach Inhalt

@Test func airtimeMergeKeepsOriginalOrder() {
    let a1 = UpcomingEpisode(seriesID: "tta", seriesName: "A", season: 1, episode: 1, airDate: "2026-11-21")
    let b1 = UpcomingEpisode(seriesID: "ttb", seriesName: "B", season: 2, episode: 3, airDate: "2026-11-22")
    let a2 = UpcomingEpisode(seriesID: "tta", seriesName: "A", season: 1, episode: 2, airDate: "2026-11-28")
    let original = [a1, b1, a2]
    // Serie B wird vor A fertig, ohne neue Sendezeit: gleicher Inhalt, also keine Änderung.
    #expect(TVmazeClient.merged(original, updated: [b1, a1, a2]) == original)
    #expect(TVmazeClient.merged(original, updated: []) == original)   // voller TVmaze-Ausfall
    var b1t = b1; b1t.airTime = "03:00"; b1t.airDate = "2026-11-23"
    #expect(TVmazeClient.merged(original, updated: [b1t, a1, a2]) == [a1, b1t, a2])
}

// MARK: N-M5 – kompakter TVmaze-Cache

@Test func tvmazeStoresOnlyCalendarWindow() {
    let now = Date()
    let day: TimeInterval = 24 * 3600
    let s = ["1:1": now.addingTimeInterval(-400 * day), "1:2": now.addingTimeInterval(-day),
             "1:3": now.addingTimeInterval(10 * day), "1:4": now.addingTimeInterval(40 * day)]
    #expect(Set(TVmazeAirtimes.window(s, now: now).keys) == ["1:2", "1:3"])
}

@Test func tvmazeTidyDropsOldEntries() {
    let now = Date()
    let day: TimeInterval = 24 * 3600
    var d = TVmazeAirtimes.Disk()
    d.missing = ["tt1": now.addingTimeInterval(-8 * day), "tt2": now.addingTimeInterval(-day)]
    d.stamps = ["1": .init(at: now.addingTimeInterval(-8 * day), ttl: 3600, value: [:]),
                "2": .init(at: now, ttl: 3600, value: [:])]
    for i in 0..<(TVmazeAirtimes.maxIDs + 20) { d.ids["tt\(1000 + i)"] = 5000 + i }
    d.ids["tt2"] = 2
    let t = TVmazeAirtimes.tidy(d, now: now)
    #expect(Array(t.missing.keys) == ["tt2"])
    #expect(Array(t.stamps.keys) == ["2"])
    #expect(t.ids == ["tt2": 2])   // zu viele IDs: nur die mit Zeitpunkten im Cache
    // Unter der Grenze bleiben IDs dauerhaft.
    var small = TVmazeAirtimes.Disk(); small.ids = ["tt9": 9]
    #expect(TVmazeAirtimes.tidy(small, now: now).ids == ["tt9": 9])
}

@Test func tvmazeWritesOncePerPass() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tvmaze-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("tvmaze.json")
    let soon = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
    let http = FakeSender([(200, #"{"id":1}"#), (200, #"[{"season":1,"number":1,"airstamp":"\#(soon)"}]"#),
                           (200, #"{"id":2}"#), (200, #"[{"season":1,"number":1,"airstamp":"\#(soon)"}]"#)])
    let a = TVmazeAirtimes(client: TVmazeClient(http: http, sleep: { _ in }), file: file)
    _ = await a.stamps(imdb: "tt1")
    _ = await a.stamps(imdb: "tt2")
    #expect(!FileManager.default.fileExists(atPath: file.path))   // noch nichts geschrieben
    await a.flush()
    let d = try JSONDecoder().decode(TVmazeAirtimes.Disk.self, from: Data(contentsOf: file))
    #expect(d.ids == ["tt1": 1, "tt2": 2] && d.stamps.count == 2)
    try? FileManager.default.removeItem(at: dir)
}
