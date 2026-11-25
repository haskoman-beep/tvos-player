import Foundation
import Testing
@testable import PlayerCore

// Build 4 follow-up S4: `ProgressBook.latest(forItem:)` answers from a per-item index instead of filtering all
// entries (up to ~1500, three calls per new card). Results must equal the old full scan, ties included.

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

/// The rule before S4, kept here as the reference: filter all entries, the first maximum in iteration order wins.
private func scanLatest(_ b: ProgressBook, _ itemID: String) -> WatchProgress? {
    b.entries.values.filter { $0.item.id == itemID }.max { $0.updated < $1.updated }
}

private func expectSameAsScan(_ b: ProgressBook, items: [String], sourceLocation: SourceLocation = #_sourceLocation) {
    for i in items {
        #expect(b.latest(forItem: i) == scanLatest(b, i), "item \(i)", sourceLocation: sourceLocation)
        #expect(b.cardState(itemID: i) == referenceCardState(b, i), "card \(i)", sourceLocation: sourceLocation)
    }
}

/// `cardState` before S4 (same text, reference scan for the series part).
private func referenceCardState(_ b: ProgressBook, _ itemID: String) -> CardState? {
    if let e = b.entries[itemID], e.season == nil {
        if e.finished { return CardState(watched: true) }
        guard e.position >= ProgressBook.minimumSeconds || (e.remoteFraction ?? 0) > 0 else { return nil }
        return CardState(fraction: e.fraction, remainingSeconds: e.duration > 0 ? max(0, e.duration - e.position) : nil)
    }
    guard let e = scanLatest(b, itemID), let s = e.season, let ep = e.episode else { return nil }
    let label = "S\(s) F\(ep)"
    if e.finished { return CardState(episode: label) }
    let started = e.position >= ProgressBook.minimumSeconds || (e.remoteFraction ?? 0) > 0
    return CardState(fraction: started ? e.fraction : nil,
                     remainingSeconds: started && e.duration > 0 ? max(0, e.duration - e.position) : nil, episode: label)
}

/// Small deterministic generator (the tests must not depend on the run).
private struct LCG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

@Test func latestIndexIsBuiltOnceAndRebuiltAfterAMutation() {
    var b = ProgressBook()
    let show = MetaPreview(id: "tt1", type: "series", name: "S")
    for e in 1...40 {
        b.record(id: "tt1:1:\(e)", item: show, season: 1, episode: e, position: 600, duration: 2400,
                 now: t0.addingTimeInterval(Double(e)))
    }
    #expect(b.latest(forItem: "tt1")?.episode == 40)
    let builds = b.latestIndexBuilds
    for _ in 0..<500 { _ = b.latest(forItem: "tt1"); _ = b.latest(forItem: "tt-missing") }
    _ = b.cardState(itemID: "tt1")
    #expect(b.latestIndexBuilds == builds)   // no full scan per lookup
    b.record(id: "tt1:2:1", item: show, season: 2, episode: 1, position: 600, duration: 2400,
             now: t0.addingTimeInterval(100))
    #expect(b.latest(forItem: "tt1")?.season == 2)   // mutation seen
    b.entries["tt1:2:1"] = nil                        // direct write from outside seen too
    #expect(b.latest(forItem: "tt1")?.episode == 40 && b.latest(forItem: "tt1")?.season == 1)
}

@Test func latestIndexOfACopyStaysWithItsOwnEntries() {
    var a = ProgressBook()
    let show = MetaPreview(id: "tt2", type: "series", name: "S")
    a.record(id: "tt2:1:1", item: show, season: 1, episode: 1, position: 600, duration: 2400, now: t0)
    let unbuilt = a                       // copy before any lookup shares the not yet built index
    var b = a
    b.record(id: "tt2:1:2", item: show, season: 1, episode: 2, position: 600, duration: 2400,
             now: t0.addingTimeInterval(10))
    #expect(b.latest(forItem: "tt2")?.episode == 2)
    #expect(a.latest(forItem: "tt2")?.episode == 1)
    #expect(unbuilt.latest(forItem: "tt2")?.episode == 1)
    let built = b                         // copy after the lookup
    b.markUnwatched(itemID: "tt2")
    #expect(b.latest(forItem: "tt2") == nil)
    #expect(built.latest(forItem: "tt2")?.episode == 2)
}

@Test func latestKeepsTheScanTieBreakingForEqualDates() {
    // Many entries of one series with the same date: the old scan kept the first maximum in dictionary order.
    var b = ProgressBook()
    let show = MetaPreview(id: "tt3", type: "series", name: "S")
    for e in 1...60 {
        b.entries["tt3:1:\(e)"] = WatchProgress(id: "tt3:1:\(e)", item: show, season: 1, episode: e,
                                                position: 600, duration: 2400, updated: e % 3 == 0 ? t0.addingTimeInterval(5) : t0)
    }
    expectSameAsScan(b, items: ["tt3", "tt-none"])
    b.entries["tt3:1:3"] = nil
    expectSameAsScan(b, items: ["tt3"])
}

@Test func latestEqualsTheScanThroughRandomMutations() {
    var rng = LCG(state: 42)
    let items = (0..<12).map { i in MetaPreview(id: "tt\(700 + i)", type: i % 3 == 0 ? "movie" : "series", name: "T\(i)") }
    var b = ProgressBook()
    var copies: [ProgressBook] = []
    for step in 0..<1500 {
        let m = items[Int.random(in: 0..<items.count, using: &rng)]
        let movie = m.type == "movie"
        let s = Int.random(in: 1...3, using: &rng), e = Int.random(in: 1...6, using: &rng)
        let id = movie ? m.id : "\(m.id):\(s):\(e)"
        // Few distinct dates, so ties happen often.
        let when = t0.addingTimeInterval(Double(Int.random(in: 0...20, using: &rng)))
        switch Int.random(in: 0..<10, using: &rng) {
        case 0, 1, 2:
            b.record(id: id, item: m, season: movie ? nil : s, episode: movie ? nil : e,
                     position: Double(Int.random(in: 0...2400, using: &rng)), duration: 2400, now: when)
        case 3:
            b.merge(remote: [RemoteProgress(id: id, item: m, season: movie ? nil : s, episode: movie ? nil : e,
                                            fraction: Double(Int.random(in: 1...99, using: &rng)) / 100, updated: when)])
        case 4:
            if !movie { b.recordNextUp(id: id, item: m, season: s, episode: e, now: when) }
        case 5: b.markWatched(item: m, series: !movie, now: when)
        case 6: b.markUnwatched(itemID: m.id)
        case 7: b.removeFromContinueWatching(itemID: m.id)
        case 8:
            b.entries[id] = WatchProgress(id: id, item: m, season: movie ? nil : s, episode: movie ? nil : e,
                                          position: 900, duration: 2400, updated: when)
        default:
            b.markFinished(id: id)
        }
        if step % 50 == 0 { copies.append(b) }
        if step % 7 == 0 { expectSameAsScan(b, items: items.map(\.id)) }
    }
    expectSameAsScan(b, items: items.map(\.id))
    for c in copies { expectSameAsScan(c, items: items.map(\.id)) }
    let p = b.pruned(now: t0, keepFinished: 3)
    expectSameAsScan(p, items: items.map(\.id))
}

@Test func progressBookFormatAndEqualityIgnoreTheIndex() throws {
    var b = ProgressBook()
    let show = MetaPreview(id: "tt4", type: "series", name: "S")
    b.record(id: "tt4:1:1", item: show, season: 1, episode: 1, position: 600, duration: 2400, now: t0)
    var built = b
    _ = built.latest(forItem: "tt4")
    #expect(built == b)
    built.schemaVersion = 1
    #expect(built == b)
    // Stored format unchanged: the same three top-level keys as Build 3, nothing for the index.
    let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = .sortedKeys
    let data = try enc.encode(built)
    let keys = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any]).keys.sorted()
    #expect(keys == ["entries", "schemaVersion"])   // `sources` is nil here and stays out, as before
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    let back = try dec.decode(ProgressBook.self, from: data)
    #expect(back == b && back.latest(forItem: "tt4")?.episode == 1)
    // A Build 3 file (written without the index) reads into a book whose lookups work.
    let build3 = #"{"schemaVersion":1,"entries":{"tt5:1:2":{"id":"tt5:1:2","item":{"id":"tt5","type":"series","name":"X"},"season":1,"episode":2,"position":700,"duration":2400,"updated":"2027-01-15T08:00:00Z","finished":false}}}"#
    let old = try dec.decode(ProgressBook.self, from: Data(build3.utf8))
    #expect(old.latest(forItem: "tt5")?.episode == 2 && old.cardState(itemID: "tt5")?.episode == "S1 F2")
}
