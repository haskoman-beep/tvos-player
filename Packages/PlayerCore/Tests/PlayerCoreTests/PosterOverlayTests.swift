import Foundation
import Testing
@testable import PlayerCore

// Build 8 (poster): urgent limiter queue, flight cancel policy, disk poster map (LRU + TTL), warm-up plan and log line.

private actor Order {
    var names: [String] = []
    func add(_ n: String) { names.append(n) }
}

@Test func limiterServesUrgentBeforeWarmUp() async {
    let limiter = AsyncLimiter(limit: 1)
    #expect(await limiter.acquire())
    let order = Order()
    let warm = Task { if await limiter.acquire(ticket: UUID(), urgent: false) { await order.add("warm"); await limiter.release() } }
    while await limiter.queued < 1 { await Task.yield() }
    let tile = Task { if await limiter.acquire(ticket: UUID(), urgent: true) { await order.add("tile"); await limiter.release() } }
    while await limiter.queued < 2 { await Task.yield() }
    await limiter.release()
    _ = await (warm.value, tile.value)
    #expect(await order.names == ["tile", "warm"])
    #expect(await limiter.active == 0)
}

@Test func limiterPromoteMovesWaitingTicketForward() async {
    let limiter = AsyncLimiter(limit: 1)
    #expect(await limiter.acquire())
    let order = Order()
    let a = UUID(), b = UUID()
    let first = Task { if await limiter.acquire(ticket: a, urgent: false) { await order.add("a"); await limiter.release() } }
    while await limiter.queued < 1 { await Task.yield() }
    let second = Task { if await limiter.acquire(ticket: b, urgent: false) { await order.add("b"); await limiter.release() } }
    while await limiter.queued < 2 { await Task.yield() }
    await limiter.promote(b)
    await limiter.release()
    _ = await (first.value, second.value)
    #expect(await order.names == ["b", "a"])
}

@Test func limiterPromoteBeforeQueueingCounts() async {
    let limiter = AsyncLimiter(limit: 1)
    #expect(await limiter.acquire())
    let order = Order()
    let late = UUID()
    let warm = Task { if await limiter.acquire(ticket: UUID(), urgent: false) { await order.add("warm"); await limiter.release() } }
    while await limiter.queued < 1 { await Task.yield() }
    await limiter.promote(late)   // arrives before its ticket queues
    let tile = Task { if await limiter.acquire(ticket: late, urgent: false) { await order.add("tile"); await limiter.release() } }
    while await limiter.queued < 2 { await Task.yield() }
    await limiter.release()
    _ = await (warm.value, tile.value)
    #expect(await order.names == ["tile", "warm"])
}

@Test func limiterCancelledTicketLeavesEitherQueue() async {
    let limiter = AsyncLimiter(limit: 1)
    #expect(await limiter.acquire())
    let w = Task { await limiter.acquire(ticket: UUID(), urgent: false) }
    while await limiter.queued < 1 { await Task.yield() }
    w.cancel()
    #expect(await w.value == false)
    #expect(await limiter.queued == 0)
    await limiter.release()
    #expect(await limiter.active == 0)
}

@Test func flightNotCancelledOnceSent() {
    // Not sent yet, last tile leaves: cancel.
    var a = FlightWaiters(tile: true)
    #expect(a.urgent)
    let l1 = a.leaveTile()

    #expect(l1)
    // Sent: the answer fills the cache, no cancel.
    var b = FlightWaiters(tile: true)
    b.markStarted()
    let l2 = b.leaveTile()

    #expect(!l2)
    // A warm-up holds it even before it is sent.
    var c = FlightWaiters(warm: true)
    #expect(!c.urgent)
    c.join(tile: true)
    #expect(c.urgent)
    let l3 = c.leaveTile()

    #expect(!l3)
    #expect(c.warm && c.tiles == 0)
    var d = FlightWaiters(tile: true)
    d.joinWarm()
    let l4 = d.leaveTile()

    #expect(!l4)
    // `init(warm: false)` pins (detail page).
    let e = FlightWaiters(warm: false)
    #expect(e.pinned && e.urgent)
}

@Test func posterMapHitsAgesAndEmptyAnswers() {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    var m = PosterURLMap(limit: 10)
    m.store("a", poster: "https://example.invalid/a.jpg", now: t0)
    m.store("b", poster: nil, now: t0)
    m.store("c", poster: "", now: t0)
    let r1 = m.lookup("a", now: t0)

    #expect(r1 == .poster("https://example.invalid/a.jpg"))
    let r2 = m.lookup("b", now: t0)

    #expect(r2 == .noPoster)
    let r3 = m.lookup("c", now: t0)

    #expect(r3 == .noPoster)
    let r4 = m.lookup("x", now: t0)

    #expect(r4 == nil)
    // "No poster" ages after 1 day, a poster after 7 days.
    let day2 = t0.addingTimeInterval(PosterURLMap.noPosterTTL + 1)
    #expect(m.peek("b", now: day2) == nil)
    let r5 = m.lookup("a", now: day2)

    #expect(r5 != nil)
    let day8 = t0.addingTimeInterval(PosterURLMap.posterTTL + 1)
    let r6 = m.lookup("a", now: day8)

    #expect(r6 == nil)
    #expect(m.peek("a", now: t0) == nil)   // dropped on the aged lookup
}

@Test func posterMapDropsLeastRecentlyUsed() {
    let now = Date(timeIntervalSince1970: 2_000_000)
    var m = PosterURLMap(limit: 20)
    for i in 0..<20 { m.store("k\(i)", poster: "p\(i)", now: now) }
    _ = m.lookup("k0", now: now)   // k0 used again: survives
    m.store("k20", poster: "p20", now: now)
    // Over the limit: down to 95 % (19), the least recently used (k1, k2) go.
    #expect(m.count == 19)
    #expect(m.peek("k0", now: now) != nil)
    #expect(m.peek("k1", now: now) == nil)
    #expect(m.peek("k2", now: now) == nil)
    #expect(m.peek("k3", now: now) != nil)
    #expect(m.peek("k20", now: now) != nil)
}

@Test func posterMapDiskRoundTripAndMerge() throws {
    let t0 = Date(timeIntervalSince1970: 3_000_000)
    var m = PosterURLMap(limit: 100)
    m.store("old", poster: "p-old", now: t0.addingTimeInterval(-PosterURLMap.posterTTL - 5))
    m.store("a", poster: "p-a", now: t0)
    m.store("none", poster: nil, now: t0)
    #expect(m.dirty)
    let copy = m
    m.markClean()
    let data = try #require(copy.encoded(now: t0))
    #expect(!m.dirty && copy.dirty)
    let back = try #require(PosterURLMap.decode(data, limit: 100, now: t0))
    #expect(back.count == 2)
    #expect(back.peek("a", now: t0) == .poster("p-a"))
    #expect(back.peek("none", now: t0) == .noPoster)
    #expect(PosterURLMap.decode(Data("{}".utf8)) == nil)
    #expect(PosterURLMap.decode(Data(#"{"version":0,"entries":{}}"#.utf8)) == nil)
    // This launch learned "a" anew and "b": they win and count as newer than the disk entries.
    var live = PosterURLMap(limit: 3)
    live.store("a", poster: "p-a2", now: t0)
    live.store("b", poster: "p-b", now: t0)
    live.merge(back)
    #expect(live.peek("a", now: t0) == .poster("p-a2"))
    #expect(live.count == 3)
    live.store("c", poster: "p-c", now: t0)   // over 3: the disk entry ("none") goes first
    #expect(live.peek("none", now: t0) == nil)
    #expect(live.peek("b", now: t0) != nil && live.peek("c", now: t0) != nil)
}

@Test func warmPlanPicksTMDBTilesWithinBacklog() {
    let ids = ["tmdb:1", "tt2", "tmdb:3", "tmdb:1", "tmdb:4", "tmdb:5"]
    #expect(OverlayWarmPlan.pick(ids, pending: 0) == ["tmdb:1", "tmdb:3", "tmdb:4", "tmdb:5"])
    #expect(OverlayWarmPlan.pick(ids, pending: 78) == ["tmdb:1", "tmdb:3"])
    #expect(OverlayWarmPlan.pick(ids, pending: 90).isEmpty)
}

@Test func warmTallyLine() {
    var t = OverlayWarmTally(total: 20)
    for _ in 0..<5 { t.record(.cache, found: true) }
    for _ in 0..<13 { t.record(.network, found: true) }
    t.record(.network, found: false)
    t.record(.failed, found: false)
    #expect(t.line(ms: 2410) == "Overlays 18/20 in 2410 ms (Cache 5, Netz 14) · ohne Antwort 1")
    #expect(OverlayWarmTally(total: 0).line(ms: 0) == "Overlays 0/0 in 0 ms (Cache 0, Netz 0)")
}

@Test func exactPosterTarget() throws {
    let stepped = try #require(ImageTarget(points: 300, 450, scale: 2, fit: false))
    #expect(stepped.width == 640 && stepped.height == 1024)
    let exact = try #require(ImageTarget(points: 300, 450, scale: 2, fit: false, stepped: false))
    #expect(exact.width == 600 && exact.height == 900)
    // 2:3 poster 1000×1500 fills 600×900 exactly.
    #expect(exact.decodeMaxPixels(imageWidth: 1000, imageHeight: 1500) == 900)
    #expect(stepped.decodeMaxPixels(imageWidth: 1000, imageHeight: 1500) == 1024)
    #expect(ImageTarget(points: 0, 450, scale: 2, fit: false, stepped: false) == nil)
    let huge = try #require(ImageTarget(points: 5000, 5000, scale: 1, fit: false, stepped: false))
    #expect(huge.width == 3840)
}

@Test func limiterNewestPromotionFirstAndDemote() async {
    let limiter = AsyncLimiter(limit: 1)
    #expect(await limiter.acquire())
    let order = Order()
    let a = UUID(), b = UUID(), c = UUID()
    var tasks: [Task<Void, Never>] = []
    for (n, t) in [("a", a), ("b", b), ("c", c)] {
        let before = await limiter.queued
        tasks.append(Task { if await limiter.acquire(ticket: t, urgent: false) { await order.add(n); await limiter.release() } })
        while await limiter.queued == before { await Task.yield() }
    }
    await limiter.promote(a)
    await limiter.promote(b)   // newest promotion goes in front of a
    await limiter.demote(a)    // a's last tile left: back behind c
    await limiter.release()
    for t in tasks { await t.value }
    #expect(await order.names == ["b", "c", "a"])
}

@Test func limiterEarlyPromotionsKeepNewest() async {
    let limiter = AsyncLimiter(limit: 1)
    #expect(await limiter.acquire())
    let keep = UUID()
    for _ in 0..<255 { await limiter.promote(UUID()) }
    await limiter.promote(keep)
    for _ in 0..<100 { await limiter.promote(UUID()) }   // only the oldest drop, `keep` stays
    let order = Order()
    let warm = Task { if await limiter.acquire(ticket: UUID(), urgent: false) { await order.add("warm"); await limiter.release() } }
    while await limiter.queued < 1 { await Task.yield() }
    let tile = Task { if await limiter.acquire(ticket: keep, urgent: false) { await order.add("tile"); await limiter.release() } }
    while await limiter.queued < 2 { await Task.yield() }
    await limiter.release()
    _ = await (warm.value, tile.value)
    #expect(await order.names == ["tile", "warm"])
}

@Test func overlayBackoffSteps() {
    let t0 = Date(timeIntervalSince1970: 5_000_000)
    var b = OverlayBackoff()
    #expect(b.wait(now: t0) == 0)
    b.noteFailure(now: t0)
    #expect(b.wait(now: t0) == 15)
    b.noteFailure(now: t0)
    #expect(b.wait(now: t0) == 30)
    b.noteFailure(now: t0)
    b.noteFailure(now: t0)
    #expect(b.wait(now: t0) == 60)
    #expect(b.wait(now: t0.addingTimeInterval(61)) == 0)
    b.noteSuccess()
    #expect(b.wait(now: t0) == 0 && b.failures == 0)
}

@Test func posterURLCarriesIDAsWholePart() {
    #expect(OverlayWarmPlan.urlCarriesID("https://example.invalid/k/imdb/poster-default/tt123.jpg", id: "tt123"))
    #expect(OverlayWarmPlan.urlCarriesID("https://example.invalid/poster?id=550&x=1", id: "tmdb:550"))
    #expect(!OverlayWarmPlan.urlCarriesID("https://example.invalid/p/15501.jpg", id: "tmdb:550"))
    #expect(!OverlayWarmPlan.urlCarriesID("https://example.invalid/p/tt1234.jpg", id: "tt123"))
    #expect(!OverlayWarmPlan.urlCarriesID("https://example.invalid/p.jpg", id: "tmdb:"))
}
