import Foundation
import Testing
@testable import PlayerCore

// Build 4 follow-up S3: a finished source search is prepared off the main thread (`PreparedStreams`: playable
// entries, parsed traits, best values); storing it on the main thread parses only entries kept from the old state.
// Slow stores leave a rate-limited log line (`StreamStoreCost`). Results must equal the old main-thread path exactly.

private func st(_ name: String, _ desc: String = "", url: String? = "auto") -> StreamItem {
    StreamItem(name: name, description: desc, url: url == "auto" ? "https://x/\(name.hashValue)/\(desc.hashValue)" : url)
}

/// The old path: `playableStreams` per addon, labelled, then `BestQuality.from(RankedStream.rank(list))`.
private func oldList(_ r: [(addon: String, streams: [StreamItem])]) -> [(addon: String, stream: StreamItem)] {
    r.flatMap { a in playableStreams(a.streams).map { (addon: a.addon, stream: $0) } }
}

private func oldBest(_ l: [(addon: String, stream: StreamItem)]) -> BestQuality? { BestQuality.from(RankedStream.rank(l)) }

private func same(_ a: [(addon: String, stream: StreamItem)], _ b: [(addon: String, stream: StreamItem)]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { $0.addon == $1.addon && $0.stream == $1.stream }
}

private let results: [(addon: String, streams: [StreamItem])] = [
    ("A", [st("[TB⚡] 1080p", "German DD5.1"), st("Fehler", "Addon kaputt", url: nil), st("[RD⚡] 720p", "Multi AAC")]),
    ("B", []),
    ("C", [st("[TB⚡] 2160p", "German DV HDR10 DDP5.1 Atmos"), st("[TB⏳] 2160p", "English REMUX DTS-HD MA 7.1")]),
]

@Test func preparedStreamsKeepsOnlyPlayableEntriesInAddonOrder() {
    let p = PreparedStreams(results)
    #expect(same(p.list, oldList(results)))
    #expect(p.list.map(\.addon) == ["A", "A", "C", "C"])
    #expect(p.traits == p.list.map { StreamTraits.parse($0.stream) })
    #expect(PreparedStreams([]).list.isEmpty)
    #expect(PreparedStreams([]).best == nil)
}

@Test func preparedBestEqualsTheOldMainThreadResult() {
    let p = PreparedStreams(results)
    #expect(p.best == oldBest(oldList(results)))
    #expect(p.best?.resolution == "2160p")
    #expect(p.best?.dolbyVision == true)
    // Stored list equal to the fresh one (no addon failed): the precomputed values.
    #expect(p.best(stored: p.list) == p.best)
}

@Test func storedListWithKeptEntriesEqualsFullParse() {
    let p = PreparedStreams([("A", [st("[TB⚡] 1080p", "German")])])
    let kept: [(addon: String, stream: StreamItem)] = [("B", st("[TB⚡] 2160p", "German DV Atmos"))]
    let stored = p.list + kept
    #expect(p.best(stored: stored) == oldBest(stored))
    #expect(p.best(stored: stored)?.resolution == "2160p")
    #expect(p.best(stored: stored)?.atmos == true)
}

/// The rule „uncached sources count only without other ones“ spans fresh and kept entries together.
@Test func keptCachedEntryHidesUncachedFreshOnes() {
    let p = PreparedStreams([("A", [st("[TB⏳] 2160p", "German DV")])])
    let kept: [(addon: String, stream: StreamItem)] = [("B", st("[TB⚡] 1080p", "German"))]
    let stored = p.list + kept
    #expect(p.best?.resolution == "2160p")
    #expect(p.best(stored: stored) == oldBest(stored))
    #expect(p.best(stored: stored)?.resolution == "1080p")
    #expect(p.best(stored: stored)?.dolbyVision == false)
}

/// A stored list that does not begin with the fresh entries (never produced by `StreamListMerge`) is parsed whole.
@Test func storedListInOtherOrderFallsBackToFullParse() {
    let p = PreparedStreams(results)
    let reversed = Array(p.list.reversed())
    #expect(p.best(stored: reversed) == oldBest(reversed))
    let shorter = Array(p.list.prefix(1))
    #expect(p.best(stored: shorter) == oldBest(shorter))
    #expect(p.best(stored: []) == nil)
}

// MARK: Main-thread cost of storing

@Test func fastStoreLogsNothing() {
    var c = StreamStoreCost()
    #expect(c.note(entries: 40, seconds: 0.0079, at: 100) == nil)
    #expect(c.note(entries: 40, seconds: 0, at: 101) == nil)
}

@Test func slowStoreLogsOneLineWithEntriesAndMilliseconds() {
    var c = StreamStoreCost()
    #expect(c.note(entries: 42, seconds: 0.0123, at: 100) == "Quellen abgelegt: 42 Einträge, Hauptthread 12 ms")
    #expect(StreamStoreCost.threshold == 0.008)
    #expect(c.note(entries: 1, seconds: 0.008, at: 200) == "Quellen abgelegt: 1 Einträge, Hauptthread 8 ms")
}

@Test func slowStoresInsideTheIntervalAreCountedIntoTheNextLine() {
    var c = StreamStoreCost(minInterval: 10)
    #expect(c.note(entries: 10, seconds: 0.010, at: 100) != nil)
    #expect(c.note(entries: 11, seconds: 0.030, at: 103) == nil)
    #expect(c.note(entries: 12, seconds: 0.020, at: 109.9) == nil)
    #expect(c.note(entries: 5, seconds: 0.001, at: 109.95) == nil)   // fast, inside the interval: neither line nor count
    #expect(c.note(entries: 13, seconds: 0.009, at: 111) == "Quellen abgelegt: 13 Einträge, Hauptthread 9 ms · dazu 2 weitere (bis 30 ms)")
    #expect(c.note(entries: 14, seconds: 0.015, at: 122) == "Quellen abgelegt: 14 Einträge, Hauptthread 15 ms")
}

/// S3 review (Minor 2): a burst of slow stores followed only by fast ones is not lost: the first store after the
/// interval, fast or slow, brings the counted ones out.
@Test func countedSlowStoresAreFlushedByALaterFastStore() {
    var c = StreamStoreCost(minInterval: 10)
    #expect(c.note(entries: 10, seconds: 0.010, at: 100) != nil)
    #expect(c.note(entries: 11, seconds: 0.030, at: 103) == nil)
    #expect(c.note(entries: 12, seconds: 0.020, at: 105) == nil)
    #expect(c.note(entries: 5, seconds: 0.001, at: 108) == nil)   // fast, inside the interval
    #expect(c.note(entries: 5, seconds: 0.001, at: 110.5) == "Quellen abgelegt: Nachtrag · dazu 2 weitere (bis 30 ms)")
    #expect(c.note(entries: 5, seconds: 0.001, at: 125) == nil)   // nothing counted any more
    // The flush counts as a line: the next slow store inside its interval is counted again.
    var d = StreamStoreCost(minInterval: 10)
    _ = d.note(entries: 10, seconds: 0.010, at: 100)
    _ = d.note(entries: 11, seconds: 0.012, at: 101)
    #expect(d.note(entries: 5, seconds: 0, at: 115) == "Quellen abgelegt: Nachtrag · dazu 1 weitere (bis 12 ms)")
    #expect(d.note(entries: 12, seconds: 0.020, at: 120) == nil)
    #expect(d.note(entries: 13, seconds: 0.009, at: 126) == "Quellen abgelegt: 13 Einträge, Hauptthread 9 ms · dazu 1 weitere (bis 20 ms)")
}
