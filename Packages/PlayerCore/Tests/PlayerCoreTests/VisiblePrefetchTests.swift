import Foundation
import Testing
@testable import PlayerCore

// Wave F-k R1: quiet source prefetch for visible poster tiles – queue, dedupe, cancel, limits, log counts.

private let t0 = Date(timeIntervalSince1970: 1_000_000)
private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

/// Plan with the given tiles visible in `row` at t0.
private func plan(_ tiles: [String], row: String = "A", limits: VisiblePrefetchPlan.Limits = .init(),
                  budget: PrefetchBudget = .init()) -> VisiblePrefetchPlan {
    var p = VisiblePrefetchPlan(limits: limits, budget: budget)
    for t in tiles { _ = p.setTile(t, row: row, visible: true, now: t0) }
    return p
}

@Test func visiblePrefetchWaitsForDebounce() {
    var p = plan(["a", "b"])
    // Scrolling: nothing starts before 400 ms of quiet.
    #expect(p.pass(now: at(0.2)) { _ in .needed }.isEmpty)
    _ = p.setTile("c", row: "A", visible: true, now: at(0.3))
    #expect(p.pass(now: at(0.6)) { _ in .needed }.isEmpty)
    #expect(p.pass(now: at(0.8)) { _ in .needed } == ["a", "b", "c"])
}

@Test func visiblePrefetchLimitsRunningAndQueues() {
    var p = plan(["a", "b", "c", "d", "e", "f"])
    // At most 4 at once, screen order; the rest waits.
    #expect(p.pass(now: at(1)) { _ in .needed } == ["a", "b", "c", "d"])
    #expect(p.queuedCount == 2)
    #expect(p.pass(now: at(1.1)) { _ in .needed }.isEmpty)   // no free slot
    p.finished("a", outcome: .loaded, now: at(3))
    #expect(p.pass(now: at(3)) { _ in .needed } == ["e"])
    #expect(p.queuedCount == 1)
}

@Test func visiblePrefetchPerMinuteLimit() {
    let limits = VisiblePrefetchPlan.Limits(maxRunning: 10)
    var p = plan(["a", "b", "c", "d"], limits: limits, budget: PrefetchBudget(perMinute: 3, focusReserve: 0))
    #expect(p.pass(now: at(1)) { _ in .needed } == ["a", "b", "c"])
    for t in ["a", "b", "c"] { p.finished(t, outcome: .loaded, now: at(2)) }
    // Bucket empty: d waits; with nothing running the app needs the time of the next free start.
    #expect(p.pass(now: at(2)) { _ in .needed }.isEmpty)
    #expect(p.nextStartAt(now: at(2)) == at(61))
    #expect(p.pass(now: at(61)) { _ in .needed } == ["d"])
}

@Test func visiblePrefetchDedupesAcrossRowsAndSkipsKnown() {
    var p = plan(["a", "b"], row: "A")
    _ = p.setTile("b", row: "B", visible: true, now: t0)
    _ = p.setTile("c", row: "B", visible: true, now: t0)
    // Row B changed last → first; b only once; known and busy tiles do not start.
    let started = p.pass(now: at(1)) { t in t == "c" ? .known : (t == "a" ? .busy : .needed) }
    #expect(started == ["b"])
    p.finished("b", outcome: .loaded, now: at(2))
    // Done within the cache lifetime: never again, even if the cache dropped it (state needed again).
    #expect(p.pass(now: at(3)) { $0 == "c" ? .known : .needed } == ["a"])
    #expect(!p.isRunning("b"))
    // After the source cache lifetime it may run again.
    p.finished("a", outcome: .loaded, now: at(4))
    #expect(p.pass(now: at(4 + 30 * 60)) { $0 == "c" ? .known : .needed }.sorted() == ["a", "b"])
}

@Test func visiblePrefetchCancelsTilesLeavingTheScreen() {
    var p = plan(["a", "b", "c", "d", "e"])
    #expect(p.pass(now: at(1)) { _ in .needed } == ["a", "b", "c", "d"])
    // Queued e leaves: dropped, nothing to cancel in the app.
    #expect(p.setTile("e", row: "A", visible: false, now: at(2)).isEmpty)
    #expect(p.queuedCount == 0)
    // Running a leaves: the app cancels its job.
    #expect(p.setTile("a", row: "A", visible: false, now: at(2)) == ["a"])
    // Still visible in another row: no cancel.
    _ = p.setTile("b", row: "B", visible: true, now: at(2))
    #expect(p.setTile("b", row: "A", visible: false, now: at(2)).isEmpty)
    p.finished("a", outcome: .cancelled, now: at(2.1))
    #expect(!p.isRunning("a"))
    // A cancelled tile is fetched again when it comes back.
    _ = p.setTile("a", row: "A", visible: true, now: at(3))
    #expect(p.pass(now: at(4)) { $0 == "a" ? .needed : .known } == ["a"])
}

@Test func visiblePrefetchRowReportsWhenSettled() {
    var p = plan(["a", "b", "c", "d", "e", "f"])
    _ = p.pass(now: at(1)) { t in t == "f" ? .known : .needed }   // a-d run, e queued, f known
    #expect(p.reports().isEmpty)                                   // row still busy
    _ = p.setTile("e", row: "A", visible: false, now: at(2))      // queued → cancelled
    for t in ["a", "b", "c"] { p.finished(t, outcome: .loaded, now: at(3)) }
    #expect(p.reports().isEmpty)
    p.finished("d", outcome: .unavailable, now: at(3))
    let r = p.reports()
    #expect(r.count == 1)
    #expect(r.first?.row == "A")
    #expect(r.first?.tally == VisiblePrefetchPlan.Tally(loaded: 3, cached: 1, cancelled: 1))
    #expect(r.first?.tally.logLine(row: "Trending") == "Vorab-Quellen: Trending 3 geladen, 1 aus Cache, 1 abgebrochen")
    // Unchanged: no second line.
    _ = p.pass(now: at(4)) { _ in .known }
    #expect(p.reports().isEmpty)
}

@Test func visiblePrefetchForgetsRowAfterItLeaves() {
    var p = plan(["a"])
    _ = p.pass(now: at(1)) { _ in .known }
    #expect(p.reports().first?.tally == VisiblePrefetchPlan.Tally(cached: 1))
    _ = p.setTile("a", row: "A", visible: false, now: at(2))
    _ = p.reports()
    // Next visit counts from scratch.
    _ = p.setTile("a", row: "A", visible: true, now: at(3))
    _ = p.pass(now: at(4)) { _ in .known }
    #expect(p.reports().first?.tally == VisiblePrefetchPlan.Tally(cached: 1))
}

@Test func prefetchTargetForMoviesAndSeries() {
    let show = MetaPreview(id: "tt9", type: "series", name: "Serie")
    #expect(PrefetchTarget.streamID(type: "movie", imdb: "tt1", progress: nil) == "tt1")
    #expect(PrefetchTarget.streamID(type: "movie", imdb: nil, progress: nil) == nil)
    // Series without progress: S1E1.
    #expect(PrefetchTarget.streamID(type: "series", imdb: "tt9", progress: nil) == "tt9:1:1")
    // Started episode wins.
    let started = WatchProgress(id: "tt9:2:3", item: show, season: 2, episode: 3, position: 100, duration: 2400)
    #expect(PrefetchTarget.streamID(type: "series", imdb: "tt9", progress: started) == "tt9:2:3")
    #expect(PrefetchTarget.streamID(type: "series", imdb: nil, progress: started) == "tt9:2:3")
    // Finished episode: back to S1E1 (no episode list request).
    var ended = started
    ended.finished = true
    #expect(PrefetchTarget.streamID(type: "series", imdb: "tt9", progress: ended) == "tt9:1:1")
    #expect(PrefetchTarget.streamID(type: "series", imdb: nil, progress: ended) == nil)
    #expect(PrefetchTarget.streamID(type: "channel", imdb: "tt1", progress: nil) == nil)
}

@Test func tileVisibilityNeedsHalfOnScreen() {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    #expect(TileVisibility.isOnScreen(CGRect(x: 100, y: 100, width: 240, height: 360), screen: screen))
    // Half below the bottom edge: still counts (threshold 0.5), less does not.
    #expect(TileVisibility.isOnScreen(CGRect(x: 100, y: 900, width: 240, height: 360), screen: screen))
    #expect(!TileVisibility.isOnScreen(CGRect(x: 100, y: 1000, width: 240, height: 360), screen: screen))
    // Right of the screen (row scrolled), above it, empty frame.
    #expect(!TileVisibility.isOnScreen(CGRect(x: 1900, y: 100, width: 240, height: 360), screen: screen))
    #expect(!TileVisibility.isOnScreen(CGRect(x: 100, y: -400, width: 240, height: 360), screen: screen))
    #expect(!TileVisibility.isOnScreen(.zero, screen: screen))
}

@Test func visiblePrefetchKnownMeanwhileAndProfileReset() {
    var p = plan(["a", "b"])
    #expect(p.pass(now: at(1)) { _ in .needed } == ["a", "b"])
    // a: another search filled the cache meanwhile → „aus Cache“, not done (state decides next time).
    p.finished("a", outcome: .known, now: at(2))
    p.finished("b", outcome: .loaded, now: at(2))
    #expect(p.reports().first?.tally == VisiblePrefetchPlan.Tally(loaded: 1, cached: 1))
    // Profile switch: results forgotten, tiles stay registered; next pass after the debounce fetches both again.
    p.resetResults(now: at(3))
    #expect(p.runningCount == 0)
    #expect(p.pass(now: at(3.1)) { _ in .needed }.isEmpty)
    #expect(p.pass(now: at(3.5)) { _ in .needed } == ["a", "b"])
}

// Wave F-k R2: one budget for focus and visible tiles; focus first; pages pause visible tiles; cache tiers.

@Test func prefetchBudgetFocusHasPriority() {
    var b = PrefetchBudget(perMinute: 12, focusReserve: 4)
    // Visible tiles get what is left above the focus reserve: 8 of 12.
    #expect(b.free(.visible, now: at(0)) == 8)
    for i in 0..<8 { let ok = b.take(.visible, now: at(Double(i))); #expect(ok) }
    let ninth = b.take(.visible, now: at(9))
    #expect(!ninth)
    // The focus prefetch still has its 4, then the minute is used up for both.
    #expect(b.free(.focus, now: at(9)) == 4)
    for _ in 0..<4 { let ok = b.take(.focus, now: at(10)); #expect(ok) }
    let fifth = b.take(.focus, now: at(11))
    #expect(!fifth)
    // Visible again once its oldest starts are older than 60 s: 12 used, needs 5 to expire (at 0…4) → at 64.
    #expect(b.nextFreeAt(.visible, now: at(11)) == at(64))
    #expect(b.nextFreeAt(.focus, now: at(11)) == at(60))
    #expect(b.free(.focus, now: at(60)) == 1)
    #expect(b.free(.visible, now: at(60)) == 0)
    #expect(b.free(.visible, now: at(64)) == 1)
}

@Test func visiblePrefetchSharesBudgetWithFocus() {
    var p = plan(["a", "b", "c", "d", "e"], limits: .init(maxRunning: 10), budget: PrefetchBudget(perMinute: 6, focusReserve: 2))
    // The focus prefetch took 3 starts this minute: 6 − 3 − 2 = 1 left for visible tiles.
    for _ in 0..<3 { p.budget.take(.focus, now: at(0.5)) }
    #expect(p.pass(now: at(1)) { _ in .needed } == ["a"])
    #expect(p.queuedCount == 4)
    // Focus may still take the reserve.
    let reserve = p.budget.take(.focus, now: at(2))
    #expect(reserve)
}

@Test func visiblePrefetchPausesWhileAPageSearches() {
    var p = plan(["a", "b"])
    p.budget.foregroundSearchBegan()
    // A detail page loads its sources: no new visible start, no timer either (its end triggers the next pass).
    #expect(p.pass(now: at(1)) { _ in .needed }.isEmpty)
    #expect(p.queuedCount == 2)
    #expect(p.nextStartAt(now: at(1)) == nil)
    // The focus prefetch is not paused.
    #expect(p.budget.free(.focus, now: at(1)) == 12)
    p.budget.foregroundSearchEnded()
    #expect(p.pass(now: at(2)) { _ in .needed } == ["a", "b"])
}

@Test func streamCacheKeepsFocusEntryAfterManyVisiblePrefetches() {
    // Source cache with 40 places: the focus prefetch stores x, then 60 visible tiles are prefetched one by one.
    var cache: [String: Date] = ["x": at(0)]
    var weak = Set<String>()
    for i in 1...60 {
        let id = "v\(i)"
        cache[id] = at(Double(i))
        weak.insert(id)
        for k in StreamCacheTiers.overflow(storedAt: cache, weak: weak, limit: 40) { cache[k] = nil; weak.remove(k) }
    }
    #expect(cache["x"] != nil)
    #expect(cache.count == 40)
    // The oldest visible ones went first.
    #expect(cache["v1"] == nil)
    #expect(cache["v60"] != nil)
    // Without weak entries the oldest of the rest goes.
    #expect(StreamCacheTiers.overflow(storedAt: ["x": at(0), "y": at(1), "z": at(2)], weak: [], limit: 2) == ["x"])
    // A weak entry goes before an older strong one.
    #expect(StreamCacheTiers.overflow(storedAt: ["x": at(0), "w": at(5)], weak: ["w"], limit: 1) == ["w"])
}
