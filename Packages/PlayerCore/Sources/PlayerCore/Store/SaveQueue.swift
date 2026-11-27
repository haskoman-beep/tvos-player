import Foundation

/// Phase 0b: the background save service. Encoding and writing leave the calling (main) thread.
///
/// Rules:
/// - `submit(key, job)` returns at once. Jobs run one after the other on one background thread, in the order their
///   keys were first submitted.
/// - Bundling: a job that still waits is replaced by a newer job with the same key and keeps its place. Twenty saves
///   of one block during a slow write become one write of the latest state. A job that already runs is never
///   replaced: it took its snapshot, the newer one runs after it.
/// - A job captures a snapshot (value types); it must not read the caller's state when it runs.
/// - Callers that need the result or a fixed order use `runNow` (run on the calling thread, in the queue's order),
///   `settle` (before reading a block back), `discard` (before removing a block) and `drain` (app goes to the
///   background).
/// - No two jobs ever run at the same time, `runNow` included.
///
/// `onError`, `done` and the jobs run on the background thread (or, for `runNow`, the calling thread). They must not
/// call `runNow`, `settle`, `discard` or `drain` of the same queue (deadlock); `submit` is allowed.
public final class SaveQueue: @unchecked Sendable {
    public typealias Job = @Sendable () throws -> Void
    public typealias Done = @Sendable (Result<Void, Error>) -> Void

    private struct Entry { let job: Job; let done: Done? }

    /// Guards the fields below; `signal`s every change that a waiting caller may care about.
    private let state = NSCondition()
    private var order: [String] = []
    private var waiting: [String: Entry] = [:]
    /// Key of the job the worker runs right now (until its `done` returned).
    private var running: String?
    private var workerActive = false
    /// `runNow` callers that wait for `exec`: the worker lets them go first (the lock itself is not fair).
    private var urgent = 0
    /// Held while a job (with its `done`) runs: the worker's job or a `runNow` body. Order: `exec` before `state`.
    private let exec = NSLock()
    private let worker: DispatchQueue
    private let onError: (@Sendable (String, Error) -> Void)?

    /// `onError`: called with the key for every failed job that has no `done` of its own.
    public init(label: String = "player.save", onError: (@Sendable (String, Error) -> Void)? = nil) {
        // Not `.utility`: the main thread waits for this thread in `drain`, `settle` and `runNow`.
        worker = DispatchQueue(label: label, qos: .userInitiated)
        self.onError = onError
    }

    /// Queues `job`. A waiting job with the same key is replaced (its `done` is never called).
    /// `done` gets the result of this job if it runs; without it a failure goes to `onError`.
    public func submit(_ key: String, _ job: @escaping Job, done: Done? = nil) {
        state.lock()
        if waiting.updateValue(Entry(job: job, done: done), forKey: key) == nil { order.append(key) }
        let start = !workerActive
        if start { workerActive = true }
        state.unlock()
        if start { worker.async { self.pump() } }
    }

    /// Keys of the jobs that wait (not the running one), in the order they will run.
    public var waitingKeys: [String] {
        state.lock(); defer { state.unlock() }
        return order
    }

    /// Runs `body` on the calling thread, after the job that runs right now and before the jobs that wait. A waiting
    /// job with this key is dropped: it is older than what `body` writes. If `body` throws, that job comes back and
    /// runs next (unless a newer one was submitted meanwhile).
    public func runNow<T>(_ key: String, _ body: () throws -> T) rethrows -> T {
        state.lock()
        let dropped = waiting.removeValue(forKey: key)
        if dropped != nil { order.removeAll { $0 == key } }
        urgent += 1
        state.broadcast()
        state.unlock()
        exec.lock()
        defer {
            exec.unlock()
            state.lock()
            urgent -= 1
            state.broadcast()
            state.unlock()
        }
        do { return try body() } catch {
            // The body wrote nothing: the state of the dropped job is still the newest one, it runs next.
            if let dropped { putBack(key, dropped) }
            throw error
        }
    }

    private func putBack(_ key: String, _ entry: Entry) {
        state.lock()
        var start = false
        if waiting[key] == nil {
            waiting[key] = entry
            order.insert(key, at: 0)
            start = !workerActive
            if start { workerActive = true }
        }
        state.unlock()
        if start { worker.async { self.pump() } }
    }

    /// Returns when no job with this key waits or runs (the block on disk is the last submitted state).
    public func settle(_ key: String) {
        state.lock()
        while waiting[key] != nil || running == key { state.wait() }
        state.unlock()
    }

    /// Drops a waiting job with this key and waits for a running one. Afterwards nothing submitted before this call
    /// writes under this key any more (call it before removing the block).
    public func discard(_ key: String) {
        dropWaiting(key)
        state.lock()
        while running == key { state.wait() }
        state.unlock()
    }

    /// Blocks until every job is done, at most `timeout` seconds (nil: without limit). False on timeout.
    @discardableResult
    public func drain(timeout: TimeInterval? = nil) -> Bool {
        let end = timeout.map { Date().addingTimeInterval($0) }
        state.lock(); defer { state.unlock() }
        while !order.isEmpty || running != nil {
            if let end {
                if !state.wait(until: end) { return order.isEmpty && running == nil }
            } else {
                state.wait()
            }
        }
        return true
    }

    private func dropWaiting(_ key: String) {
        state.lock()
        if waiting.removeValue(forKey: key) != nil { order.removeAll { $0 == key } }
        state.broadcast()
        state.unlock()
    }

    private func pump() {
        while true {
            // `exec` first: between taking a job and running it no `runNow` body can slip in (it would be
            // overwritten by the older job).
            state.lock()
            while urgent > 0 { state.wait() }
            state.unlock()
            exec.lock()
            state.lock()
            guard let key = order.first, let entry = waiting.removeValue(forKey: key) else {
                workerActive = false
                state.broadcast()
                state.unlock()
                exec.unlock()
                return
            }
            order.removeFirst()
            running = key
            state.unlock()

            let result = Result { try entry.job() }
            if let done = entry.done { done(result) } else if case .failure(let e) = result { onError?(key, e) }
            exec.unlock()

            state.lock()
            running = nil
            state.broadcast()
            state.unlock()
        }
    }
}

// MARK: progress through the queue

public extension SaveQueue {
    /// Key of a profile's progress book.
    static func progressKey(_ profile: UUID) -> String { "progress-" + profile.uuidString }
    /// Key of every write of `profiles.json` and its generations.
    static let profilesKey = "profiles"
}

public extension ProgressStore {
    /// Saves on the queue: `book` is a snapshot, encoding and writing run in the background. Several calls during a
    /// slow write become one write of the latest book. `failed` runs on the background thread.
    func save(_ book: ProgressBook, profile: UUID, on queue: SaveQueue, failed: (@Sendable (Error) -> Void)? = nil) {
        var done: SaveQueue.Done?
        if let failed {
            done = { (result: Result<Void, Error>) in
                if case .failure(let e) = result { failed(e) }
            }
        }
        queue.submit(SaveQueue.progressKey(profile), { _ = try self.save(book, profile: profile) }, done: done)
    }

    /// `load(profile:)` after every queued write of this profile's book went through.
    func load(profile: UUID, settling queue: SaveQueue) -> ProgressBook? {
        queue.settle(SaveQueue.progressKey(profile))
        return load(profile: profile)
    }
}
