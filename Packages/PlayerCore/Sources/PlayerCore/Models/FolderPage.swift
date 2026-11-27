import Foundation

/// Build 7 (folder): the row page of a folder (studio and streaming tiles). Device test b6-1: kit folders
/// (Fusion Widget Manager collections) list one addon catalog per type, both named after the tile ("Shudder" twice:
/// films and series), and AIOMetadata answers a first request in 3–11 s. The page showed only faint placeholder
/// tiles under two equal headings; it looked empty and each source seemed to load twice.
public enum FolderPage {
    /// Rows the page shows: sources with the same request once (first wins), and titles that several rows share
    /// get the media type (" · Filme" / " · Serien"), so two rows never carry the same heading.
    /// IDs stay unchanged (cache, shared loads and the disk cache key on them).
    public static func rows(_ sources: [CatalogSource]) -> [CatalogSource] {
        var seen = Set<RequestKey>()
        let unique = sources.filter { seen.insert(RequestKey($0)).inserted }
        var count: [String: Int] = [:]
        for s in unique { count[s.title, default: 0] += 1 }
        return unique.map { s in
            guard count[s.title, default: 0] > 1, let suffix = suffix(s), !s.title.hasSuffix(suffix) else { return s }
            var t = s
            t.title = s.title + suffix
            return t
        }
    }

    /// Sources of a folder worth loading ahead when its tile rests in focus: not cached yet, at most `limit`
    /// (the first rows are the ones on screen when the page opens). Review b7 M1: 2, not 4.
    public static func prefetchSources(_ sources: [CatalogSource], isCached: (String) -> Bool,
                                       limit: Int = 2) -> [CatalogSource] {
        Array(rows(sources).filter { isPrefetchable($0) && !isCached($0.id) }.prefix(limit))
    }

    /// Review b7 M1: global cap. With this many row loads already running (home preload, other warm-ups) a resting
    /// tile warms nothing; the page still loads on open.
    public static let prefetchBusyLimit = 6

    public static func mayPrefetch(runningLoads: Int) -> Bool { runningLoads < prefetchBusyLimit }

    /// Local lists (progress, watchlist, calendar) need no warm-up.
    static func isPrefetchable(_ s: CatalogSource) -> Bool {
        switch s.kind {
        case .continueWatching, .watchlist, .upcoming: return false
        default: return true
        }
    }

    static func suffix(_ s: CatalogSource) -> String? {
        switch s.mediaType {
        case .movie: return " · Filme"
        case .series: return " · Serien"
        case .both: return nil
        }
    }

    /// Same request: kind, media type, sort and limit (the title does not change what is fetched).
    struct RequestKey: Hashable {
        let kind: SourceKind, mediaType: MediaType, sortBy: String?, limit: Int?
        init(_ s: CatalogSource) { kind = s.kind; mediaType = s.mediaType; sortBy = s.sortBy; limit = s.limit }
    }
}

/// Build 7 (folder): one source's load on the folder page.
public enum FolderSourceResult: Equatable, Sendable {
    case loading
    /// `count` titles; `ms` until they arrived; `cached` = shown from the cache (memory or disk).
    case loaded(count: Int, ms: Int, cached: Bool)
    case failed(ms: Int)
    /// Addon catalog that no installed addon serves (no request was made).
    case noAddon
}

/// Build 7 (folder): what the page says above its rows. Rows keep their own placeholders and status tiles; the page
/// line makes the loading visible at once and explains a page that really ends up empty.
public enum FolderPagePhase: Equatable, Sendable {
    /// Nothing arrived yet: spinner with "Titel werden geladen …".
    case loading
    /// At least one row has titles (further rows may still load; they show their placeholders).
    case content
    /// Every source finished without titles.
    case empty
    /// Every source failed (or failed / no addon, none with titles).
    case failed
    /// Only addon catalogs no installed addon serves.
    case noAddon
    /// The folder has no readable source at all.
    case noSources

    public static func of(_ results: [FolderSourceResult]) -> FolderPagePhase {
        guard !results.isEmpty else { return .noSources }
        var pending = false, failed = 0, noAddon = 0
        for r in results {
            switch r {
            case .loading: pending = true
            case .loaded(let n, _, _): if n > 0 { return .content }
            case .failed: failed += 1
            case .noAddon: noAddon += 1
            }
        }
        if pending { return .loading }
        if noAddon == results.count { return .noAddon }
        if failed > 0 && failed + noAddon == results.count { return .failed }
        return .empty
    }

    /// German page text (nil while titles show).
    public var text: String? {
        switch self {
        case .loading: return "Titel werden geladen …"
        case .content: return nil
        case .empty: return "Hier gibt es gerade keine Titel. Die Quelle hat eine leere Liste geliefert."
        case .failed: return "Laden fehlgeschlagen. Die Quelle antwortet gerade nicht – später erneut versuchen."
        case .noAddon: return "Kein installiertes Addon liefert diese Kataloge. Das passende Addon (z. B. AIOMetadata) in den Einstellungen hinzufügen."
        case .noSources: return "Dieser Ordner hat keine lesbaren Quellen."
        }
    }

    public var isFinished: Bool { self != .loading }
}

/// Build 7 (folder): one log line per page open, once every source has finished.
/// `katalog: Ordner Shudder: 2 Quellen in 9423 ms · Shudder · Filme 36 (7760 ms) · Shudder · Serien 50 (Cache)`
public enum FolderLoadLog {
    public static func line(folder: String, rows: [(title: String, result: FolderSourceResult)], totalMs: Int,
                            prefetched: Int = 0) -> String {
        let parts = rows.map { r -> String in
            switch r.result {
            case .loading: return "\(r.title) lädt"
            case .loaded(let n, let ms, let cached): return cached ? "\(r.title) \(n) (Cache)" : "\(r.title) \(n) (\(ms) ms)"
            case .failed(let ms): return "\(r.title) Fehler (\(ms) ms)"
            case .noAddon: return "\(r.title) ohne Addon"
            }
        }
        let warm = prefetched > 0 ? " · \(prefetched) beim Fokus vorgeladen" : ""
        let head = "Ordner \(folder): \(rows.count) \(rows.count == 1 ? "Quelle" : "Quellen") in \(totalMs) ms\(warm)"
        return ([head] + parts).joined(separator: " · ")
    }
}

/// Build 7 review (M2, M3, L5): what the folder page knows about its sources. Lives in a holder owned by the page
/// (not in the lazily built header, which scrolling dropped). Results come from the page's own loads and from every
/// later load of the same source (row retry, lazy row rebuilt, background refresh).
public struct FolderLoadState: Equatable, Sendable {
    public private(set) var results: [String: FolderSourceResult] = [:]
    public init() {}

    /// A newer result replaces the old one, except that a failure does not hide titles already shown.
    public mutating func record(_ id: String, _ r: FolderSourceResult) {
        if case .failed = r, case .loaded(let n, _, _)? = results[id], n > 0 { return }
        results[id] = r
    }

    /// Result of a row: recorded, else the cache (count of a stored list, read synchronously, so a cached folder
    /// shows no spinner on its first frame), else loading.
    public func result(_ id: String, cachedCount: (String) -> Int?) -> FolderSourceResult {
        switch results[id] {
        case nil, .loading?:
            if let n = cachedCount(id) { return .loaded(count: n, ms: 0, cached: true) }
            return .loading
        case let r?:
            // A row retry or refresh filled the cache after a failed or empty result: titles win.
            if let n = cachedCount(id), n > 0, !r.hasTitles { return .loaded(count: n, ms: 0, cached: true) }
            return r
        }
    }

    public func phase(_ rows: [CatalogSource], cachedCount: (String) -> Int?) -> FolderPagePhase {
        FolderPagePhase.of(rows.map { result($0.id, cachedCount: cachedCount) })
    }
}

extension FolderSourceResult {
    var hasTitles: Bool {
        if case .loaded(let n, _, _) = self { return n > 0 }
        return false
    }
}

/// Build 7 review (L4): sources whose last load failed, remembered for `ttl` seconds. A lazily rebuilt row or a
/// renewed focus rest then does not ask a failing catalog again at once; a row's own retry forgets the entry first.
public struct RecentLoadFailures: Sendable {
    public static let ttl: TimeInterval = 30
    private var at: [String: Date] = [:]
    public init() {}

    public mutating func mark(_ id: String, now: Date = Date()) { at[id] = now }
    public mutating func forget(_ id: String) { at[id] = nil }
    public mutating func removeAll() { at.removeAll() }

    public func isRecent(_ id: String, now: Date = Date()) -> Bool {
        guard let t = at[id] else { return false }
        return now.timeIntervalSince(t) < Self.ttl
    }
}
