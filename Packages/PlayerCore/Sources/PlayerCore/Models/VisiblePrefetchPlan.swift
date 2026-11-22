import Foundation

/// Wave F-k R1: quiet source prefetch for poster tiles on screen, so every visible tile can show its quality badge
/// (badges come only from known sources). Pure bookkeeping; the app (`StreamPrefetcher`) runs the searches.
/// - Tiles report on/off screen per row. A pass runs only after `debounce` without a change (scrolling stopped).
/// - A pass starts the visible tiles that still need sources: the row with the latest change first, tiles in screen
///   order; at most `maxRunning` at once and `maxStartsPerMinute`. A tile shown in two rows runs once.
/// - A tile fetched within `doneFor` (lifetime of the source cache) is never fetched again, even when the cache has
///   dropped it in the meantime (no refetch loop when more tiles are visible than the cache holds).
/// - Off screen before its start: dropped and counted as cancelled. Off screen while running: returned to the app,
///   which cancels the job (the job decides whether the search was already under way).
public struct VisiblePrefetchPlan: Sendable {
    public struct Limits: Sendable, Equatable {
        public var maxRunning: Int
        public var maxStartsPerMinute: Int
        public var debounce: TimeInterval
        public var doneFor: TimeInterval
        public var maxDone: Int

        public init(maxRunning: Int = 4, maxStartsPerMinute: Int = 24, debounce: TimeInterval = 0.4,
                    doneFor: TimeInterval = 30 * 60, maxDone: Int = 400) {
            self.maxRunning = maxRunning
            self.maxStartsPerMinute = maxStartsPerMinute
            self.debounce = debounce
            self.doneFor = doneFor
            self.maxDone = maxDone
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
    /// Visible tiles per row in screen order (first reported first).
    private var rows: [String: [String]] = [:]
    /// Rows, latest change first.
    private var rowOrder: [String] = []
    /// Running tile → rows it was started for.
    private var running: [String: Set<String>] = [:]
    /// Needed tiles the last pass could not start (no free slot): the queue.
    private var queued: Set<String> = []
    private var done: [String: Date] = [:]
    private var starts: [Date] = []
    private var changedAt: Date?
    private var marks: [String: [String: Mark]] = [:]
    private var reported: [String: Tally] = [:]

    public init(limits: Limits = Limits()) { self.limits = limits }

    public var runningCount: Int { running.count }
    public var queuedCount: Int { queued.count }
    public func isRunning(_ tile: String) -> Bool { running[tile] != nil }

    /// Earliest time of the next pass after the last change (debounce).
    public var dueAt: Date? { changedAt.map { $0.addingTimeInterval(limits.debounce) } }

    /// Tiles wait only for the per-minute limit (nothing running would trigger a pass): when the next start is free.
    public var nextStartAt: Date? {
        guard !queued.isEmpty, running.isEmpty, starts.count >= limits.maxStartsPerMinute, let first = starts.first
        else { return nil }
        return first.addingTimeInterval(60)
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
        starts.removeAll { now.timeIntervalSince($0) >= 60 }
        done = done.filter { now.timeIntervalSince($0.value) < limits.doneFor }
        var free = min(limits.maxRunning - running.count, limits.maxStartsPerMinute - starts.count)
        var out: [String] = []
        var waiting = Set<String>()
        for tile in visibleInOrder() where running[tile] == nil && done[tile] == nil {
            switch state(tile) {
            case .known:
                for r in rowsContaining(tile) where marks[r]?[tile] == nil { marks[r, default: [:]][tile] = .cached }
            case .busy, .skip:
                continue
            case .needed:
                if free > 0 {
                    free -= 1
                    running[tile] = rowsContaining(tile)
                    starts.append(now)
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
        case .cancelled:
            for r in credited where marks[r]?[tile] == nil { marks[r, default: [:]][tile] = .cancelled }
        case .known:
            for r in credited where marks[r]?[tile] == nil { marks[r, default: [:]][tile] = .cached }
        }
    }

    /// Profile switch: forget every result, keep the tiles on screen (they are fetched again for the new profile).
    /// Running jobs belong to the old profile; the app drops their `finished`.
    public mutating func resetResults(now: Date) {
        running.removeAll(); queued.removeAll(); done.removeAll(); starts.removeAll()
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
