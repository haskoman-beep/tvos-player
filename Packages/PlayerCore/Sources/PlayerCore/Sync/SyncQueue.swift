import Foundation

/// Wave L: a local change the sync services (Trakt/Simkl) still have to confirm.
public enum SyncChangeKind: String, Codable, Sendable, CaseIterable {
    case watchlistAdd, watchlistRemove, markWatched, markUnwatched, removeFromContinue

    /// Changes in the same slot replace each other (add ↔ remove, watched ↔ unwatched).
    public var slot: String {
        switch self {
        case .watchlistAdd, .watchlistRemove: "watchlist"
        case .markWatched, .markUnwatched: "watched"
        case .removeFromContinue: "continue"
        }
    }

    /// German name for the log.
    public var logName: String {
        switch self {
        case .watchlistAdd: "Merkliste hinzufügen"
        case .watchlistRemove: "Merkliste entfernen"
        case .markWatched: "als gesehen"
        case .markUnwatched: "als ungesehen"
        case .removeFromContinue: "aus Weiterschauen entfernen"
        }
    }
}

/// Build 2: a queued action besides the tile changes. Additive in the queue file (`actions`, `deadLetters`).
public enum SyncAction: Codable, Sendable, Equatable {
    /// A `stop` scrobble from 80 % on that did not get through: sent later as a history entry.
    /// `id`: "tt…" (movie) or "tt…:season:episode"; `progress` 0…1; `at`: when it was watched.
    case scrobbleStop(id: String, progress: Double, at: Date)
    /// A tile action on a "tmdb:" tile made while the IMDb ID could not be looked up; it waits for the lookup.
    case resolveThen(tmdbID: String, type: String, action: SyncChangeKind)
    /// A tile change that was given up (only in `deadLetters`).
    case change(SyncChange)
}

/// Decodes one element of an array; a broken or unknown one becomes nil instead of failing the array.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// One pending change (a tombstone for removals). `pending` = services that have not confirmed it yet.
public struct SyncChange: Codable, Sendable, Equatable, Identifiable {
    public var kind: SyncChangeKind
    /// Title ID as the tile shows it ("tt…" or "tmdb:…"); local matching uses this.
    public var itemID: String
    /// IMDb ID for the services; nil = the change stays local (no service can address the title).
    public var imdb: String?
    public var item: MetaPreview
    public var series: Bool
    public var createdAt: Date
    public var pending: Set<String>
    public var confirmedAt: Date?
    /// A service took it but changed nothing remotely: keep it until it expires (30 days), not just the grace time.
    public var held: Bool?
    /// Failed sends so far (nil in files of older builds = 0). Additive: older builds ignore it.
    public var attempts: Int?

    /// Keyed by the canonical title ID (IMDb first, else the tile's own TMDB or addon ID), so a TMDB tile and an
    /// IMDb tile of the same title share one entry.
    public var id: String { "\(kind.slot):\(imdb ?? itemID)" }

    public init(kind: SyncChangeKind, itemID: String, imdb: String?, item: MetaPreview, series: Bool,
                createdAt: Date, pending: Set<String>, confirmedAt: Date? = nil) {
        self.kind = kind; self.itemID = itemID; self.imdb = imdb; self.item = item; self.series = series
        self.createdAt = createdAt; self.pending = pending; self.confirmedAt = confirmedAt
    }

    /// Does this change concern a title with this ID (tile ID or IMDb ID)?
    public func matches(_ id: String) -> Bool { id == itemID || (imdb != nil && id == imdb) }
}

/// Wave L: per-profile queue of local changes. It keeps them until every targeted service confirmed them, so a pull
/// in between cannot bring back what the user just removed. Watchlist entries stay until a pull that started a grace
/// time after the confirmation has been stored (the app's own catalog cache can be a day old, and the services may
/// still answer from their cache for a few minutes); other entries expire that grace time after confirmation.
/// Everything expires after 30 days at the latest.
public struct SyncQueue: Codable, Sendable, Equatable {
    public static let maxAge: TimeInterval = 30 * 24 * 3600
    public static let confirmedGrace: TimeInterval = 5 * 60
    /// Remote timestamps up to this much after a local change still count as older (device clock drift).
    public static let clockTolerance: TimeInterval = 5
    /// After this many failed sends an entry goes to `deadLetters` and blocks nothing any more.
    public static let maxAttempts = 8
    /// Dead letters kept for the log (newest last).
    public static let maxDeadLetters = 50
    public var schemaVersion = 1
    public var changes: [String: SyncChange] = [:]
    /// Queued actions that are no tile change (failed scrobble stops, actions waiting for a TMDB→IMDb lookup).
    /// Additive key: older builds ignore it.
    public var actions: [Entry] = []
    /// Entries given up on (too many attempts or a permanent error). Additive key.
    public var deadLetters: [Entry] = []

    public init() {}

    enum CodingKeys: String, CodingKey { case schemaVersion, changes, actions, deadLetters }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? c.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? 1
        changes = try c.decode([String: SyncChange].self, forKey: .changes)
        // One unknown or broken action never costs the whole queue.
        actions = ((try? c.decodeIfPresent([Lossy<Entry>].self, forKey: .actions)) ?? []).compactMap(\.value)
        deadLetters = ((try? c.decodeIfPresent([Lossy<Entry>].self, forKey: .deadLetters)) ?? []).compactMap(\.value)
    }

    /// One queued action. `pending` = services that still have to take it.
    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var action: SyncAction
        public var createdAt: Date
        public var pending: Set<String>
        public var attempts: Int
        /// Last HTTP status of a failed send (0 = network or retry), for the log.
        public var lastStatus: Int?

        public init(id: String = UUID().uuidString, action: SyncAction, createdAt: Date, pending: Set<String>,
                    attempts: Int = 0, lastStatus: Int? = nil) {
            self.id = id; self.action = action; self.createdAt = createdAt; self.pending = pending
            self.attempts = attempts; self.lastStatus = lastStatus
        }

        enum CodingKeys: String, CodingKey { case id, action, createdAt, pending, attempts, lastStatus }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            action = try c.decode(SyncAction.self, forKey: .action)
            createdAt = try c.decode(Date.self, forKey: .createdAt)
            pending = (try? c.decodeIfPresent(Set<String>.self, forKey: .pending)) ?? []
            attempts = (try? c.decodeIfPresent(Int.self, forKey: .attempts)) ?? 0
            lastStatus = try? c.decodeIfPresent(Int.self, forKey: .lastStatus)
        }
    }

    /// Is this failed send the end of the line (permanent error, or the last allowed attempt)?
    static func givesUp(_ r: SyncWriteResult, attempts: Int) -> Bool {
        if case .rejected = r { return true }
        return attempts >= maxAttempts
    }

    private mutating func bury(_ e: Entry) {
        deadLetters.append(e)
        if deadLetters.count > Self.maxDeadLetters { deadLetters.removeFirst(deadLetters.count - Self.maxDeadLetters) }
    }

    /// Queues an action for these services (nothing is queued without services).
    @discardableResult
    public mutating func enqueue(_ action: SyncAction, services: Set<String>, now: Date = Date()) -> Entry? {
        guard !services.isEmpty else { return nil }
        let e = Entry(action: action, createdAt: now, pending: services)
        actions.append(e)
        return e
    }

    /// Actions this service still has to take, oldest first.
    public func dueActions(for service: String) -> [Entry] {
        actions.filter { $0.pending.contains(service) }.sorted { $0.createdAt < $1.createdAt }
    }

    /// The service took the action (or it is no longer needed there).
    public mutating func finish(_ id: String, service: String) {
        guard let i = actions.firstIndex(where: { $0.id == id }) else { return }
        actions[i].pending.remove(service)
        if actions[i].pending.isEmpty { actions.remove(at: i) }
    }

    /// A send failed. Returns true when the entry was given up for this service (moved to `deadLetters`).
    @discardableResult
    public mutating func fail(_ id: String, service: String, result: SyncWriteResult) -> Bool {
        guard let i = actions.firstIndex(where: { $0.id == id }) else { return false }
        actions[i].attempts += 1
        if case .rejected(let s) = result { actions[i].lastStatus = s } else { actions[i].lastStatus = 0 }
        guard Self.givesUp(result, attempts: actions[i].attempts) else { return false }
        var dead = actions[i]
        dead.pending = [service]
        bury(dead)
        finish(id, service: service)
        return true
    }

    /// A tile change failed to send. Returns true when it was given up for this service: it then counts as done
    /// there (the local state stays as the user left it) and a copy goes to `deadLetters`.
    @discardableResult
    public mutating func failChange(_ id: String, service: String, createdAt: Date, result: SyncWriteResult,
                                    now: Date = Date()) -> Bool {
        guard var c = changes[id], c.createdAt == createdAt else { return false }
        let n = (c.attempts ?? 0) + 1
        c.attempts = n
        changes[id] = c
        guard Self.givesUp(result, attempts: n) else { return false }
        var status = 0
        if case .rejected(let s) = result { status = s }
        bury(Entry(action: .change(c), createdAt: c.createdAt, pending: [service], attempts: n, lastStatus: status))
        confirm(id, service: service, createdAt: createdAt, now: now)
        return true
    }

    /// A TMDB tile resolved to an IMDb ID: the local change waiting for it gets the ID and goes to the services.
    /// Returns how many waiting actions were settled.
    @discardableResult
    public mutating func resolve(tmdbID: String, imdb: String, services: Set<String>, now: Date = Date()) -> Int {
        let waiting = actions.filter { e in
            if case .resolveThen(let t, _, _) = e.action { return t == tmdbID }
            return false
        }
        for e in waiting {
            guard case .resolveThen(_, let type, let kind) = e.action else { continue }
            let old = changes.values.first { $0.kind == kind && $0.matches(tmdbID) && $0.createdAt == e.createdAt }
            // A newer change in the slot made meanwhile wins (the user changed their mind).
            if old == nil, changes.values.contains(where: { $0.kind.slot == kind.slot && ($0.matches(imdb) || $0.matches(tmdbID)) }) { continue }
            var c = old ?? SyncChange(kind: kind, itemID: tmdbID, imdb: nil, item: MetaPreview(id: tmdbID, type: type, name: tmdbID),
                                      series: ContentKind.isEpisodic(type: type), createdAt: e.createdAt, pending: [])
            if let old { changes[old.id] = nil }
            c.imdb = imdb
            c.pending = services
            c.confirmedAt = services.isEmpty ? now : nil
            changes = changes.filter { _, o in o.kind.slot != kind.slot || !o.matches(imdb) }
            changes[c.id] = c
        }
        actions.removeAll { w in waiting.contains { $0.id == w.id } }
        return waiting.count
    }

    /// Records a change; it replaces its counterpart in the same slot. Without services it is confirmed at once.
    @discardableResult
    public mutating func record(_ kind: SyncChangeKind, item: MetaPreview, imdb: String?, series: Bool,
                                services: Set<String>, now: Date = Date()) -> SyncChange {
        let targets = imdb == nil ? [] : services
        let c = SyncChange(kind: kind, itemID: item.id, imdb: imdb, item: item, series: series, createdAt: now,
                           pending: targets, confirmedAt: targets.isEmpty ? now : nil)
        changes = changes.filter { _, o in o.kind.slot != kind.slot || !(o.matches(item.id) || (imdb != nil && o.matches(imdb!))) }
        changes[c.id] = c
        return c
    }

    /// A service confirmed (or definitely rejected) the change. Ignores a change that was replaced meanwhile.
    /// `held`: the service is done with it but nothing changed remotely, so the entry stays until it expires.
    public mutating func confirm(_ id: String, service: String, createdAt: Date, held: Bool = false, now: Date = Date()) {
        guard var c = changes[id], c.createdAt == createdAt else { return }
        c.pending.remove(service)
        if held { c.held = true }
        if c.pending.isEmpty, c.confirmedAt == nil { c.confirmedAt = now }
        changes[id] = c
    }

    /// The service is no longer connected: nothing left to confirm there.
    public mutating func drop(service: String, now: Date = Date()) {
        for e in actions where e.pending.contains(service) { finish(e.id, service: service) }
        for (k, var c) in changes where c.pending.contains(service) {
            c.pending.remove(service)
            if c.pending.isEmpty, c.confirmedAt == nil { c.confirmedAt = now }
            changes[k] = c
        }
    }

    /// Removes expired entries; returns how many.
    @discardableResult
    public mutating func prune(now: Date = Date()) -> Int {
        actions.removeAll { now.timeIntervalSince($0.createdAt) > Self.maxAge }
        deadLetters.removeAll { now.timeIntervalSince($0.createdAt) > Self.maxAge }
        let before = changes.count
        changes = changes.filter { _, c in
            if now.timeIntervalSince(c.createdAt) > Self.maxAge { return false }
            if c.kind.slot == "watchlist" || c.held == true { return true }   // see notePull
            if let done = c.confirmedAt, now.timeIntervalSince(done) > Self.confirmedGrace { return false }
            return true
        }
        return before - changes.count
    }

    /// A watchlist pull that started at `startedAt` has been stored in the catalog cache: confirmed watchlist
    /// entries older than that pull (by the grace time) are no longer needed. Returns how many went.
    @discardableResult
    public mutating func notePull(watchlistStartedAt startedAt: Date) -> Int {
        let before = changes.count
        changes = changes.filter { _, c in
            guard c.kind.slot == "watchlist", c.held != true, let done = c.confirmedAt else { return true }
            return startedAt.timeIntervalSince(done) < Self.confirmedGrace
        }
        return before - changes.count
    }

    /// Changes this service still has to confirm, oldest first.
    public func due(for service: String) -> [SyncChange] {
        changes.values.filter { $0.pending.contains(service) }.sorted { $0.createdAt < $1.createdAt }
    }

    public var pendingCount: Int { changes.values.filter { !$0.pending.isEmpty }.count }

    private func change(_ slot: String, for id: String) -> SyncChange? {
        changes.values.first { $0.kind.slot == slot && $0.matches(id) }
    }

    /// Watchlist as the services report it, with the local pending changes applied (adds first, removals gone).
    public func applyWatchlist(_ items: [MetaPreview]) -> [MetaPreview] {
        let removed = changes.values.filter { $0.kind == .watchlistRemove }
        var out = items.filter { m in !removed.contains { $0.matches(m.id) } }
        let added = changes.values.filter { $0.kind == .watchlistAdd }.sorted { $0.createdAt > $1.createdAt }
        let fresh = added.filter { c in !out.contains { c.matches($0.id) } }.map(\.item)
        out.insert(contentsOf: fresh, at: 0)
        return out
    }

    /// Is the title on the watchlist? `remote` = what the last pull said.
    public func isOnWatchlist(_ id: String, remote: Bool) -> Bool {
        switch change("watchlist", for: id)?.kind {
        case .watchlistAdd?: true
        case .watchlistRemove?: false
        default: remote
        }
    }

    /// Drops pulled progress that a local change overrides: a removal from Continue Watching or a watched/unwatched
    /// mark made after the remote state. Progress made later elsewhere passes.
    public func filterRemote(_ remote: [RemoteProgress]) -> [RemoteProgress] {
        let blocking = changes.values.filter { $0.kind != .watchlistAdd && $0.kind != .watchlistRemove }
        return remote.filter { r in
            !blocking.contains { $0.matches(r.item.id) && r.updated <= $0.createdAt.addingTimeInterval(Self.clockTolerance) }
        }
    }

    /// Remote playback entries to delete for a Continue Watching removal (only those not newer than the removal).
    public static func playbackIDs(for c: SyncChange, in remote: [RemoteProgress]) -> [Int] {
        playbackPlan(for: c, in: remote).ids
    }

    /// What a Continue Watching removal can delete: entry IDs, and how many matching entries carry no ID.
    public static func playbackPlan(for c: SyncChange, in remote: [RemoteProgress]) -> (ids: [Int], withoutID: Int) {
        let matching = remote.filter { c.matches($0.item.id) && $0.updated <= c.createdAt.addingTimeInterval(clockTolerance) }
        let ids = matching.compactMap(\.playbackID)
        return (ids, matching.count - ids.count)
    }
}

/// Wave L: how a service answered a write.
public enum SyncWriteResult: Sendable, Equatable {
    /// Done (2xx, or 404 when deleting something that is already gone).
    case confirmed
    /// Try again later (network, 401, 408, 429, 5xx).
    case retry
    /// The service will never accept it (other 4xx); stop asking.
    case rejected(Int)
    /// Deliberately not sent (no safe call for it); counts as done. The text is a German log line.
    case skipped(String)
    /// Sent, but nothing could be changed remotely (no entry or no entry ID): stays pending until it expires.
    case unconfirmed(String)

    public static func classify(status: Int, deleting: Bool = false) -> SyncWriteResult {
        if (200..<300).contains(status) || (deleting && status == 404) { return .confirmed }
        if status == 0 || status == 401 || status == 408 || status == 429 || status >= 500 { return .retry }
        if (400..<500).contains(status) { return .rejected(status) }
        return .retry
    }
}

/// Wave L: one per profile, syncqueue-<id>.json.
public struct SyncQueueStore: Sendable {
    public let storage: BlobStorage
    public init(storage: BlobStorage) { self.storage = storage }
    func name(_ profile: UUID) -> String { "syncqueue-\(profile.uuidString).json" }

    /// `failed` is called when a file exists but cannot be read (the queue then starts empty).
    public func load(profile: UUID, failed: (() -> Void)? = nil) -> SyncQueue {
        guard let d = storage.read(name(profile)) else { return SyncQueue() }
        // Default date coding keeps sub-seconds, so `confirm(createdAt:)` still matches after a reload.
        // Files of the first build used ISO-8601 dates and tile-ID keys: read those too and re-key.
        let iso = JSONDecoder(); iso.dateDecodingStrategy = .iso8601
        guard var q = (try? JSONDecoder().decode(SyncQueue.self, from: d)) ?? (try? iso.decode(SyncQueue.self, from: d)) else {
            failed?()
            return SyncQueue()
        }
        q.changes = Dictionary(q.changes.values.map { ($0.id, $0) }) { a, b in a.createdAt >= b.createdAt ? a : b }
        return q
    }

    public func remove(profile: UUID) { storage.remove(name(profile)) }

    public func save(_ q: SyncQueue, profile: UUID) throws {
        try storage.write(name(profile), try JSONEncoder().encode(q))
    }
}

// MARK: Local side of the tile actions

extension ProgressBook {
    /// Tile shows "watched": a finished movie, or a series marked as watched as a whole.
    public func isTileWatched(_ itemID: String) -> Bool { entries[itemID]?.finished == true }

    /// Marks a title as watched. Series: a whole-series marker; its unfinished episodes leave Continue Watching.
    public mutating func markWatched(item: MetaPreview, series: Bool, now: Date = Date()) {
        if series { entries = entries.filter { $0.value.item.id != item.id || $0.value.finished } }
        let old = entries[item.id]
        entries[item.id] = WatchProgress(id: item.id, item: item, position: 0, duration: old?.duration ?? 0,
                                         updated: now, finished: true)
    }

    /// A playback ended past the services' watched threshold: the entry counts as watched locally too.
    public mutating func markFinished(id: String) {
        guard var e = entries[id], !e.finished else { return }
        e.finished = true
        entries[id] = e
    }

    /// Marks a title as unwatched: all local progress of it goes (movie entry, or every episode of the series).
    public mutating func markUnwatched(itemID: String) {
        entries = entries.filter { $0.key != itemID && $0.value.item.id != itemID }
    }

    /// Removes a title from Continue Watching; finished entries (history) stay. Returns how many entries went.
    @discardableResult
    public mutating func removeFromContinueWatching(itemID: String) -> Int {
        let before = entries.count
        entries = entries.filter { ($0.key != itemID && $0.value.item.id != itemID) || $0.value.finished }
        return before - entries.count
    }

    /// New episode progress replaces an older whole-series "watched" marker, so the tile shows the episode again.
    mutating func clearSeriesMarker(itemID: String, episodeID: String, updated: Date) {
        guard itemID != episodeID, let m = entries[itemID], m.season == nil, m.updated <= updated else { return }
        entries[itemID] = nil
    }
}

// MARK: Tile context menu

/// Wave L: entries of the long-press menu on a poster/tile, in display order.
public enum TileMenuAction: String, Sendable, CaseIterable {
    case watchlistAdd, watchlistRemove, markWatched, markUnwatched, removeFromContinue, openDetail

    public var title: String {
        switch self {
        case .watchlistAdd: "Auf die Merkliste"
        case .watchlistRemove: "Von der Merkliste entfernen"
        case .markWatched: "Als gesehen markieren"
        case .markUnwatched: "Als ungesehen markieren"
        case .removeFromContinue: "Aus „Weiterschauen“ entfernen"
        case .openDetail: "Zur Detailseite"
        }
    }

    /// `watchlistAvailable`: a service with a watchlist is connected. `inContinueRow`: the tile sits in that row.
    public static func menu(watchlistAvailable: Bool, onWatchlist: Bool, watched: Bool, inContinueRow: Bool) -> [TileMenuAction] {
        var out: [TileMenuAction] = []
        if watchlistAvailable { out.append(onWatchlist ? .watchlistRemove : .watchlistAdd) }
        out.append(watched ? .markUnwatched : .markWatched)
        if inContinueRow { out.append(.removeFromContinue) }
        out.append(.openDetail)
        return out
    }

    /// Does the action take the tile out of the row it sits in (focus must move to a neighbour first)?
    public func removesTile(inContinueRow: Bool, inWatchlistRow: Bool) -> Bool {
        switch self {
        case .removeFromContinue, .markWatched: inContinueRow
        case .watchlistRemove: inWatchlistRow
        default: false
        }
    }

    /// Where focus goes when the tile at `index` leaves a row of `count` tiles: right neighbour first, then left;
    /// nil = the row becomes empty.
    public static func neighbour(removing index: Int, count: Int) -> Int? {
        if index + 1 < count { return index + 1 }
        if index > 0, index - 1 < count { return index - 1 }
        return nil
    }

    /// The queue change this action records (nil = navigation only).
    public var change: SyncChangeKind? {
        switch self {
        case .watchlistAdd: .watchlistAdd
        case .watchlistRemove: .watchlistRemove
        case .markWatched: .markWatched
        case .markUnwatched: .markUnwatched
        case .removeFromContinue: .removeFromContinue
        case .openDetail: nil
        }
    }
}
