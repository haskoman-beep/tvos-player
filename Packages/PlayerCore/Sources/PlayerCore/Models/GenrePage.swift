import Foundation

/// Wave G2: the genre page (a folder tile of a genre row opened from the home screen). A filter Filme / Serien and
/// an endless poster grid that loads one block at a time (a TMDB page or an addon `skip` page). Pure logic; the app
/// view (`GenrePageView`) only fetches the requested block and hands the answer back.

/// Filter of the genre page. Filme is always the default and the page starts on it every time it opens.
public enum GenreFilter: String, Sendable, CaseIterable, Hashable {
    case movies, series

    public var title: String { self == .movies ? "Filme" : "Serien" }

    /// Filter the page opens with: Filme whenever the folder has films, otherwise the first available one.
    public static func initial(available: [GenreFilter]) -> GenreFilter {
        available.contains(.movies) ? .movies : (available.first ?? .movies)
    }
}

/// One block of a source: TMDB counts pages from 1, an addon catalog an item offset (`skip`).
public enum GenrePageRequest: Equatable, Sendable {
    case tmdbPage(Int)
    case addonSkip(Int)
}

/// The sources behind the filter: at most one film and one series list, each loadable block by block.
public struct GenrePageSources: Equatable, Sendable {
    public var movies: CatalogSource?
    public var series: CatalogSource?

    public init(movies: CatalogSource?, series: CatalogSource?) { self.movies = movies; self.series = series }

    /// Folders that become a genre page: one film and/or one series list, every one of them pageable (TMDB discover,
    /// list, company or an addon catalog). Everything else (e.g. streaming folders with four lists, Trakt lists,
    /// mixed lists) keeps the old page with one row per source (nil).
    public static func of(_ folder: Folder) -> GenrePageSources? {
        var movies: CatalogSource?, series: CatalogSource?
        for s in folder.sources {
            guard isPageable(s) else { return nil }
            switch filter(of: s) {
            case .movies?: if movies != nil { return nil }; movies = s
            case .series?: if series != nil { return nil }; series = s
            case nil: return nil
            }
        }
        guard movies != nil || series != nil else { return nil }
        return GenrePageSources(movies: movies, series: series)
    }

    public var available: [GenreFilter] {
        GenreFilter.allCases.filter { source(for: $0) != nil }
    }

    public func source(for filter: GenreFilter) -> CatalogSource? { filter == .movies ? movies : series }

    static func isPageable(_ s: CatalogSource) -> Bool {
        switch s.kind {
        case .tmdbDiscover, .tmdbList, .tmdbCompany, .addon: true
        default: false
        }
    }

    /// Film or series; an addon catalog says it by its type, a `.both` list fits neither.
    static func filter(of s: CatalogSource) -> GenreFilter? {
        if case .addon(_, _, let type) = s.kind {
            switch type { case "movie": return .movies; case "series": return .series; default: return nil }
        }
        switch s.mediaType { case .movie: return .movies; case .series: return .series; case .both: return nil }
    }
}

/// Paging state of one grid (one filter). Collects blocks, drops titles already shown, knows the end of the source,
/// a failed block (retry row at the end, the shown titles stay) and when the focus is close enough to the end to
/// load the next block.
public struct GenrePaging: Equatable, Sendable {
    public enum Style: Equatable, Sendable { case tmdb, addon }

    public let style: Style
    public private(set) var items: [MetaPreview] = []
    /// Blocks received so far (TMDB: the last page number loaded).
    public private(set) var pagesLoaded = 0
    /// Raw entries received from an addon (next `skip`), duplicates included: the addon counts its own offset.
    public private(set) var rawCount = 0
    /// Block in flight (nil = idle).
    public private(set) var inFlight: GenrePageRequest?
    public private(set) var failed = false
    public private(set) var reachedEnd = false
    private var seen = Set<String>()

    /// TMDB serves at most page 500 of a discover query.
    public static let tmdbMaxPage = 500
    /// Rows before the end at which the next block is requested.
    public static let prefetchRows = 2

    public init(style: Style) { self.style = style }

    public init(source: CatalogSource) {
        if case .addon = source.kind { self.init(style: .addon) } else { self.init(style: .tmdb) }
    }

    /// The next block to load, marked as in flight; nil while one is in flight, after the end or after a failure
    /// (that needs `retry`).
    public mutating func beginNext() -> GenrePageRequest? {
        guard inFlight == nil, !failed, !reachedEnd else { return nil }
        let r: GenrePageRequest = style == .tmdb ? .tmdbPage(pagesLoaded + 1) : .addonSkip(rawCount)
        inFlight = r
        return r
    }

    /// Answer to `request`. `totalPages`: TMDB's `total_pages` (nil = unknown). Returns how many new titles were
    /// added. An empty block ends the source; for an addon also a block with no new title (an addon that ignores
    /// `skip` repeats its first page). A TMDB page of only duplicates does not end it (the order shifted between
    /// two requests); its last page is `totalPages`.
    /// An answer to an older request (e.g. after a filter switch) is ignored and returns 0.
    @discardableResult
    public mutating func receive(_ request: GenrePageRequest, items new: [MetaPreview], totalPages: Int? = nil) -> Int {
        guard request == inFlight else { return 0 }
        inFlight = nil
        failed = false
        pagesLoaded += 1
        rawCount += new.count
        var added = 0
        for m in new where seen.insert(m.id).inserted {
            items.append(m); added += 1
        }
        if new.isEmpty || (style == .addon && added == 0) { reachedEnd = true }
        if case .tmdbPage(let p) = request {
            if let totalPages, p >= totalPages { reachedEnd = true }
            if p >= Self.tmdbMaxPage { reachedEnd = true }
        }
        return added
    }

    /// The block failed: titles shown so far stay, the grid ends with a retry row.
    public mutating func fail(_ request: GenrePageRequest) {
        guard request == inFlight else { return }
        inFlight = nil
        failed = true
    }

    /// "Erneut versuchen": the failed block again.
    public mutating func retry() -> GenrePageRequest? {
        guard failed else { return nil }
        failed = false
        return beginNext()
    }

    /// Should the focus on `index` (0-based, grid with `columns` per row) request the next block? True from about
    /// `prefetchRows` rows before the end, while more can come and nothing is in flight.
    public func shouldPrefetch(focusedIndex index: Int, columns: Int) -> Bool {
        guard inFlight == nil, !failed, !reachedEnd, !items.isEmpty else { return false }
        let cols = max(1, columns)
        let lastRow = (items.count - 1) / cols
        let row = max(0, index) / cols
        return lastRow - row <= Self.prefetchRows
    }

    /// What the grid shows.
    public var phase: Phase {
        if items.isEmpty {
            if failed { return .failedFirst }
            if reachedEnd { return .empty }
            return .loadingFirst
        }
        return .items
    }

    public enum Phase: Equatable, Sendable { case loadingFirst, empty, failedFirst, items }

    /// Footer below the grid: a small spinner while a later block loads, the retry row after a failure.
    public var footer: Footer {
        guard !items.isEmpty else { return .none }
        if failed { return .retry }
        if inFlight != nil { return .loading }
        return .none
    }

    public enum Footer: Equatable, Sendable { case none, loading, retry }

    /// Log line: „Genre: Action Filme Seite 3, +20 Titel (gesamt 60)“ (Seite = block number, also for addons).
    public func logLine(genre: String, filter: GenreFilter, added: Int) -> String {
        var s = "Genre: \(genre) \(filter.title) Seite \(pagesLoaded), +\(added) Titel (gesamt \(items.count))"
        if reachedEnd { s += ", Ende" }
        return s
    }

    /// Log line of a failed block.
    public func failLine(genre: String, filter: GenreFilter, request: GenrePageRequest, error: String) -> String {
        "Genre: \(genre) \(filter.title) Seite \(Self.blockNumber(request, loaded: pagesLoaded)) fehlgeschlagen: \(error)"
    }

    static func blockNumber(_ r: GenrePageRequest, loaded: Int) -> Int {
        if case .tmdbPage(let p) = r { return p }
        return loaded + 1
    }
}

/// Grid geometry of the genre page: as many poster columns as fit the width between the edges, at the profile's
/// poster size.
public enum GenreGrid {
    /// Columns for `tileWidth` and `spacing` in `width` (at least 1).
    public static func columns(width: CGFloat, tileWidth: CGFloat, spacing: CGFloat) -> Int {
        guard tileWidth > 0 else { return 1 }
        return max(1, Int(((width + spacing) / (tileWidth + spacing)).rounded(.down)))
    }
}
