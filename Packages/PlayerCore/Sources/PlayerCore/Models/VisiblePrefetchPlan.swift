import Foundation

/// Wave F-k R1: quiet source prefetch for poster tiles on screen, so every visible tile can show its quality badge
/// (badges come only from known sources). Pure bookkeeping; the app (`StreamPrefetcher`) runs the searches.
/// - Tiles report on/off screen per row. A pass runs only after `debounce` without a change (scrolling stopped) and,
///   Build 4 follow-up 2 (P3), `focusQuiet` after the last focus move (`focusMoved`): no searches while the focus
///   moves on, the focus-rest prefetch (same 1 s rest) comes first.
/// - A pass starts the visible tiles that still need sources: the row with the latest change first, tiles in screen
///   order; at most `maxRunning` at once and what the shared per-minute `budget` leaves (R2: shared with the focus
///   prefetch, which has priority; none while a page runs its own source search). A tile shown in two rows runs once.
/// - A tile fetched within `doneFor` (lifetime of the source cache) is never fetched again, even when the cache has
///   dropped it in the meantime (no refetch loop when more tiles are visible than the cache holds).
/// - Off screen before its start: dropped and counted as cancelled. Off screen while running: returned to the app,
///   which cancels the job (the job decides whether the search was already under way).
public struct VisiblePrefetchPlan: Sendable {
    public struct Limits: Sendable, Equatable {
        public var maxRunning: Int
        public var debounce: TimeInterval
        public var doneFor: TimeInterval
        public var maxDone: Int
        /// P3: quiet time after the last focus move.
        public var focusQuiet: TimeInterval

        public init(maxRunning: Int = 4, debounce: TimeInterval = 0.4,
                    doneFor: TimeInterval = 30 * 60, maxDone: Int = 400,
                    focusQuiet: TimeInterval = FocusRest.prefetchQuiet) {
            self.maxRunning = maxRunning
            self.debounce = debounce
            self.doneFor = doneFor
            self.maxDone = maxDone
            self.focusQuiet = focusQuiet
        }
    }

    /// What the app knows about a tile right now.
    public enum TileState: Sendable, Equatable {
        /// No sources known: fetch.
        case needed
        /// Sources or quality already known (badge decided): nothing to fetch, counts as „aus Cache“.
        case known
        /// A search for it runs elsewhere (focus prefetch, detail page): look again in the next pass.
        case busy
        /// Nothing to fetch now (empty result a moment ago, badges off).
        case skip
    }

    /// How a started tile ended.
    public enum Outcome: Sendable, Equatable {
        /// The search ran (with or without sources).
        case loaded
        /// Stopped before its search began.
        case cancelled
        /// Sources turned up meanwhile (another search): counts as „aus Cache“.
        case known
        /// No search target (no IMDb ID, unknown type): not retried within `doneFor`.
        case unavailable
    }

    /// Counts of one row for the log line.
    public struct Tally: Sendable, Equatable {
        public var loaded = 0
        public var cached = 0
        public var cancelled = 0

        public init(loaded: Int = 0, cached: Int = 0, cancelled: Int = 0) {
            self.loaded = loaded; self.cached = cached; self.cancelled = cancelled
        }

        /// „Vorab-Quellen: <row> n geladen, k aus Cache, m abgebrochen“
        public func logLine(row: String) -> String {
            "Vorab-Quellen: \(row) \(loaded) geladen, \(cached) aus Cache, \(cancelled) abgebrochen"
        }
    }

    private enum Mark: Sendable { case loaded, cached, cancelled }

    public let limits: Limits
    /// Wave F-k R2: the per-minute budget shared with the focus prefetch (it takes its starts from here too).
    public var budget: PrefetchBudget
    /// Visible tiles per row in screen order (first reported first).
    private var rows: [String: [String]] = [:]
    /// Rows, latest change first.
    private var rowOrder: [String] = []
    /// Running tile → rows it was started for.
    private var running: [String: Set<String>] = [:]
    /// Needed tiles the last pass could not start (no free slot): the queue.
    private var queued: Set<String> = []
    private var done: [String: Date] = [:]
    private var changedAt: Date?
    private var focusMovedAt: Date?
    private var marks: [String: [String: Mark]] = [:]
    private var reported: [String: Tally] = [:]

    public init(limits: Limits = Limits(), budget: PrefetchBudget = PrefetchBudget()) {
        self.limits = limits
        self.budget = budget
    }

    public var runningCount: Int { running.count }
    public var queuedCount: Int { queued.count }
    public func isRunning(_ tile: String) -> Bool { running[tile] != nil }

    /// Earliest time of the next pass: debounce after the last tile change, P3: and `focusQuiet` after the last focus
    /// move, whichever ends later.
    public var dueAt: Date? {
        let tiles = changedAt.map { $0.addingTimeInterval(limits.debounce) }
        let focus = focusMovedAt.map { $0.addingTimeInterval(limits.focusQuiet) }
        guard let t = tiles else { return focus }
        guard let f = focus else { return t }
        return max(t, f)
    }

    /// Build 4 follow-up 2 (P3): the focus moved to another tile; the next pass waits `focusQuiet` from now.
    public mutating func focusMoved(now: Date) { focusMovedAt = now }

    /// When the app should run the next pass: the due time while it lies ahead (a pass before it starts nothing),
    /// else the next free start of the budget for waiting tiles (`nextStartAt`); nil when nothing waits.
    public func nextPassAt(now: Date) -> Date? {
        if let due = dueAt, now < due { return due }
        return nextStartAt(now: now)
    }

    /// Tiles wait only for the per-minute budget (nothing running would trigger a pass): when the next start is
    /// free. nil while a page's own search pauses visible tiles (its end triggers the next pass).
    public func nextStartAt(now: Date) -> Date? {
        guard !queued.isEmpty, running.isEmpty else { return nil }
        return budget.nextFreeAt(.visible, now: now)
    }

    /// The tile is on screen in at least one row.
    public func isVisible(_ tile: String) -> Bool { rows.values.contains { $0.contains(tile) } }

    /// Tile on or off screen in `row`. Returns the tiles whose running job should be cancelled (now off screen
    /// everywhere). Every change restarts the debounce.
    public mutating func setTile(_ tile: String, row: String, visible: Bool, now: Date) -> [String] {
        var list = rows[row] ?? []
        if visible {
            guard !list.contains(tile) else { return [] }
            list.append(tile)
        } else {
            guard let i = list.firstIndex(of: tile) else { return [] }
            list.remove(at: i)
        }
        rows[row] = list.isEmpty ? nil : list
        changedAt = now
        rowOrder.removeAll { $0 == row }
        rowOrder.insert(row, at: 0)
        guard !visible, !isVisible(tile) else { return [] }
        if queued.remove(tile) != nil, marks[row]?[tile] == nil {
            marks[row, default: [:]][tile] = .cancelled
        }
        return running[tile] != nil ? [tile] : []
    }

    /// Tiles to start now (empty while the debounce runs). `state` says what the app knows about a tile.
    public mutating func pass(now: Date, state: (String) -> TileState) -> [String] {
        if let due = dueAt, now < due { return [] }
        done = done.filter { now.timeIntervalSince($0.value) < limits.doneFor }
        var free = min(limits.maxRunning - running.count, budget.free(.visible, now: now))
        var out: [String] = []
        var waiting = Set<String>()
        for tile in visibleInOrder() where running[tile] == nil && done[tile] == nil {
            switch state(tile) {
            case .known:
                for r in rowsContaining(tile) where marks[r]?[tile] == nil { marks[r, default: [:]][tile] = .cached }
            case .busy, .skip:
                continue
            case .needed:
                if free > 0, budget.take(.visible, now: now) {
                    free -= 1
                    running[tile] = rowsContaining(tile)
                    out.append(tile)
                } else {
                    waiting.insert(tile)
                }
            }
        }
        queued = waiting
        return out
    }

    /// A started tile ended. Credits every row it was started for or is shown in now.
    public mutating func finished(_ tile: String, outcome: Outcome, now: Date) {
        let credited = (running.removeValue(forKey: tile) ?? []).union(rowsContaining(tile))
        switch outcome {
        case .loaded:
            remember(tile, now)
            for r in credited { marks[r, default: [:]][tile] = .loaded }
        case .unavailable:
            remember(tile, now)
            budget.giveBack(now: now)   // R3 (m-R2-2): ended before any source search
        case .cancelled:
            for r in credited where marks[r]?[tile] == nil { marks[r, default: [:]][tile] = .cancelled }
        case .known:
            for r in credited where marks[r]?[tile] == nil { marks[r, default: [:]][tile] = .cached }
            budget.giveBack(now: now)
        }
    }

    /// Profile switch: forget every result, keep the tiles on screen (they are fetched again for the new profile).
    /// Running jobs belong to the old profile; the app drops their `finished`. The budget stays (the searches ran).
    public mutating func resetResults(now: Date) {
        running.removeAll(); queued.removeAll(); done.removeAll()
        marks.removeAll(); reported.removeAll()
        changedAt = now
    }

    /// Rows whose visible tiles are all decided (nothing queued or running for them) and whose counts changed since
    /// the last report. A row without visible tiles is forgotten after its report (counted again on its next visit).
    public mutating func reports() -> [(row: String, tally: Tally)] {
        var out: [(row: String, tally: Tally)] = []
        for (row, m) in marks {
            let visible = rows[row] ?? []
            let pending = visible.contains { queued.contains($0) || running[$0] != nil }
                || running.values.contains { $0.contains(row) }
            guard !pending else { continue }
            var t = Tally()
            for mark in m.values {
                switch mark {
                case .loaded: t.loaded += 1
                case .cached: t.cached += 1
                case .cancelled: t.cancelled += 1
                }
            }
            if t != reported[row] { out.append((row, t)); reported[row] = t }
            if visible.isEmpty { marks[row] = nil; reported[row] = nil }
        }
        rowOrder.removeAll { rows[$0] == nil && marks[$0] == nil }
        return out.sorted { $0.row < $1.row }
    }

    private func visibleInOrder() -> [String] {
        var seen = Set<String>(), out: [String] = []
        for row in rowOrder { for tile in rows[row] ?? [] where seen.insert(tile).inserted { out.append(tile) } }
        return out
    }

    private func rowsContaining(_ tile: String) -> Set<String> {
        Set(rows.compactMap { $0.value.contains(tile) ? $0.key : nil })
    }

    private mutating func remember(_ tile: String, _ now: Date) {
        done[tile] = now
        guard done.count > limits.maxDone else { return }
        for (k, _) in done.sorted(by: { $0.value < $1.value }).prefix(done.count - limits.maxDone) { done[k] = nil }
    }
}

/// Wave F-k R2: one per-minute budget of source searches for both prefetchers (focus rest and visible tiles), to spare
/// the addons (AIOStreams, debrid). The focus prefetch has priority: it may use every free start; visible tiles only
/// get what is left above `focusReserve`, and none while a page (detail, source list) runs its own source search.
public struct PrefetchBudget: Sendable, Equatable {
    public enum Kind: Sendable { case focus, visible }

    public let perMinute: Int
    public let focusReserve: Int
    /// Source searches of pages running now (`foregroundSearchBegan`/`Ended`).
    public private(set) var foregroundSearches = 0
    private var starts: [Date] = []

    public init(perMinute: Int = 12, focusReserve: Int = 4) {
        self.perMinute = perMinute
        self.focusReserve = focusReserve
    }

    /// Starts `kind` may take now.
    public func free(_ kind: Kind, now: Date) -> Int {
        let left = perMinute - live(now).count
        switch kind {
        case .focus: return max(0, left)
        case .visible: return foregroundSearches > 0 ? 0 : max(0, left - focusReserve)
        }
    }

    /// Takes one start if `kind` may (false otherwise).
    @discardableResult
    public mutating func take(_ kind: Kind, now: Date) -> Bool {
        starts.removeAll { now.timeIntervalSince($0) >= 60 }
        guard free(kind, now: now) > 0 else { return false }
        starts.append(now)
        return true
    }

    /// When `kind` gets its next start; nil when it has one now, or visible tiles are paused by a page's search.
    public func nextFreeAt(_ kind: Kind, now: Date) -> Date? {
        guard free(kind, now: now) == 0, kind == .focus || foregroundSearches == 0 else { return nil }
        let recent = live(now).sorted()
        let allowed = perMinute - (kind == .focus ? 0 : focusReserve)   // starts in 60 s that still leave one free
        let expire = recent.count - allowed + 1
        guard allowed > 0, expire > 0, expire <= recent.count else { return nil }
        return recent[expire - 1].addingTimeInterval(60)
    }

    /// Wave F-k R3 (m-R2-2): a started job ended before its source search (title known meanwhile, or no ID): its
    /// start is free again. Takes back the newest start of the minute (the job's own one is not tracked).
    public mutating func giveBack(now: Date) {
        if let i = starts.lastIndex(where: { now.timeIntervalSince($0) < 60 }) { starts.remove(at: i) }
    }

    public mutating func foregroundSearchBegan() { foregroundSearches += 1 }
    public mutating func foregroundSearchEnded() { foregroundSearches = max(0, foregroundSearches - 1) }

    private func live(_ now: Date) -> [Date] { starts.filter { now.timeIntervalSince($0) < 60 } }
}

/// Wave F-k R2: the source cache keeps at most `limit` titles. Entries of the visible-tile prefetch are the weak tier
/// and go first (oldest first), so they never push out what the focus prefetch or a page stored; only then the
/// oldest of the rest. (A weak entry becomes strong when a page or the focus prefetch uses it: `StreamCacheTierMarks`.)
public enum StreamCacheTiers {
    /// Keys to drop so that at most `limit` remain.
    public static func overflow(storedAt: [String: Date], weak: Set<String>, limit: Int) -> [String] {
        let excess = storedAt.count - limit
        guard excess > 0 else { return [] }
        let order = storedAt.sorted { a, b in
            let wa = weak.contains(a.key), wb = weak.contains(b.key)
            if wa != wb { return wa }
            return a.value != b.value ? a.value < b.value : a.key < b.key
        }
        return order.prefix(excess).map(\.key)
    }
}

/// Wave F-k R3: the weak-tier marks of the source cache (kept by `AppModel`, rules here so they are testable).
/// `weak`: stored entries from the visible-tile prefetch. `pending`: running searches started by it that no page or
/// focus prefetch has joined yet; their result is stored weak.
public struct StreamCacheTierMarks: Sendable, Equatable {
    public private(set) var weak: Set<String> = []
    public private(set) var pending: Set<String> = []

    public init() {}

    /// A new search for `id` starts. One of the visible-tile prefetch is weak unless it renews a usable strong entry
    /// (a partial focus/page entry stays strong); any other is strong.
    public mutating func searchStarted(_ id: String, visiblePrefetch: Bool, hasUsableEntry: Bool) {
        if visiblePrefetch, !hasUsableEntry || weak.contains(id) { pending.insert(id) } else { pending.remove(id) }
    }

    /// A page or the focus prefetch uses the entry, joins its running search, or the focus rests on its tile
    /// (R3, I-R2-1): strong from now on, also the result of a search still running.
    public mutating func keep(_ id: String) {
        weak.remove(id)
        pending.remove(id)
    }

    /// The search ended without storing anything; a previous entry keeps its tier.
    public mutating func searchDropped(_ id: String) { pending.remove(id) }

    /// The result of `id` is stored; `storedAt` is the cache with it (expired entries already out). Returns the keys
    /// to drop so that at most `limit` remain (`StreamCacheTiers.overflow`) and forgets marks of entries now gone.
    public mutating func stored(_ id: String, storedAt: [String: Date], limit: Int) -> [String] {
        if pending.remove(id) != nil { weak.insert(id) } else { weak.remove(id) }
        let drop = StreamCacheTiers.overflow(storedAt: storedAt, weak: weak, limit: limit)
        let gone = Set(drop)
        weak = weak.filter { storedAt[$0] != nil && !gone.contains($0) }
        return drop
    }

    /// Profile switch.
    public mutating func removeAll() {
        weak.removeAll()
        pending.removeAll()
    }
}

/// Wave F-k R1: which source search stands for a tile (key of the source cache, badge of the tile).
public enum PrefetchTarget {
    /// Film: its IMDb ID. Series: the started or next episode from the progress; without one S1E1 – it always exists,
    /// needs no episode list request, is what a new viewer starts with, and the releases of a series mostly share
    /// their quality. nil without IMDb ID (series: and without progress) or for other types.
    public static func streamID(type: String, imdb: String?, progress: WatchProgress?) -> String? {
        switch type {
        case "movie":
            return imdb
        case "series":
            if let p = progress, p.season != nil, p.episode != nil, !p.finished { return p.id }
            return imdb.map { "\($0):1:1" }
        default:
            return nil
        }
    }

    /// Build 4 follow-up S3: is `id` this tile's source cache key, i.e. `streamID(type:imdb:progress:)` with the
    /// latest progress of `itemID`? Same answer, but the progress is searched only when `id` can be that key (S1E1 of
    /// this series or an entry of this series; `entries` is keyed by entry ID), so a stored list does not scan the
    /// whole progress book once per tile on screen.
    public static func matches(_ id: String, type: String, imdb: String?, itemID: String, book: ProgressBook) -> Bool {
        switch type {
        case "movie":
            return imdb == id
        case "series":
            guard book.entries[id]?.item.id == itemID || imdb.map({ "\($0):1:1" }) == id else { return false }
            return streamID(type: type, imdb: imdb, progress: book.latest(forItem: itemID)) == id
        default:
            return false
        }
    }
}

/// Wave F-k R1: is a tile on screen? Its frame in screen coordinates (both scroll views already applied) must lie at
/// least `threshold` (share of its area) inside the screen.
public enum TileVisibility {
    public static func isOnScreen(_ frame: CGRect, screen: CGRect, threshold: CGFloat = 0.5) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        let w = min(frame.maxX, screen.maxX) - max(frame.minX, screen.minX)
        let h = min(frame.maxY, screen.maxY) - max(frame.minY, screen.minY)
        guard w > 0, h > 0 else { return false }
        return w * h >= threshold * frame.width * frame.height
    }
}
