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

    public var id: String { "\(kind.slot):\(itemID)" }

    public init(kind: SyncChangeKind, itemID: String, imdb: String?, item: MetaPreview, series: Bool,
                createdAt: Date, pending: Set<String>, confirmedAt: Date? = nil) {
        self.kind = kind; self.itemID = itemID; self.imdb = imdb; self.item = item; self.series = series
        self.createdAt = createdAt; self.pending = pending; self.confirmedAt = confirmedAt
    }

    /// Does this change concern a title with this ID (tile ID or IMDb ID)?
    public func matches(_ id: String) -> Bool { id == itemID || (imdb != nil && id == imdb) }
}

/// Wave L: per-profile queue of local changes. It keeps them until every targeted service confirmed them, so a pull
/// in between cannot bring back what the user just removed. Entries expire a short grace time after confirmation
/// (the services may still answer from a cache for a few minutes) or after 30 days at the latest.
public struct SyncQueue: Codable, Sendable, Equatable {
    public static let maxAge: TimeInterval = 30 * 24 * 3600
    public static let confirmedGrace: TimeInterval = 15 * 60
    public var schemaVersion = 1
    public var changes: [String: SyncChange] = [:]

    public init() {}

    /// Records a change; it replaces its counterpart in the same slot. Without services it is confirmed at once.
    @discardableResult
    public mutating func record(_ kind: SyncChangeKind, item: MetaPreview, imdb: String?, series: Bool,
                                services: Set<String>, now: Date = Date()) -> SyncChange {
        let targets = imdb == nil ? [] : services
        let c = SyncChange(kind: kind, itemID: item.id, imdb: imdb, item: item, series: series, createdAt: now,
                           pending: targets, confirmedAt: targets.isEmpty ? now : nil)
        changes[c.id] = c
        return c
    }

    /// A service confirmed (or definitely rejected) the change. Ignores a change that was replaced meanwhile.
    public mutating func confirm(_ id: String, service: String, createdAt: Date, now: Date = Date()) {
        guard var c = changes[id], c.createdAt == createdAt else { return }
        c.pending.remove(service)
        if c.pending.isEmpty, c.confirmedAt == nil { c.confirmedAt = now }
        changes[id] = c
    }

    /// The service is no longer connected: nothing left to confirm there.
    public mutating func drop(service: String, now: Date = Date()) {
        for (k, var c) in changes where c.pending.contains(service) {
            c.pending.remove(service)
            if c.pending.isEmpty, c.confirmedAt == nil { c.confirmedAt = now }
            changes[k] = c
        }
    }

    /// Removes expired entries; returns how many.
    @discardableResult
    public mutating func prune(now: Date = Date()) -> Int {
        let before = changes.count
        changes = changes.filter { _, c in
            if now.timeIntervalSince(c.createdAt) > Self.maxAge { return false }
            if let done = c.confirmedAt, now.timeIntervalSince(done) > Self.confirmedGrace { return false }
            return true
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
            !blocking.contains { $0.matches(r.item.id) && r.updated <= $0.createdAt }
        }
    }

    /// Remote playback entries to delete for a Continue Watching removal (only those not newer than the removal).
    public static func playbackIDs(for c: SyncChange, in remote: [RemoteProgress]) -> [Int] {
        remote.compactMap { r in
            guard let pid = r.playbackID, c.matches(r.item.id), r.updated <= c.createdAt else { return nil }
            return pid
        }
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

    public func load(profile: UUID) -> SyncQueue {
        guard let d = storage.read(name(profile)) else { return SyncQueue() }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(SyncQueue.self, from: d)) ?? SyncQueue()
    }

    public func save(_ q: SyncQueue, profile: UUID) throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try storage.write(name(profile), try enc.encode(q))
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
