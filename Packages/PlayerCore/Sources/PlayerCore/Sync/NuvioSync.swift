import Foundation

// Nuvio account sync, T7: one sync pass as pure orchestration (plan sections 1.7–1.9, addendum A3, A4, A8, D3, D4).
// Profile check → push the outbox → bootstrap or delta pull → merge → state update. No timer, no sleep, no storage:
// the client calls, the id and title lookups and the clock are injected; book and state go in and come out by value.
// The app owns persistence, the single-flight token refresh, the cooldown memory and the triggers.
//
// Consistency: every change is recorded as a `NuvioSyncChange` and applied at once to the working copy. A cursor
// step is recorded only after the changes of its page, so whatever the pass returns (also after an error midway)
// never has a cursor past data that is not in the returned book. A bootstrap commits as one group (rows, cursors,
// `bootstrapDone`) or not at all. Merging is newer-wins with a tie keeping local, so a page applied twice changes
// nothing, and a second pass after any interruption converges.

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

/// Everything a pass reaches outside itself.
public struct NuvioSyncDependencies: Sendable {
    public var api: any NuvioSyncAPI
    /// `tmdb:N` → IMDb id. Gets a nameless preview (`id` = `tmdb:N`, `type` = `movie` or `series`), the form of the
    /// app's `imdbID(for:)`. nil: the title keeps `tmdb:N` as its local item id.
    public var imdbID: @Sendable (MetaPreview) async -> String?
    /// Title (and artwork) for a nameless pulled row. Gets the local item preview without a name; nil or an empty
    /// name: the row stays staged and is tried again at the next pass.
    public var meta: @Sendable (MetaPreview) async -> MetaPreview?
    public var now: @Sendable () -> Date

    public init(api: any NuvioSyncAPI, imdbID: @escaping @Sendable (MetaPreview) async -> String?,
                meta: @escaping @Sendable (MetaPreview) async -> MetaPreview?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.api = api; self.imdbID = imdbID; self.meta = meta; self.now = now
    }
}

public enum NuvioSyncMode: Equatable, Sendable {
    /// Push (always, when something waits), then pull. App start, profile switch, foreground, after playback.
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
    /// The push the account refused with a status or an unreadable answer (the pull still ran; the outbox is kept).
    public var pushError: NuvioError?

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
    case pushed([NuvioSentPush], at: Date)
    case pushFailed(at: Date)
    /// Local item id → `content_id` as the account has it.
    case remoteIDs([String: String])
    /// Pulled entries, filtered with the tombstones (A4) and merged.
    case merge([NuvioProgressEntry])
    /// Nameless rows that wait for a title.
    case stage([NuvioStaged])
    /// Staged rows (by `NuvioStaged.id`) that were merged or replaced.
    case unstage([String])
    /// Delete events by progress key (translated to local ids when applied; staged rows of the keys go too).
    case delete(progressKeys: [String], watchedKeys: [String], before: Date)
    case skipped(Int)
    /// Bootstrap committed: cursors captured before the snapshot, `bootstrapDone`.
    case bootstrapped(progressCursor: Int, watchedCursor: Int)
    case progressCursor(Int)
    case watchedCursor(Int)
    case pulled(at: Date)
}

public struct NuvioSyncChanges: Equatable, Sendable {
    public internal(set) var steps: [NuvioSyncChange] = []
    public init() {}
    public var isEmpty: Bool { steps.isEmpty }

    /// Replays the pass onto other values (the live book and state). Returns how many entries were merged and
    /// removed.
    @discardableResult
    public func apply(to book: inout ProgressBook, state: inout NuvioState) -> (merged: Int, deleted: Int) {
        var m = 0, d = 0
        for s in steps {
            let r = NuvioSync.apply(s, book: &book, state: &state)
            m += r.merged; d += r.deleted
        }
        return (m, d)
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
        let force: Bool
        switch mode {
        case .full: force = true
        case .pushOnly(let f):
            force = f
            guard p.state.outbox.isDue(now: start, force: f) else { return p.finish(.ok) }
        }

        let profiles: [NuvioProfile]
        do { profiles = try await deps.api.profiles(session) } catch { return p.finish(p.outcome(error)) }
        switch p.state.matches(profiles) {
        case .ok(let fresh): p.profile = fresh
        case .notChosen: return p.finish(.notChosen)
        case .missing: return p.finish(.profileMissing)
        case .replaced: return p.finish(.profileReplaced)
        case .pinProtected: return p.finish(.pinProtected)
        }

        if p.state.outbox.isDue(now: deps.now(), force: force) {
            let batch = p.state.outbox.batch()
            do {
                try await deps.api.push(profile: index, batch.map(\.entry), session)
                p.record(.pushed(batch.map { NuvioSentPush(key: $0.key, push: $0.entry) }, at: deps.now()))
                p.summary.pushed = batch.count
            } catch {
                p.record(.pushFailed(at: deps.now()))
                let o = p.outcome(error)
                guard case .failed(let e) = o, mode == .full else { return p.finish(o) }
                p.summary.pushError = e
            }
        }
        if mode != .full { return p.finish(.ok) }

        do {
            if !p.state.bootstrapDone { try await p.bootstrap(index) }
            try await p.delta(index, start: start)
        } catch {
            return p.finish(p.outcome(error))
        }
        p.record(.pulled(at: start))
        await p.resolveStaged()
        return p.finish(p.summary.moreToPull || p.summary.pushError != nil ? .partial : .ok)
    }

    // MARK: Applying one change

    static func apply(_ c: NuvioSyncChange, book: inout ProgressBook, state: inout NuvioState) -> (merged: Int, deleted: Int) {
        switch c {
        case .account(let user):
            if state.userID == nil { state.userID = user } else if state.userID != user { state.resetForAccount(user) }
        case .pushed(let sent, let at):
            state.outbox.confirm(sent.map { (key: $0.key, entry: $0.push) }, now: at)
        case .pushFailed(let at):
            state.outbox.failed(now: at)
        case .remoteIDs(let ids):
            state.remoteIDs.merge(ids) { _, new in new }
        case .merge(let entries):
            let kept = state.filterPulled(entries)
            return (book.merge(nuvio: kept), 0)
        case .stage(let rows):
            for r in rows { state.stage(r) }
        case .unstage(let ids):
            let gone = Set(ids)
            state.staged.removeAll { gone.contains($0.id) }
        case .delete(let progressKeys, let watchedKeys, let before):
            let reverse = reverseIDs(state.remoteIDs)
            let local = { (key: String) in localID(key: key, reverse: reverse) }
            let gone = Set(progressKeys.map { "p:" + $0 } + watchedKeys.map { "w:" + $0 })
            state.staged.removeAll { gone.contains($0.id) }
            let protected = Set(state.outbox.keys.compactMap(local))
            let n = book.applyNuvio(deletedProgress: progressKeys.compactMap(local),
                                    watchedRemoved: watchedKeys.compactMap(local), protected: protected, before: before)
            return (0, n)
        case .skipped(let n):
            state.skipped += n
        case .bootstrapped(let pc, let wc):
            state.progressCursor = pc
            state.watchedCursor = wc
            state.bootstrapDone = true
        case .progressCursor(let c):
            state.progressCursor = c
        case .watchedCursor(let c):
            state.watchedCursor = c
        case .pulled(let at):
            state.lastPullAt = at
        }
        return (0, 0)
    }

    // MARK: Ids

    /// `content_id` → local item id, from the stored round-trip map. Several local ids for one remote form: the
    /// smallest wins (deterministic).
    static func reverseIDs(_ remoteIDs: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (local, remote) in remoteIDs where out[remote].map({ local < $0 }) ?? true { out[remote] = local }
        return out
    }

    /// A progress key (`{content_id}` or `{content_id}_s{S}e{E}`) as the local progress id, or nil for an id scheme
    /// the app cannot address.
    static func localID(key: String, reverse: [String: String]) -> String? {
        let k = NuvioMapping.parseKey(key)
        let item: String
        if let l = reverse[k.contentID] {
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

private struct Pass {
    var book: ProgressBook
    var state: NuvioState
    let deps: NuvioSyncDependencies
    let session: NuvioSession
    var changes = NuvioSyncChanges()
    var summary = NuvioSyncSummary()
    var profile: NuvioProfile?

    init(book: ProgressBook, state: NuvioState, deps: NuvioSyncDependencies, session: NuvioSession) {
        self.book = book; self.state = state; self.deps = deps; self.session = session
    }

    mutating func record(_ c: NuvioSyncChange) {
        let r = NuvioSync.apply(c, book: &book, state: &state)
        summary.merged += r.merged
        summary.deleted += r.deleted
        changes.steps.append(c)
    }

    mutating func finish(_ outcome: NuvioSyncOutcome) -> NuvioSyncResult {
        summary.staged = state.staged.count
        return NuvioSyncResult(outcome: outcome, summary: summary, book: book, state: state, changes: changes,
                               profile: profile)
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

    // MARK: Pull

    /// Cursors first, then the snapshot (newest 200 progress rows), then history pages; commits as one group.
    mutating func bootstrap(_ index: Int) async throws {
        let api = deps.api
        let pc = try await api.progressCursor(profile: index, session)
        let wc = try await api.watchedCursor(profile: index, session)
        let snapshot = try await api.progress(profile: index, session)
        var history: [NuvioWatchedItem] = []
        var unreadable = snapshot.skipped
        for page in 1...NuvioSync.maxWatchedPages {
            let w = try await api.watched(profile: index, page: page, pageSize: NuvioSync.watchedPageSize, session)
            history += w.rows
            unreadable += w.skipped
            if w.received < NuvioSync.watchedPageSize { break }
        }
        await take(progress: snapshot.rows, watched: history, unreadable: unreadable)
        record(.bootstrapped(progressCursor: pc, watchedCursor: wc))
        summary.bootstrapped = true
    }

    /// Both delta streams from the stored cursors. Each page is applied, then its cursor step is recorded.
    mutating func delta(_ index: Int, start: Date) async throws {
        let api = deps.api
        let session = self.session
        // Deletes win only over local entries older than the last pull (the bootstrap pass: older than its start).
        let before = state.lastPullAt ?? start

        var since = state.progressCursor ?? 0
        for n in 1...NuvioSync.maxDeltaPages {
            let page = try await api.progressDelta(profile: index, since: since, limit: NuvioSync.deltaLimit, session)
            let settled = NuvioSync.settle(page.rows, id: \.eventID, key: \.progressKey, operation: \.operation)
            await take(progress: settled.upserts.compactMap(\.row), watched: [], unreadable: page.skipped)
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
            let page = try await api.watchedDelta(profile: index, since: since, limit: NuvioSync.deltaLimit, session)
            let settled = NuvioSync.settle(page.rows, id: \.eventID, key: \.item.progressKey, operation: \.operation)
            await take(progress: [], watched: settled.upserts.map(\.item), unreadable: page.skipped)
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

    /// Maps pulled rows to local entries and records them: ids (with the round-trip map), then merge for rows with a
    /// known title, staging for the rest. Rows a tombstone would drop are neither merged nor staged.
    mutating func take(progress rows: [NuvioProgressRow], watched: [NuvioWatchedItem], unreadable: Int) async {
        var skipped = unreadable
        let items = await itemIDs(rows.map { ($0.contentID, NuvioSync.isSeries(type: $0.contentType, season: $0.season,
                                                                                  episode: $0.episode)) }
                                  + watched.map { ($0.contentID, NuvioSync.isSeries(type: $0.contentType,
                                                                                      season: $0.season,
                                                                                      episode: $0.episode)) })
        let names = nameIndex()
        let now = deps.now()
        var newIDs: [String: String] = [:]
        var merge: [NuvioProgressEntry] = []
        var stage: [NuvioStaged] = []
        var unstage: [String] = []

        for row in rows {
            guard let item = items[row.contentID],
                  var e = NuvioMapping.entry(row, itemID: item, name: nil, now: now) else { skipped += 1; continue }
            guard !tombstoned(e) else { continue }
            if item != row.contentID { newIDs[item] = row.contentID }
            let staged = NuvioStaged(itemID: item, row: row, stagedAt: now)
            if let known = names[item] {
                e.item.name = known
                merge.append(e)
                unstage.append(staged.id)
            } else {
                stage.append(staged)
            }
        }
        for w in watched {
            guard let item = items[w.contentID],
                  var e = NuvioMapping.entry(w, itemID: item, now: now) else { skipped += 1; continue }
            guard !tombstoned(e) else { continue }
            if item != w.contentID { newIDs[item] = w.contentID }
            let staged = NuvioStaged(itemID: item, watched: w, stagedAt: now)
            if let known = names[item] { e.item.name = known }
            if e.item.name.isEmpty {
                stage.append(staged)
            } else {
                merge.append(e)
                unstage.append(staged.id)
            }
        }

        if !newIDs.isEmpty { record(.remoteIDs(newIDs)) }
        if !unstage.isEmpty { record(.unstage(unstage)) }
        if !merge.isEmpty { record(.merge(merge)) }
        if !stage.isEmpty { record(.stage(stage)) }
        if skipped > 0 { record(.skipped(skipped)); summary.skipped += skipped }
    }

    /// `content_id` → local item id. `tt…` stays; `tmdb:N` uses the round-trip map, then the lookup (at most
    /// `lookupWidth` at a time), else stays `tmdb:N`; other schemes are left out.
    func itemIDs(_ ids: [(String, Bool)]) async -> [String: String] {
        let reverse = NuvioSync.reverseIDs(state.remoteIDs)
        var out: [String: String] = [:]
        var lookups: [String: TMDBKey] = [:]
        for (cid, series) in ids where out[cid] == nil && lookups[cid] == nil {
            if let l = reverse[cid] { out[cid] = l; continue }
            switch NuvioMapping.remoteID(cid) {
            case .imdb(let s): out[cid] = s
            case .tmdb(let n): lookups[cid] = TMDBKey(number: n, series: series)
            case .other: break
            }
        }
        let keys = Array(Set(lookups.values)).sorted { ($0.number, $0.series ? 1 : 0) < ($1.number, $1.series ? 1 : 0) }
        let imdbID = deps.imdbID
        let found = await NuvioSync.bounded(keys, width: NuvioSync.lookupWidth) { k -> String? in
            let id = await imdbID(MetaPreview(id: "tmdb:\(k.number)", type: k.series ? "series" : "movie", name: ""))
            guard let id, case .imdb = NuvioMapping.remoteID(id) else { return nil }
            return id
        }
        for (cid, k) in lookups { out[cid] = found[k] ?? "tmdb:\(k.number)" }
        return out
    }

    /// Local item id → title, from the book (any entry of the title with a name).
    func nameIndex() -> [String: String] {
        var out: [String: String] = [:]
        for e in book.entries.values where !e.item.name.isEmpty { out[e.item.id] = e.item.name }
        return out
    }

    /// True when the tombstones would drop the entry (judged on a copy; the merge step filters for real).
    func tombstoned(_ e: NuvioProgressEntry) -> Bool {
        guard !state.tombstones.isEmpty else { return false }
        var copy = state
        return copy.filterPulled([e]).isEmpty
    }

    // MARK: Staged rows (plan section 1.9)

    /// Newest first, up to `metaPerPass` titles looked up (at most `lookupWidth` at a time); every staged row of a
    /// title with a known name is merged and unstaged. Unresolved rows stay for the next pass.
    mutating func resolveStaged() async {
        guard !state.staged.isEmpty else { return }
        let now = deps.now()
        let names = nameIndex()
        let ordered = state.staged.sorted { $0.lastWatched != $1.lastWatched ? $0.lastWatched > $1.lastWatched : $0.id < $1.id }
        var previews: [String: MetaPreview] = [:]
        var lookup: [String] = []
        for s in ordered where names[s.itemID] == nil && previews[s.itemID] == nil {
            guard lookup.count < NuvioSync.metaPerPass else { break }
            guard let e = entry(s, now: now) else { continue }
            previews[s.itemID] = e.item
            lookup.append(s.itemID)
        }
        let meta = deps.meta
        let asked = previews
        let found = await NuvioSync.bounded(lookup, width: NuvioSync.lookupWidth) { id -> MetaPreview? in
            guard let p = asked[id], let m = await meta(p), !m.name.isEmpty else { return nil }
            return m
        }
        var merge: [NuvioProgressEntry] = []
        var unstage: [String] = []
        for s in ordered {
            guard var e = entry(s, now: now) else { unstage.append(s.id); continue }
            if let n = names[s.itemID] {
                e.item.name = n
            } else if let m = found[s.itemID] {
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

    func entry(_ s: NuvioStaged, now: Date) -> NuvioProgressEntry? {
        if let r = s.row { return NuvioMapping.entry(r, itemID: s.itemID, name: nil, now: now) }
        if let w = s.watched { return NuvioMapping.entry(w, itemID: s.itemID, now: now) }
        return nil
    }
}

extension NuvioWatchedItem {
    /// The progress key of the item's title (film or episode), as used for matching deletes and staged rows.
    var progressKey: String { NuvioMapping.progressKey(contentID: contentID, season: season, episode: episode) }
}
