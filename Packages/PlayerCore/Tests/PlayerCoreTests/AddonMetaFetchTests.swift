import Foundation
import Testing
@testable import PlayerCore

private actor Gauge {
    var now = 0, peak = 0, done = 0
    func enter() { now += 1; peak = max(peak, now) }
    func leave() { now -= 1; done += 1 }
}

@Test func limiterCapsConcurrency() async {
    let limiter = AsyncLimiter(limit: 4)
    let g = Gauge()
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<12 {
            group.addTask {
                _ = await limiter.run {
                    await g.enter()
                    try? await Task.sleep(nanoseconds: 20_000_000)
                    await g.leave()
                }
            }
        }
    }
    #expect(await g.peak <= 4)
    #expect(await g.peak >= 2)
    #expect(await g.done == 12)
    #expect(await limiter.active == 0)
}

@Test func limiterCancelledWaiterLeavesQueue() async throws {
    let limiter = AsyncLimiter(limit: 1)
    #expect(await limiter.acquire())
    let waiter = Task { await limiter.acquire() }
    while await limiter.queued == 0 { await Task.yield() }
    waiter.cancel()
    #expect(await waiter.value == false)
    #expect(await limiter.queued == 0)
    await limiter.release()
    #expect(await limiter.active == 0)
    // Schon abgebrochen: kein Platz.
    let early = Task { () -> Bool in
        withUnsafeCurrentTask { $0?.cancel() }
        return await limiter.acquire()
    }
    #expect(await early.value == false)
    #expect(await limiter.active == 0)
}

@Test func metaFetchOutcomes() async {
    let m = try! JSONDecoder().decode(MetaDetail.self, from: Data(#"{"id":"tt1","type":"movie","name":"A"}"#.utf8))
    #expect(await AddonMetaFetch.run { m } == .meta(m))
    #expect(await AddonMetaFetch.run { throw URLError(.badServerResponse) } == .failed)
    #expect(await AddonMetaFetch.run { throw URLError(.cancelled) } == .cancelled)
    #expect(await AddonMetaFetch.run { throw CancellationError() } == .cancelled)
    // Zeitgrenze: Hänger zählt als Fehler.
    #expect(await AddonMetaFetch.run(limit: 0.05) { try await Task.sleep(nanoseconds: 2_000_000_000); return m } == .failed)
    // Abbruch von außen: nicht als Fehler.
    let t = Task { await AddonMetaFetch.run { try await Task.sleep(nanoseconds: 2_000_000_000); return m } }
    t.cancel()
    #expect(await t.value == .cancelled)
}

@Test func metaFetchWaitAndValue() async {
    let slow = Task<Int?, Never> { try? await Task.sleep(nanoseconds: 300_000_000); return 7 }
    #expect(await AddonMetaFetch.wait(for: slow, atMost: 0.02) == nil)
    #expect(await slow.value == 7)   // läuft nach dem Warten weiter
    let fast = Task<Int?, Never> { 3 }
    #expect(await AddonMetaFetch.wait(for: fast, atMost: 1) == 3)
    let long = Task<Int?, Never> { try? await Task.sleep(nanoseconds: 2_000_000_000); return 1 }
    let left = Gauge()
    let caller = Task { await AddonMetaFetch.value(of: long, onCancel: { Task { await left.enter() } }) }
    try? await Task.sleep(nanoseconds: 20_000_000)
    caller.cancel()
    #expect(await caller.value == nil)
    // Höchstens 2 s warten, sonst fehlschlagen statt ewig zu hängen.
    let deadline = ContinuousClock.now + .seconds(2)
    while await left.done + left.now == 0 {
        guard ContinuousClock.now < deadline else { Issue.record("onCancel kam nicht binnen 2 s"); long.cancel(); return }
        await Task.yield()
    }
    #expect(await left.now == 1)   // onCancel kam an
    long.cancel()
}

@Test func flightWaitersCancelOnlyWithoutWaiters() {
    var a = FlightWaiters(tile: true)
    a.join(tile: true)
    let a1 = a.leaveTile(), a2 = a.leaveTile()
    #expect(!a1)
    #expect(a2)
    var b = FlightWaiters(tile: true)
    b.join(tile: false)
    let b1 = b.leaveTile()
    #expect(!b1)          // Detailseite hält die Abfrage
    var c = FlightWaiters(tile: false)
    let c1 = c.leaveTile()
    #expect(!c1)
    #expect(c.tiles == 0 && c.pinned)
}
