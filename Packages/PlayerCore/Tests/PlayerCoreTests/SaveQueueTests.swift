import Foundation
import Testing
@testable import PlayerCore

// Phase 0b: the background save service. Jobs (encode + write) leave the calling thread; a newer job for the same
// key replaces one that still waits; `runNow`, `discard` and `drain` give callers that need the result a fixed order.

/// What the jobs did, in order.
private final class Journal: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ s: String) { lock.withLock { lines.append(s) } }
    var all: [String] { lock.withLock { lines } }
}

/// Holds a job until the test lets it go, and tells the test that the job has started.
private final class Gate: @unchecked Sendable {
    let started = DispatchSemaphore(value: 0)
    let open = DispatchSemaphore(value: 0)
    func pass() { started.signal(); open.wait() }
}

private struct Boom: Error, Equatable {}

private let film = MetaPreview(id: "tt1", type: "movie", name: "Film")

@Test func jobRunsOffTheCallingThread() {
    let q = SaveQueue()
    let caller = ObjectIdentifier(Thread.current)
    let j = Journal()
    q.submit("a") { j.add(ObjectIdentifier(Thread.current) == caller ? "caller" : "other") }
    #expect(q.drain(timeout: 5))
    #expect(j.all == ["other"])
}

@Test func jobsRunInSubmissionOrder() {
    let q = SaveQueue()
    let j = Journal()
    for k in ["a", "b", "c", "d"] { q.submit(k) { j.add(k) } }
    #expect(q.drain(timeout: 5))
    #expect(j.all == ["a", "b", "c", "d"])
}

@Test func newerJobReplacesWaitingJobOfSameKeyAndKeepsItsPlace() {
    let q = SaveQueue()
    let j = Journal()
    let gate = Gate()
    q.submit("hold") { gate.pass() }
    gate.started.wait()
    q.submit("progress") { j.add("progress 1") }
    q.submit("profiles") { j.add("profiles") }
    q.submit("progress") { j.add("progress 2") }
    q.submit("progress") { j.add("progress 3") }
    #expect(q.waitingKeys == ["progress", "profiles"])
    gate.open.signal()
    #expect(q.drain(timeout: 5))
    #expect(j.all == ["progress 3", "profiles"])
}

@Test func jobSubmittedWhileSameKeyRunsStillRuns() {
    // The running job already took its snapshot: the newer state must be written after it.
    let q = SaveQueue()
    let j = Journal()
    let gate = Gate()
    q.submit("progress") { gate.pass(); j.add("old") }
    gate.started.wait()
    q.submit("progress") { j.add("new") }
    gate.open.signal()
    #expect(q.drain(timeout: 5))
    #expect(j.all == ["old", "new"])
}

@Test func failingJobReportsItsKeyAndTheQueueGoesOn() {
    let j = Journal()
    let q = SaveQueue(onError: { key, error in j.add("\(key): \(error is Boom)") })
    q.submit("a") { throw Boom() }
    q.submit("b") { j.add("b ran") }
    #expect(q.drain(timeout: 5))
    #expect(j.all == ["a: true", "b ran"])
}

@Test func doneIsCalledForTheJobThatRanOnly() {
    let q = SaveQueue()
    let j = Journal()
    let gate = Gate()
    q.submit("hold") { gate.pass() }
    gate.started.wait()
    q.submit("p", { j.add("job 1") }, done: { _ in j.add("done 1") })
    q.submit("p", { throw Boom() }, done: { r in
        if case .failure(let e) = r { j.add("done 2 failed \(e is Boom)") } else { j.add("done 2 ok") }
    })
    gate.open.signal()
    #expect(q.drain(timeout: 5))
    #expect(j.all == ["done 2 failed true"])
}

@Test func doneRunsBeforeDrainReturns() {
    let q = SaveQueue()
    let j = Journal()
    q.submit("p", { j.add("job") }, done: { _ in Thread.sleep(forTimeInterval: 0.05); j.add("done") })
    #expect(q.drain(timeout: 5))
    #expect(j.all == ["job", "done"])
}

@Test func runNowReturnsTheResultAndDropsTheOlderWaitingJob() throws {
    let q = SaveQueue()
    let j = Journal()
    let gate = Gate()
    q.submit("hold") { gate.pass(); j.add("hold") }
    gate.started.wait()
    q.submit("profiles") { j.add("stale profiles") }
    q.submit("other") { j.add("other") }
    // The running job ends first; `runNow` then runs on this thread.
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { gate.open.signal() }
    let caller = ObjectIdentifier(Thread.current)
    let n = try q.runNow("profiles") { () throws -> Int in
        j.add(ObjectIdentifier(Thread.current) == caller ? "now on caller" : "now elsewhere")
        return 7
    }
    #expect(n == 7)
    #expect(q.drain(timeout: 5))
    #expect(j.all == ["hold", "now on caller", "other"])
}

@Test func runNowRethrows() {
    let q = SaveQueue()
    #expect(throws: Boom.self) { try q.runNow("x") { throw Boom() } }
    // The queue still works afterwards.
    let j = Journal()
    q.submit("y") { j.add("y") }
    #expect(q.drain(timeout: 5))
    #expect(j.all == ["y"])
}

@Test func settleWaitsForWaitingAndRunningJobsOfThatKey() {
    let q = SaveQueue()
    let j = Journal()
    let gate = Gate()
    q.submit("hold") { gate.pass() }
    gate.started.wait()
    q.submit("progress") { Thread.sleep(forTimeInterval: 0.05); j.add("written") }
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { gate.open.signal() }
    q.settle("progress")
    #expect(j.all == ["written"])
}

@Test func settleReturnsAtOnceWhenNothingIsPending() {
    let q = SaveQueue()
    q.settle("nothing")
    #expect(q.waitingKeys.isEmpty)
}

@Test func discardDropsWaitingJobAndWaitsForARunningOne() {
    let q = SaveQueue()
    let j = Journal()
    let gate = Gate()
    q.submit("progress") { gate.pass(); Thread.sleep(forTimeInterval: 0.05); j.add("running one finished") }
    gate.started.wait()
    q.submit("progress") { j.add("must not run") }
    gate.open.signal()
    q.discard("progress")
    j.add("after discard")
    #expect(q.drain(timeout: 5))
    #expect(j.all == ["running one finished", "after discard"])
}

@Test func drainTimesOutWhileAJobHangs() {
    let q = SaveQueue()
    let gate = Gate()
    q.submit("hold") { gate.pass() }
    gate.started.wait()
    #expect(q.drain(timeout: 0.05) == false)
    gate.open.signal()
    #expect(q.drain(timeout: 5))
}

@Test func manySubmittersLoseNoLastState() {
    // Eight threads write their own key 200 times: the last value of every key must be the one stored.
    let q = SaveQueue()
    let dir = FileBlobStorage(directory: tempDir())
    DispatchQueue.concurrentPerform(iterations: 8) { t in
        for i in 0..<200 {
            q.submit("k\(t)") { try dir.write("k\(t)", Data("\(i)".utf8)) }
        }
    }
    #expect(q.drain(timeout: 20))
    for t in 0..<8 { #expect(dir.read("k\(t)") == Data("199".utf8)) }
}

// MARK: progress through the queue

@Test func deferredProgressSaveIsReadBackAfterSettle() {
    let q = SaveQueue()
    let store = ProgressStore(storage: FileBlobStorage(directory: tempDir()))
    let id = UUID()
    var book = ProgressBook()
    book.record(id: "tt1", item: film, position: 100, duration: 1000)
    store.save(book, profile: id, on: q)
    // `load(profile:settling:)` waits for the write above, however slow it is.
    #expect(store.load(profile: id, settling: q)?.entries.count == 1)
}

@Test func deferredProgressSavesCollapseToTheLatestBook() {
    let q = SaveQueue()
    let store = ProgressStore(storage: FileBlobStorage(directory: tempDir()))
    let id = UUID()
    let gate = Gate()
    q.submit("hold") { gate.pass() }
    gate.started.wait()
    var book = ProgressBook()
    for i in 1...20 {
        book.record(id: "tt1", item: film, position: Double(i * 10), duration: 1000)
        store.save(book, profile: id, on: q)
    }
    #expect(q.waitingKeys == [SaveQueue.progressKey(id)])
    gate.open.signal()
    #expect(store.load(profile: id, settling: q)?.entries["tt1"]?.position == 200)
}

@Test func deferredProgressFailureReachesTheCaller() {
    struct Refusing: BlobStorage {
        func read(_ name: String) -> Data? { nil }
        func write(_ name: String, _ data: Data) throws { throw Boom() }
        func remove(_ name: String) {}
    }
    let q = SaveQueue()
    let j = Journal()
    let store = ProgressStore(storage: Refusing())
    store.save(ProgressBook(), profile: UUID(), on: q) { error in j.add("failed \(error is Boom)") }
    #expect(q.drain(timeout: 5))
    #expect(j.all == ["failed true"])
}

@Test func discardedProgressWriteDoesNotComeBackAfterRemoval() {
    // Profile deleted while its last progress write still waits: the block must stay gone.
    let q = SaveQueue()
    let dir = FileBlobStorage(directory: tempDir())
    let store = ProgressStore(storage: dir)
    let id = UUID()
    let gate = Gate()
    q.submit("hold") { gate.pass() }
    gate.started.wait()
    var book = ProgressBook()
    book.record(id: "tt1", item: film, position: 100, duration: 1000)
    store.save(book, profile: id, on: q)
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { gate.open.signal() }
    q.discard(SaveQueue.progressKey(id))
    dir.remove(store.name(id))
    #expect(q.drain(timeout: 5))
    #expect(dir.read(store.name(id)) == nil)
}
