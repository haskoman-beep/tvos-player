import Foundation
import Testing
@testable import PlayerCore

// S3 review (Minor 1): the badge values of a stored list are kept from the store on (`CachedBest`). Reading the list
// later drops kept entries of an addon without answer once their own fetch is `usableFor` old
// (`StreamListMerge.usable`); from then on the kept values are not those of the list any more and must lapse, or a
// tile keeps showing DV/Atmos of sources the list no longer offers.

private func st(_ name: String, _ desc: String = "") -> StreamItem {
    StreamItem(name: name, description: desc, url: "https://x/\(name.hashValue)/\(desc.hashValue)")
}

@Test func cachedBestLapsesWhenKeptEntriesExpireOnRead() throws {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let maxAge = RevalidationPolicy.streams.usableFor
    // Old state, 20 min ago: A with 1080p, B with 2160p DV Atmos.
    let before = t0.addingTimeInterval(-20 * 60)
    let previous: [(addon: String, stream: StreamItem)] = [("A", st("[TB⚡] 1080p", "German")),
                                                          ("B", st("[TB⚡] 2160p", "German DV Atmos"))]
    // New search: A answers, B fails → B's entry is kept with its old fetch time.
    let p = PreparedStreams([("A", [st("[TB⚡] 1080p", "German")])])
    guard case let .store(at, list, fetchedAt) = StreamCacheUpdate.apply(
        fresh: p.list, answered: ["A"], failed: ["B"], previous: (at: before, list: previous),
        previousFetchedAt: ["A": before, "B": before], now: t0) else {
        Issue.record("expected a stored list")
        return
    }
    #expect(list.count == 2)
    let cached = CachedBest(best: try #require(p.best(stored: list)), entries: list.count)
    #expect(cached.best.dolbyVision)
    #expect(cached.best.atmos)

    // Right after the store, reading yields the whole list: the kept values hold.
    let read0 = StreamListMerge.usable(list, fetchedAt: fetchedAt, storedAt: at, now: t0, maxAge: maxAge)
    #expect(cached.isCurrent(usableEntries: read0.count))
    // 9 min later B's fetch is 29 min old: still shown, values hold.
    let read9 = StreamListMerge.usable(list, fetchedAt: fetchedAt, storedAt: at, now: t0.addingTimeInterval(9 * 60), maxAge: maxAge)
    #expect(cached.isCurrent(usableEntries: read9.count))
    // 11 min later it is 31 min old: reading drops it, the kept values lapse; computed again they carry no DV/Atmos.
    let read11 = StreamListMerge.usable(list, fetchedAt: fetchedAt, storedAt: at, now: t0.addingTimeInterval(11 * 60), maxAge: maxAge)
    #expect(read11.count == 1)
    #expect(!cached.isCurrent(usableEntries: read11.count))
    let again = try #require(BestQuality.from(RankedStream.rank(read11)))
    #expect(!again.dolbyVision)
    #expect(!again.atmos)
    #expect(again.resolution == "1080p")
}

@Test func cachedBestOfAFullAnswerHoldsWhileTheListIsUsable() {
    let p = PreparedStreams([("A", [st("[TB⚡] 2160p", "German DV")]), ("B", [st("[RD⚡] 1080p", "English")])])
    let cached = CachedBest(best: p.best!, entries: p.list.count)
    #expect(cached.isCurrent(usableEntries: 2))
    #expect(!cached.isCurrent(usableEntries: 1))
    #expect(!cached.isCurrent(usableEntries: 0))
    #expect(cached == CachedBest(best: p.best!, entries: 2))
}
