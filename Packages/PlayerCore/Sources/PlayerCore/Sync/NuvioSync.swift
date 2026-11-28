import Foundation

// Nuvio account sync, T7: one sync pass as pure orchestration (plan sections 1.7–1.9, addendum A3, A4, A8, D3, D4).
// Profile check → bootstrap or delta pull → merge → IMDb ids of `tmdb:` titles → push the outbox → titles of staged
// rows. No timer, no sleep, no storage: the client calls, the id and title lookups and the clock are injected; book and
// state go in and come out by value. The app owns persistence, the single-flight token refresh, the cooldown memory
// and the triggers.
//
// Consistency: every change is recorded as a `NuvioSyncChange` and applied at once to the working copy. A cursor
// step is recorded only after the changes of its page, so whatever the pass returns (also after an error midway)
// never has a cursor past data that is not in the returned book. A bootstrap commits as one group (rows, cursors,
// `bootstrapDone`) or not at all; one that needs more passes stores where it goes on. Merging is newer-wins with a tie
// keeping local, so a page applied twice changes nothing, and a second pass after any interruption converges.
//
// Ids (review 2, findings 1 and 2): no lookup runs while rows are taken. A `tmdb:N` row without a known link is merged
// at once under the provisional local id `tmdb:N` (one id for all rows of the title) and noted as pending; after the
// pull at most `metaPerPass` pending titles are looked up, newest first, and a found IMDb id moves the title with a
// `.rekey` step (entries, tombstones, staged rows, outbox). Links and pending titles are keyed by kind, since TMDB
// numbers films and series separately.
//
// Deletes (finding 12, documented, not changed): a delete event is judged against `lastPullAt`, the start of the last
// pass that reached its end. A pass that fails midway after consuming delete pages leaves `lastPullAt` older than
// the rows it merged, so such a delete may be consumed without removing an entry pulled in that pass. That errs on
// the safe side (an entry stays, nothing is lost) and the next upsert or delete of the title settles it.

/// The client calls a pass needs (`NuvioClient` conforms; tests use a scripted fake).
public protocol NuvioSyncAPI: Sendable {
    func profiles(_ s: NuvioSession) async throws -> [NuvioProfile]
    func progress(profile: Int, _ s: NuvioSession) async throws -> NuvioPage<NuvioProgressRow>
    func progressCursor(profile: Int, _ s: NuvioSession) async throws -> Int
    func progressDelta(profile: Int, since: Int, limit: Int, _ s: NuvioSession) async throws -> NuvioPage<NuvioProgressEvent>
    func push(profile: Int, _ entries: [NuvioProgressPush], _ s: NuvioSession) async throws
    func watched(profile: Int, page: Int, pageSize: Int, _ s: NuvioSession) async throws -> NuvioPage<NuvioWatchedItem>
    func watchedCursor(profile: Int, _ s: NuvioSession) async throws -> Int
    func watchedDelta(profile: Int, since: Int, limit: Int, _ s: NuvioSession) async throws -> NuvioPage<NuvioWatchedEvent>
}

extension NuvioClient: NuvioSyncAPI {}

/// Answer of the IMDb-id lookup for a `tmdb:N` title (finding 2).
public enum NuvioIDLookup: Equatable, Sendable {
    /// The IMDb id (`tt…`; anything else counts as `none`).
    case found(String)
    /// The title has no IMDb id. After `NuvioState.maxIDAttempts` such answers it keeps `tmdb:N`.
    case notFound
    /// The lookup could not run (offline, rate limit, no key): tried again in a later pass, no attempt counted.
    case unavailable
}

/// Everything a pass reaches outside itself.
public struct NuvioSyncDependencies: Sendable {
    public var api: any NuvioSyncAPI
    /// `tmdb:N` → IMDb id. Gets a nameless preview (`id` = `tmdb:N`, `type` = `movie` or `series`).
    public var imdbID: @Sendable (MetaPreview) async -> NuvioIDLookup
    /// Title (and artwork) for a nameless pulled row. Gets the local item preview without a name; nil or an empty
    /// name: the row stays staged and is tried again at the next pass.
    public var meta: @Sendable (MetaPreview) async -> MetaPreview?
    public var now: @Sendable () -> Date
    /// The stored session, read again before every account call (finding 18): after the client's refresh hook stored
    /// a renewed session, the rest of the pass uses it. A session of another account is ignored.
    public var currentSession: (@Sendable () async -> NuvioSession?)?

    public init(api: any NuvioSyncAPI, imdbID: @escaping @Sendable (MetaPreview) async -> NuvioIDLookup,
                meta: @escaping @Sendable (MetaPreview) async -> MetaPreview?, now: @escaping @Sendable () -> Date = { Date() },
                currentSession: (@Sendable () async -> NuvioSession?)? = nil) {
        self.api = api; self.imdbID = imdbID; self.meta = meta; self.now = now; self.currentSession = currentSession
    }
}

public enum NuvioSyncMode: Equatable, Sendable {
    /// Pull, then push (always, when something waits; finding 4: a queued entry the account already has newer is
    /// dropped by the pull first). App start, profile switch, foreground, after playback. A pull that fails ends the
    /// pass before the push.
    case full
    /// Push only, when due (`force` skips the 60 s throttle: pause, stop). Nothing is pulled.
    case pushOnly(force: Bool)
}

/// Why a pass ended. No UI text here: the app maps each case to its own wording.
public enum NuvioSyncOutcome: Equatable, Sendable {
    /// Everything done.
    case ok
    /// Done, but not all of it: a delta page cap stopped the pull (`summary.moreToPull`), or the account refused the
    /// push with a status the pull did not share (`summary.pushError`; the outbox is kept).
    case partial
    /// No Nuvio profile chosen (also after the state was reset for another account). No call was made.
    case notChosen
    /// No profile at the stored index any more (A3). Nothing was pulled or pushed.
    case profileMissing
    /// The index holds another profile now (A3). Nothing was pulled or pushed.
    case profileReplaced
    /// The chosen profile is PIN-protected now (D3). Nothing was pulled or pushed.
    case pinProtected
    /// The session is not accepted (after the client's one refresh). The app wipes the stored session.
    case signedOut
    /// Still 429 after the client's one retry, or a cooldown is running: no Nuvio call before `until`.
    case rateLimited(until: Date)
    /// No answer from the account.
    case offline
    /// Any other refusal or unreadable answer (403 = row-level security). Work committed before it stays.
    case failed(NuvioError)
    /// The task was cancelled. Work committed before it stays.
    case cancelled
}

public struct NuvioSyncSummary: Equatable, Sendable {
    /// Outbox entries the account took.
    public var pushed = 0
    /// Book entries changed by pulled rows (staged rows resolved in this pass included).
    public var merged = 0
    /// Book entries removed by delete events.
    public var deleted = 0
    /// Pulled rows left out in this pass: unreadable, other id schemes, whole-series rows.
    public var skipped = 0
    /// Rows waiting for a title after the pass (`state.staged.count`).
    public var staged = 0
    /// This pass completed the bootstrap.
    public var bootstrapped = false
    /// A delta stream hit its page cap; the next pass continues from the stored cursor.
    public var moreToPull = false
    /// The push the account refused with a status or an unreadable answer (the pull still ran; the outbox is kept,
    /// except entries refused alone `NuvioOutbox.maxAttempts` times).
    public var pushError: NuvioError?
    /// Outbox entries dropped in this pass after the account refused them alone too often (finding 11).
    public var pushDropped = 0
    /// The bootstrap snapshot came back full (200 rows, the server's cap without `p_since_last_watched`): older
    /// progress rows of the account were not in it (finding 6; the reference documents no paging for it).
    public var snapshotCapped = false
    /// `tmdb:` titles still waiting for their IMDb id after the pass (`state.pendingIDs.count`).
    public var pendingIDs = 0

    public init() {}
}

/// One sent outbox entry (`NuvioOutbox.batch()` element as a value).
public struct NuvioSentPush: Equatable, Sendable {
    public var key: String
    public var push: NuvioProgressPush
    public init(key: String, push: NuvioProgressPush) { self.key = key; self.push = push }
}

/// One step of a pass. Applying the steps in order to the book and state the pass started from gives exactly the
/// returned book and state; applying them to the live values instead keeps what the app changed meanwhile (plays,
/// new outbox notes, tombstones): merges are newer-wins, deletes and tombstone filters are judged against the live
/// values, and a confirmed push keeps an entry that was replaced while in flight.
public enum NuvioSyncChange: Equatable, Sendable {
    /// The session's account: sets `userID`, or resets the state when it belonged to another account.
    case account(String)
    /// The chosen profile had no id stored; the fresh list gave one (finding 8).
    case profilePinned(String)
    case pushed([NuvioSentPush], at: Date)
    case pushFailed(at: Date)
    /// The account refused this entry sent alone (finding 11): one attempt counted, dropped at the limit.
    case pushRefused(NuvioSentPush, at: Date)
    /// Progress key → `last_watched` (epoch ms) of pulled rows: queued entries not newer go (finding 4).
    case outboxSeen([String: Int])
    /// Provisional `tmdb:N` titles to resolve.
    case pending([NuvioPendingID])
    /// The lookup said "no IMDb id" for the title (one attempt; at the limit it keeps `tmdb:N` for good).
    case idMissing(number: Int, series: Bool)
    /// Moves a title from its provisional id to its IMDb id and links the two (finding 2). Idempotent.
    case rekey(from: String, to: String, series: Bool)
    /// Pulled entries, filtered with the tombstones (A4) and merged.
    case merge([NuvioProgressEntry])
    /// Nameless rows that wait for a title (beyond `NuvioState.maxStaged` the oldest go and are counted as skipped).
    case stage([NuvioStaged])
    /// Staged rows (by `NuvioStaged.id`) that were merged or replaced.
    case unstage([String])
    /// Delete events by progress key (translated to local ids when applied; staged rows of the keys go too).
    case delete(progressKeys: [String], watchedKeys: [String], before: Date)
    case skipped(Int)
    /// A bootstrap goes on in the next pass from here (nil: it starts over).
    case bootstrapResume(NuvioBootstrapResume?)
    /// Bootstrap committed: cursors captured before the snapshot, `bootstrapDone`.
    case bootstrapped(progressCursor: Int, watchedCursor: Int)
    case progressCursor(Int)
    case watchedCursor(Int)
    case pulled(at: Date)
}

/// What `NuvioSyncChanges.apply` did.
public struct NuvioSyncApplied: Equatable, Sendable {
    /// False: the live state belongs to another account, profile or reset generation than the one the pass started
    /// from; nothing was replayed (finding 10).
    public var applied: Bool
    public var merged: Int
    public var deleted: Int

    public init(applied: Bool, merged: Int, deleted: Int) {
        self.applied = applied; self.merged = merged; self.deleted = deleted
    }
}

public struct NuvioSyncChanges: Equatable, Sendable {
    public internal(set) var steps: [NuvioSyncChange] = []
    /// The state the pass started from: account, profile and reset generation (finding 10).
    public internal(set) var userID: String?
    public internal(set) var profileIndex: Int?
    public internal(set) var profileID: String?
    public internal(set) var generation = 0

    public init() {}

    init(from state: NuvioState) {
        userID = state.userID; profileIndex = state.profileIndex; profileID = state.profileID
        generation = state.generation
    }

    public var isEmpty: Bool { steps.isEmpty }

    /// Replays the pass onto other values (the live book and state). Does nothing when the live state was reset,
    /// changed account or profile since the pass started.
    @discardableResult
    public func apply(to book: inout ProgressBook, state: inout NuvioState) -> NuvioSyncApplied {
        guard state.userID == userID, state.profileIndex == profileIndex, state.profileID == profileID,
              state.generation == generation else { return NuvioSyncApplied(applied: false, merged: 0, deleted: 0) }
        var m = 0, d = 0
        for s in steps {
            let r = NuvioSync.apply(s, book: &book, state: &state)
            m += r.merged; d += r.deleted
        }
        return NuvioSyncApplied(applied: true, merged: m, deleted: d)
    }
}

public struct NuvioSyncResult: Equatable, Sendable {
    public var outcome: NuvioSyncOutcome
    public var summary: NuvioSyncSummary
    /// The book and state the pass started from with `changes` applied. Store the book first, then the state.
    public var book: ProgressBook
    public var state: NuvioState
    /// The same changes as steps, for replaying onto live values that changed during the pass.
    public var changes: NuvioSyncChanges
    /// The fresh account profile of the check (read `usesPrimaryAddons` from it, never from the state); nil when the
    /// check did not pass or the account has no profile rows.
    public var profile: NuvioProfile?

    /// Keep in memory; pass it to the next `run`.
    public var cooldownUntil: Date? {
        if case .rateLimited(let until) = outcome { return until }
        return nil
    }
}

public enum NuvioSync {
    /// Bootstrap history pages (1-based) and their size; a full page 20 ends the bootstrap all the same.
    public static let watchedPageSize = 500
    public static let maxWatchedPages = 20
    /// Delta pages per stream and pass; a full page asks for the next one.
    public static let deltaLimit = 1000
    public static let maxDeltaPages = 10
    /// No Nuvio call for this long after a 429 that survived the client's retry.
    public static let cooldown: TimeInterval = 5 * 60
    /// Title lookups for staged rows: at most this many at a time, and at most `metaPerPass` titles per pass.
    public static let lookupWidth = 4
    public static let metaPerPass = 40

    /// One pass. Never throws: every stop is an outcome, and the returned values hold what was committed before it.
    public static func run(_ mode: NuvioSyncMode = .full, session: NuvioSession, book: ProgressBook, state: NuvioState,
                           cooldownUntil: Date? = nil, using deps: NuvioSyncDependencies) async -> NuvioSyncResult {
        var p = Pass(book: book, state: state, deps: deps, session: session)
        let start = deps.now()
        if let until = cooldownUntil, start < until { return p.finish(.rateLimited(until: until)) }
        if p.state.userID != session.userID { p.record(.account(session.userID)) }
        guard let index = p.state.profileIndex else { return p.finish(.notChosen) }
        if case .pushOnly(let f) = mode, !p.state.outbox.isDue(now: start, force: f) { return p.finish(.ok) }

        let profiles: [NuvioProfile]
        do { profiles = try await deps.api.profiles(await p.current()) } catch { return p.finish(p.outcome(error)) }
        switch p.state.matches(profiles) {
        case .ok(let fresh):
            p.profile = fresh
            if p.state.profileID == nil, let id = fresh?.id, !id.isEmpty { p.record(.profilePinned(id)) }
        case .notChosen: return p.finish(.notChosen)
        case .missing: return p.finish(.profileMissing)
        case .replaced: return p.finish(.profileReplaced)
        case .pinProtected: return p.finish(.pinProtected)
        }

        if case .pushOnly(let f) = mode {
            if p.state.outbox.isDue(now: deps.now(), force: f), let stop = await p.push(index) { return p.finish(stop) }
            return p.finish(p.summary.pushError.map { .failed($0) } ?? .ok)
        }

        do {
            if !p.state.bootstrapDone { try await p.bootstrap(index) }
            if p.state.bootstrapDone { try await p.delta(index, start: start) }
        } catch {
            return p.finish(p.outcome(error))
        }
        p.record(.pulled(at: start))
        await p.resolveIDs()
        if Task.isCancelled { return p.finish(.cancelled) }
        if p.state.outbox.isDue(now: deps.now(), force: true), let stop = await p.push(index) { return p.finish(stop) }
        await p.resolveStaged()
        return p.finish(p.summary.moreToPull || p.summary.pushError != nil ? .partial : .ok)
    }

    // MARK: Applying one change

    struct Applied { var merged = 0, deleted = 0, dropped = 0, pushDropped = 0 }

    static func apply(_ c: NuvioSyncChange, book: inout ProgressBook, state: inout NuvioState) -> Applied {
        var r = Applied()
        switch c {
        case .account(let user):
            if state.userID == nil { state.userID = user } else if state.userID != user { state.resetForAccount(user) }
        case .profilePinned(let id):
            if state.profileID == nil { state.profileID = id }
        case .pushed(let sent, let at):
            state.outbox.confirm(sent.map { (key: $0.key, entry: $0.push) }, now: at)
        case .pushFailed(let at):
            state.outbox.failed(now: at)
        case .pushRefused(let sent, let at):
            if state.outbox.refused((key: sent.key, entry: sent.push), now: at) { r.pushDropped = 1 }
        case .outboxSeen(let seen):
            state.outbox.dropSeen(seen)
        case .pending(let list):
            for p in list { state.notePending(p) }
        case .idMissing(let number, let series):
            guard let i = state.pendingIDs.firstIndex(where: { $0.number == number && $0.series == series }) else { break }
            state.pendingIDs[i].attempts += 1
            if state.pendingIDs[i].attempts >= NuvioState.maxIDAttempts {
                state.pendingIDs.remove(at: i)
                state.link(NuvioIDLink(local: "tmdb:\(number)", remote: "tmdb:\(number)", series: series))
            }
        case .rekey(let from, let to, let series):
            r.merged = rekey(from: from, to: to, series: series, book: &book, state: &state)
        case .merge(let entries):
            let kept = state.filterPulled(entries)
            r.merged = book.merge(nuvio: kept)
        case .stage(let rows):
            r.dropped = state.stage(contentsOf: rows)
        case .unstage(let ids):
            let gone = Set(ids)
            state.staged.removeAll { gone.contains($0.id) }
        case .delete(let progressKeys, let watchedKeys, let before):
            let local = { (key: String) in localID(key: key, state: state) }
            let gone = Set(progressKeys.map { "p:" + $0 } + watchedKeys.map { "w:" + $0 })
            state.staged.removeAll { gone.contains($0.id) }
            let protected = Set(state.outbox.keys.compactMap(local))
            r.deleted = book.applyNuvio(deletedProgress: progressKeys.compactMap(local),
                                        watchedRemoved: watchedKeys.compactMap(local), protected: protected, before: before)
        case .skipped(let n):
            state.skipped += n
        case .bootstrapResume(let resume):
            state.bootstrapResume = resume
        case .bootstrapped(let pc, let wc):
            state.progressCursor = pc
            state.watchedCursor = wc
            state.bootstrapDone = true
            state.bootstrapResume = nil
        case .progressCursor(let c):
            state.progressCursor = c
        case .watchedCursor(let c):
            state.watchedCursor = c
        case .pulled(let at):
            state.lastPullAt = at
        }
        return r
    }

    /// The `.rekey` step: book entries (tombstones of either id judge the moved ones), tombstones, staged rows, outbox
    /// entries queued under the IMDb id (to the account's `content_id`), the link, the pending title.
    static func rekey(from: String, to: String, series: Bool, book: inout ProgressBook, state: inout NuvioState) -> Int {
        let judge = state
        let n = book.rekeyNuvio(from: from, to: to, series: series) { e in
            judge.blocks(itemID: to, updated: e.updated, finished: e.finished)
                || judge.blocks(itemID: from, updated: e.updated, finished: e.finished)
        }
        if let t = state.tombstones.filter({ $0.itemID == from }).max(by: { $0.at < $1.at }) {
            state.tombstones.removeAll { $0.itemID == from }
            if let have = state.tombstones.first(where: { $0.itemID == to }), have.at >= t.at {} else {
                state.tombstones.removeAll { $0.itemID == to }
                state.tombstones.append(NuvioTombstone(itemID: to, kind: t.kind, at: t.at))
            }
        }
        for i in state.staged.indices where state.staged[i].itemID == from && state.staged[i].isSeries == series {
            state.staged[i].itemID = to
        }
        state.outbox.rewrite(contentID: to, to: from, series: series)
        state.link(NuvioIDLink(local: to, remote: from, series: series))
        if case .tmdb(let number) = NuvioMapping.remoteID(from) {
            state.pendingIDs.removeAll { $0.number == number && $0.series == series }
        }
        return n
    }

    // MARK: Ids

    /// A progress key (`{content_id}` or `{content_id}_s{S}e{E}`) as the local progress id (with the stored links, by
    /// kind: a key with an episode is a series), or nil for an id scheme the app cannot address.
    static func localID(key: String, state: NuvioState) -> String? {
        let k = NuvioMapping.parseKey(key)
        let series = k.episode != nil
        let item: String
        if let l = state.localID(remote: k.contentID, series: series) {
            item = l
        } else {
            switch NuvioMapping.remoteID(k.contentID) {
            case .imdb(let s): item = s
            case .tmdb(let n): item = "tmdb:\(n)"
            case .other: return nil
            }
        }
        return NuvioMapping.localProgressID(itemID: item, season: k.season, episode: k.episode)
    }

    /// One delta page in ascending `event_id`, settled per key: when a key's last event is a delete, that delete
    /// stands for it (its upserts in the page are dropped); otherwise its upserts after its last delete stay, in
    /// ascending order (the merge keeps the newest). Deletes come one per key, ascending.
    static func settle<E>(_ events: [E], id: KeyPath<E, Int>, key: KeyPath<E, String>,
                          operation: KeyPath<E, NuvioOperation>) -> (upserts: [E], deletes: [E]) {
        let sorted = events.sorted { $0[keyPath: id] < $1[keyPath: id] }
        var last: [String: E] = [:]
        var lastDelete: [String: Int] = [:]
        for e in sorted {
            last[e[keyPath: key]] = e
            if e[keyPath: operation] == .delete { lastDelete[e[keyPath: key]] = e[keyPath: id] }
        }
        let upserts = sorted.filter { e in
            let k = e[keyPath: key]
            return e[keyPath: operation] == .upsert && last[k].map({ $0[keyPath: operation] == .upsert }) == true
                && e[keyPath: id] > (lastDelete[k] ?? Int.min)
        }
        let deletes = last.values.filter { $0[keyPath: operation] == .delete }.sorted { $0[keyPath: id] < $1[keyPath: id] }
        return (upserts, deletes)
    }

    static func isSeries(type: String, season: Int?, episode: Int?) -> Bool {
        ContentKind.isEpisodic(type: type) || NuvioMapping.episode(type: type, season: season, episode: episode) != nil
    }

    /// Runs `f` for every key, at most `width` at a time. Keys whose result is nil are left out.
    static func bounded<K: Hashable & Sendable, V: Sendable>(_ keys: [K], width: Int,
                                                             _ f: @escaping @Sendable (K) async -> V?) async -> [K: V] {
        var out: [K: V] = [:]
        guard !keys.isEmpty else { return out }
        await withTaskGroup(of: (K, V?).self) { group in
            var next = keys.makeIterator()
            for _ in 0..<max(1, width) {
                guard let k = next.next() else { break }
                group.addTask { (k, await f(k)) }
            }
            while let (k, v) = await group.next() {
                if let v { out[k] = v }
                if let n = next.next() { group.addTask { (n, await f(n)) } }
            }
        }
        return out
    }
}

// MARK: - The working pass

private struct TMDBKey: Hashable, Sendable {
    var number: Int
    var series: Bool
}

/// A title by local item id and kind (a film and a series may share a provisional `tmdb:N`).
private struct TitleKey: Hashable, Sendable {
    var id: String
    var series: Bool

    init(_ e: NuvioProgressEntry) { id = e.item.id; series = e.season != nil || ContentKind.isEpisodic(type: e.item.type) }
    init(_ e: WatchProgress) { id = e.item.id; series = e.season != nil || ContentKind.isEpisodic(type: e.item.type) }
}

private struct Pass {
    var book: ProgressBook
    var state: NuvioState
    let deps: NuvioSyncDependencies
    var session: NuvioSession
    var changes: NuvioSyncChanges
    var summary = NuvioSyncSummary()
    var profile: NuvioProfile?

    init(book: ProgressBook, state: NuvioState, deps: NuvioSyncDependencies, session: NuvioSession) {
        self.book = book; self.state = state; self.deps = deps; self.session = session
        changes = NuvioSyncChanges(from: state)
    }

    @discardableResult
    mutating func record(_ c: NuvioSyncChange) -> NuvioSync.Applied {
        let r = NuvioSync.apply(c, book: &book, state: &state)
        summary.merged += r.merged
        summary.deleted += r.deleted
        summary.pushDropped += r.pushDropped
        if r.dropped > 0 { summary.skipped += r.dropped; summary.moreToPull = true }
        changes.steps.append(c)
        return r
    }

    mutating func finish(_ outcome: NuvioSyncOutcome) -> NuvioSyncResult {
        summary.staged = state.staged.count
        summary.pendingIDs = state.pendingIDs.count
        return NuvioSyncResult(outcome: outcome, summary: summary, book: book, state: state, changes: changes,
                               profile: profile)
    }

    /// The session for the next call: the stored one when the app renewed it meanwhile (same account).
    mutating func current() async -> NuvioSession {
        if let read = deps.currentSession, let s = await read(), s.userID == session.userID { session = s }
        return session
    }

    func outcome(_ error: Error) -> NuvioSyncOutcome {
        if error is CancellationError { return .cancelled }
        guard let e = error as? NuvioError else { return Task.isCancelled ? .cancelled : .offline }
        switch e {
        case .signedOut: return .signedOut
        case .rateLimited: return .rateLimited(until: deps.now().addingTimeInterval(NuvioSync.cooldown))
        case .offline: return .offline
        case .status, .decoding: return .failed(e)
        }
    }

    // MARK: Push

    /// Sends the outbox in one batch. A 4xx (not 401/429) for several entries sends them one by one, so one refused
    /// entry does not block the rest; an entry refused alone counts an attempt (finding 11). Returns the outcome that
    /// ends the pass (signed out, rate limit, offline, cancelled), or nil; a refusal is kept in `summary.pushError`.
    mutating func push(_ index: Int) async -> NuvioSyncOutcome? {
        let batch = state.outbox.batch().map { NuvioSentPush(key: $0.key, push: $0.entry) }
        guard !batch.isEmpty else { return nil }
        switch await send(index, batch) {
        case .done: return nil
        case .stop(let o): return o
        case .refused(let e):
            summary.pushError = e
            guard batch.count > 1 else { record(.pushRefused(batch[0], at: deps.now())); return nil }
            for one in batch {
                switch await send(index, [one]) {
                case .done: break
                case .stop(let o): return o
                case .refused(let e): summary.pushError = e; record(.pushRefused(one, at: deps.now()))
                }
            }
            return nil
        }
    }

    enum Sent { case done, stop(NuvioSyncOutcome), refused(NuvioError) }

    mutating func send(_ index: Int, _ batch: [NuvioSentPush]) async -> Sent {
        do {
            try await deps.api.push(profile: index, batch.map(\.push), await current())
            record(.pushed(batch, at: deps.now()))
            summary.pushed += batch.count
            return .done
        } catch {
            let o = outcome(error)
            guard case .failed(let e) = o else { record(.pushFailed(at: deps.now())); return .stop(o) }
            if case .status(let code, _) = e, (400..<500).contains(code), code != 401, code != 429 { return .refused(e) }
            record(.pushFailed(at: deps.now()))
            summary.pushError = e
            return .done
        }
    }

    // MARK: Pull

    /// Cursors first, then the snapshot (newest 200 progress rows), then history pages; commits as one group. History
    /// beyond `maxWatchedPages` pages goes on in the next pass from a stored resume point (one page read again, since
    /// newer plays push items down meanwhile); the delta waits until the bootstrap is done. When staged rows had to be
    /// dropped the bootstrap is not committed and starts over in a later pass (finding 6).
    mutating func bootstrap(_ index: Int) async throws {
        let api = deps.api
        let pc: Int, wc: Int, first: Int
        var snapshot: NuvioPage<NuvioProgressRow>?
        if let r = state.bootstrapResume {
            (pc, wc, first) = (r.progressCursor, r.watchedCursor, r.nextWatchedPage)
        } else {
            pc = try await api.progressCursor(profile: index, await current())
            wc = try await api.watchedCursor(profile: index, await current())
            snapshot = try await api.progress(profile: index, await current())
            first = 1
        }
        var history: [NuvioWatchedItem] = []
        var unreadable = snapshot?.skipped ?? 0
        var complete = false
        var last = first
        for page in first..<(first + NuvioSync.maxWatchedPages) {
            let w = try await api.watched(profile: index, page: page, pageSize: NuvioSync.watchedPageSize, await current())
            history += w.rows
            unreadable += w.skipped
            last = page
            if w.received < NuvioSync.watchedPageSize { complete = true; break }
        }
        if let snapshot, snapshot.received >= NuvioClient.snapshotLimit { summary.snapshotCapped = true }
        let dropped = take(progress: snapshot?.rows ?? [], watched: history, unreadable: unreadable)
        if dropped > 0 {
            if state.bootstrapResume != nil { record(.bootstrapResume(nil)) }
            summary.moreToPull = true
        } else if complete {
            record(.bootstrapped(progressCursor: pc, watchedCursor: wc))
            summary.bootstrapped = true
        } else {
            record(.bootstrapResume(NuvioBootstrapResume(progressCursor: pc, watchedCursor: wc,
                                                         nextWatchedPage: max(first + 1, last))))
            summary.moreToPull = true
        }
    }

    /// Both delta streams from the stored cursors. Each page is applied, then its cursor step is recorded.
    mutating func delta(_ index: Int, start: Date) async throws {
        let api = deps.api
        // Deletes win only over local entries older than the last pull (the bootstrap pass: older than its start).
        let before = state.lastPullAt ?? start

        var since = state.progressCursor ?? 0
        for n in 1...NuvioSync.maxDeltaPages {
            let page = try await api.progressDelta(profile: index, since: since, limit: NuvioSync.deltaLimit, await current())
            let settled = NuvioSync.settle(page.rows, id: \.eventID, key: \.progressKey, operation: \.operation)
            take(progress: settled.upserts.compactMap(\.row), watched: [], unreadable: page.skipped)
            let deletes = settled.deletes.map(\.progressKey)
            if !deletes.isEmpty { record(.delete(progressKeys: deletes, watchedKeys: [], before: before)) }
            let next = max(since, page.lastEventID ?? page.rows.map(\.eventID).max() ?? since)
            let moved = next > since
            if moved { record(.progressCursor(next)); since = next }
            if page.received < NuvioSync.deltaLimit || !moved { break }
            if n == NuvioSync.maxDeltaPages { summary.moreToPull = true }
        }

        since = state.watchedCursor ?? 0
        for n in 1...NuvioSync.maxDeltaPages {
            let page = try await api.watchedDelta(profile: index, since: since, limit: NuvioSync.deltaLimit, await current())
            let settled = NuvioSync.settle(page.rows, id: \.eventID, key: \.item.progressKey, operation: \.operation)
            take(progress: [], watched: settled.upserts.map(\.item), unreadable: page.skipped)
            // A whole-series item (no episode) is never applied (plan section 7.8), also not as a delete.
            let deletes = settled.deletes.filter {
                !(ContentKind.isEpisodic(type: $0.item.contentType)
                  && NuvioMapping.episode(type: $0.item.contentType, season: $0.item.season, episode: $0.item.episode) == nil)
            }.map(\.item.progressKey)
            if !deletes.isEmpty { record(.delete(progressKeys: [], watchedKeys: deletes, before: before)) }
            let next = max(since, page.lastEventID ?? page.rows.map(\.eventID).max() ?? since)
            let moved = next > since
            if moved { record(.watchedCursor(next)); since = next }
            if page.received < NuvioSync.deltaLimit || !moved { break }
            if n == NuvioSync.maxDeltaPages { summary.moreToPull = true }
        }
    }

    // MARK: Taking rows

    /// Maps pulled rows to local entries and records them: ids (links by kind, else `tt…` as is and `tmdb:N` as the
    /// provisional id, noted as pending), then merge for rows with a known title, staging for the rest. Rows a
    /// tombstone would drop are neither merged nor staged. Every row's `last_watched` drops older queued pushes of
    /// its key. No lookup runs here. Returns how many staged rows had to be dropped (overflow).
    @discardableResult
    mutating func take(progress rows: [NuvioProgressRow], watched: [NuvioWatchedItem], unreadable: Int) -> Int {
        var skipped = unreadable
        let names = nameIndex()
        let now = deps.now()
        var seen: [String: Int] = [:]
        var pending: [TMDBKey: Int] = [:]
        var merge: [NuvioProgressEntry] = []
        var stage: [NuvioStaged] = []
        var unstage: [String] = []
        let state = self.state

        func local(_ cid: String, series: Bool, at: Int) -> String? {
            if let l = state.localID(remote: cid, series: series) { return l }
            switch NuvioMapping.remoteID(cid) {
            case .imdb(let s): return s
            case .tmdb(let n):
                let k = TMDBKey(number: n, series: series)
                pending[k] = max(pending[k] ?? 0, at)
                return "tmdb:\(n)"
            case .other: return nil
            }
        }

        for row in rows {
            seen[row.progressKey] = max(seen[row.progressKey] ?? 0, row.lastWatched)
            let series = NuvioSync.isSeries(type: row.contentType, season: row.season, episode: row.episode)
            guard let item = local(row.contentID, series: series, at: row.lastWatched),
                  var e = NuvioMapping.entry(row, itemID: item, name: nil, now: now) else { skipped += 1; continue }
            guard !tombstoned(e) else { continue }
            let staged = NuvioStaged(itemID: item, row: row, stagedAt: now)
            if let known = names[TitleKey(e)] {
                e.item.name = known
                merge.append(e)
                unstage.append(staged.id)
            } else {
                stage.append(staged)
            }
        }
        for w in watched {
            seen[w.progressKey] = max(seen[w.progressKey] ?? 0, w.watchedAt)
            let series = NuvioSync.isSeries(type: w.contentType, season: w.season, episode: w.episode)
            guard let item = local(w.contentID, series: series, at: w.watchedAt),
                  var e = NuvioMapping.entry(w, itemID: item, now: now) else { skipped += 1; continue }
            guard !tombstoned(e) else { continue }
            let staged = NuvioStaged(itemID: item, watched: w, stagedAt: now)
            if let known = names[TitleKey(e)] { e.item.name = known }
            if e.item.name.isEmpty {
                stage.append(staged)
            } else {
                merge.append(e)
                unstage.append(staged.id)
            }
        }

        let notes = pending.map { NuvioPendingID(number: $0.key.number, series: $0.key.series, lastWatched: $0.value) }
            .sorted { ($0.number, $0.series ? 1 : 0) < ($1.number, $1.series ? 1 : 0) }
        if !notes.isEmpty { record(.pending(notes)) }
        if !unstage.isEmpty { record(.unstage(unstage)) }
        if !merge.isEmpty { record(.merge(merge)) }
        var dropped = 0
        if !stage.isEmpty { dropped = record(.stage(stage)).dropped }
        if !seen.isEmpty, !state.outbox.isEmpty { record(.outboxSeen(seen)) }
        if skipped > 0 { record(.skipped(skipped)); summary.skipped += skipped }
        return dropped
    }

    /// Local title → name, from the book: per title the newest named entry (tie: the smallest entry id), so the
    /// choice does not depend on dictionary order (finding 5).
    func nameIndex() -> [TitleKey: String] {
        var best: [TitleKey: WatchProgress] = [:]
        for e in book.entries.values where !e.item.name.isEmpty {
            let k = TitleKey(e)
            if let b = best[k], b.updated > e.updated || (b.updated == e.updated && b.id < e.id) { continue }
            best[k] = e
        }
        return best.mapValues(\.item.name)
    }

    /// True when the tombstones would drop the entry (judged on a copy; the merge step filters for real).
    func tombstoned(_ e: NuvioProgressEntry) -> Bool {
        guard !state.tombstones.isEmpty else { return false }
        var copy = state
        return copy.filterPulled([e]).isEmpty
    }

    // MARK: Ids (finding 2)

    /// Up to `metaPerPass` pending `tmdb:` titles, newest first, looked up at most `lookupWidth` at a time. A found
    /// IMDb id re-keys the title; `notFound` counts an attempt; "unavailable" leaves it for a later pass. A cancelled
    /// task records nothing of the lookups.
    mutating func resolveIDs() async {
        let todo = state.pendingIDs.sorted {
            $0.lastWatched != $1.lastWatched ? $0.lastWatched > $1.lastWatched
                : ($0.number, $0.series ? 1 : 0) < ($1.number, $1.series ? 1 : 0)
        }.prefix(NuvioSync.metaPerPass).map { TMDBKey(number: $0.number, series: $0.series) }
        guard !todo.isEmpty else { return }
        let imdbID = deps.imdbID
        let found = await NuvioSync.bounded(todo, width: NuvioSync.lookupWidth) { k -> NuvioIDLookup? in
            await imdbID(MetaPreview(id: "tmdb:\(k.number)", type: k.series ? "series" : "movie", name: ""))
        }
        if Task.isCancelled { return }
        for k in todo {
            switch found[k] {
            case .found(let id)?:
                if case .imdb(let tt) = NuvioMapping.remoteID(id) {
                    record(.rekey(from: "tmdb:\(k.number)", to: tt, series: k.series))
                } else {
                    record(.idMissing(number: k.number, series: k.series))
                }
            case .notFound?: record(.idMissing(number: k.number, series: k.series))
            case .unavailable?, nil: continue
            }
        }
    }

    // MARK: Staged rows (plan section 1.9)

    /// Newest first, up to `metaPerPass` titles looked up (at most `lookupWidth` at a time); every staged row of a
    /// title with a known name is merged and unstaged. Unresolved rows stay for the next pass.
    mutating func resolveStaged() async {
        guard !state.staged.isEmpty else { return }
        let now = deps.now()
        let names = nameIndex()
        let ordered = state.staged.sorted { $0.lastWatched != $1.lastWatched ? $0.lastWatched > $1.lastWatched : $0.id < $1.id }
        var previews: [TitleKey: MetaPreview] = [:]
        var lookup: [TitleKey] = []
        for s in ordered {
            guard let e = entry(s, now: now) else { continue }
            let k = TitleKey(e)
            guard names[k] == nil, previews[k] == nil else { continue }
            guard lookup.count < NuvioSync.metaPerPass else { break }
            previews[k] = e.item
            lookup.append(k)
        }
        let meta = deps.meta
        let asked = previews
        let found = await NuvioSync.bounded(lookup, width: NuvioSync.lookupWidth) { k -> MetaPreview? in
            guard let p = asked[k], let m = await meta(p), !m.name.isEmpty else { return nil }
            return m
        }
        if Task.isCancelled { return }
        var merge: [NuvioProgressEntry] = []
        var unstage: [String] = []
        for s in ordered {
            guard var e = entry(s, now: now) else { unstage.append(s.id); continue }
            let k = TitleKey(e)
            if let n = names[k] {
                e.item.name = n
            } else if let m = found[k] {
                e.item.name = m.name
                e.item.poster = e.item.poster ?? m.poster
                e.item.background = e.item.background ?? m.background
            } else {
                continue
            }
            merge.append(e)
            unstage.append(s.id)
        }
        if !unstage.isEmpty { record(.unstage(unstage)) }
        if !merge.isEmpty { record(.merge(merge)) }
    }

    /// The staged row as an entry, its time clamped to when it was staged (finding 3): a future-dated row must not
    /// become newer than a local play made after it was staged.
    func entry(_ s: NuvioStaged, now: Date) -> NuvioProgressEntry? {
        let at = min(now, s.stagedAt)
        if let r = s.row { return NuvioMapping.entry(r, itemID: s.itemID, name: nil, now: at) }
        if let w = s.watched { return NuvioMapping.entry(w, itemID: s.itemID, now: at) }
        return nil
    }
}

extension NuvioWatchedItem {
    /// The progress key of the item's title (film or episode), as used for matching deletes and staged rows.
    var progressKey: String { NuvioMapping.progressKey(contentID: contentID, season: season, episode: episode) }
}
