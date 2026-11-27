import SwiftUI
import PlayerCore

/// Wave G2: genre page (a genre tile of the home screen). Filter Filme / Serien (always opens on Filme) and an endless
/// poster grid: one block at a time (TMDB page or addon `skip` page), the next block about two rows before the end,
/// duplicates dropped, a failed block ends the grid with a small "Erneut versuchen" row. Paging logic: PlayerCore
/// `GenrePaging`; tiles, poster size and badges as in the home rows (`PosterCard`); focus room as wave F-m
/// (`Theme.Focus`, `FocusHeadroom`).
/// Wave G2 R1: genre folders open the genre page, every other folder the row page (PlayerCore `GenrePageRule`).
/// Build 8: tiles of a studio / streaming row open the same grid (PlayerCore `BrandPage`: TMDB service, company or
/// network by the tile title, else a cached company search, else the tile's addon catalogs); the rest the row page.
struct FolderRouteView: View {
    @EnvironmentObject var model: AppModel
    let folder: Folder
    /// Build 8: when the page was opened (first page time in the log, search included).
    @State private var openedAt = Date()
    /// Build 8: the page after a company search (nil while none ran).
    @State private var searched: BrandPage.Resolution?

    var body: some View {
        if let g = GenrePageRule.sources(for: folder, collection: { model.collection($0) }) {
            GenrePageView(folder: folder, sources: g)
        } else {
            // Build 8 review: without a TMDB key only the addon grid or the row page (`tmdb: false`).
            brandPage(searched ?? BrandPage.resolve(folder, collection: { model.collection($0) },
                                                    searched: { CompanySearchStore.shared.lookup($0) },
                                                    tmdb: model.tmdb != nil))
        }
    }

    @ViewBuilder private func brandPage(_ r: BrandPage.Resolution) -> some View {
        switch r {
        case .grid(let g):
            GenrePageView(folder: folder, sources: g.sources, brand: g, openedAt: openedAt)
        case .search(let query, let key):
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task(id: key) { await runSearch(query: query, key: key) }
        case .rowPage:
            FolderView(folder: folder)
        }
    }

    /// Search once (cached on disk); a failed search (or no TMDB key) opens the addon grid or the row page.
    private func runSearch(query: String, key: String) async {
        let answer = await CompanySearchStore.shared.search(query, key: key, tmdb: model.tmdb)
        let lookup: (String) -> MediaCollection? = { model.collection($0) }
        if let answer {
            searched = BrandPage.afterSearch(folder, collection: lookup, answer: answer)
        } else {
            searched = BrandPage.withoutSearch(folder, collection: lookup)
        }
    }
}

struct GenrePageView: View {
    @EnvironmentObject var model: AppModel
    let folder: Folder
    let sources: GenrePageSources
    /// New on every open of the page (pushed view), so the page always starts on Filme.
    @State private var filter: GenreFilter
    @State private var paging: [GenreFilter: GenrePaging] = [:]
    @FocusState private var focusedID: String?
    @FocusState private var focusedFilter: GenreFilter?
    /// Review I-2: the footer retry button keeps the focus while its block loads (spinner inside).
    @FocusState private var retryFocused: Bool
    /// F-B-8: retry marker per filter, so a block of the other filter neither keeps nor clears it.
    @State private var retrying: Set<GenreFilter> = []
    /// Review M-1: page on screen; a block that lands after leaving it does not chain the next one.
    @State private var onScreen = false
    /// Build 7: studio logo address that could not be loaded (header shows the name).
    @State private var headerLogoFailed: String?
    /// Build 8: studio / streaming tile of the home screen (nil for genre pages and detail studio plates).
    let brand: BrandPage.Grid?
    let openedAt: Date
    /// Build 8: TMDB logo of a table studio / network (looked up once, cached on disk), tile picture that failed.
    @State private var brandLogo: String?
    @State private var headerTileFailed: String?
    /// Build 8: region US lists that replaced an empty region DE list (by the DE source ID).
    @State private var regionSwap: [String: CatalogSource] = [:]
    /// Build 8: filters whose first page time is logged already.
    @State private var firstLogged: Set<GenreFilter> = []

    init(folder: Folder, sources: GenrePageSources, brand: BrandPage.Grid? = nil, openedAt: Date = Date()) {
        self.folder = folder; self.sources = sources; self.brand = brand; self.openedAt = openedAt
        // Build 7 review: the studio page opens on Serien when it came from a series (or is a network).
        // Build 8: a studio / streaming tile opens on the filter `BrandPage` picked.
        let brandStart = brand.flatMap { sources.available.contains($0.initial) ? $0.initial : nil }
        let start = brandStart ?? StudioPage.initialFilter(folder, available: sources.available)
            ?? GenreFilter.initial(available: sources.available)
        _filter = State(initialValue: start)
    }

    var body: some View {
        let a = model.profile.appearance
        let s = a.cardSize.scale
        let tile = PosterSize.tileSize(.poster, scale: s)
        let spacing = PosterSize.spacing(scale: s)
        let band = a.titles.posterBadges == .bottom ? PosterQualityBadges.bandHeight : 0
        let cardHeight = FocusHeadroom.tallest([.poster], cardScale: s, posterExtra: band)
        // Vertical gap between grid rows: lift + shadow of a focused card (as `Strip`), so it never runs into the row
        // below; at the list edges the same room (wave F-m: list inset, draws into the room, no clipping).
        let rowGap = Theme.Focus.cardRowPadding(height: cardHeight, minimum: Theme.Space.l * s)
        let room = Theme.Focus.listBottomRoom(height: cardHeight)
        let bottom = max(room, Self.bottomSafeArea)
        let cols = GenreGrid.columns(width: Self.contentWidth, tileWidth: tile.width, spacing: spacing)
        let state = paging[filter] ?? GenrePaging(style: .tmdb)

        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                header
                filterBar
                grid(state, columns: cols, tileWidth: tile.width, spacing: spacing, rowGap: rowGap)
                    .zIndex(1)   // review M-6: a lifted card of the last row draws above the footer
                footer(state)
            }
            .padding(.horizontal, Theme.Space.edge)
            .padding(.top, max(0, 40 - room))
            .padding(.bottom, 40)
        }
        .scrollClipDisabled()
        .mask(alignment: .top) { Color.black.padding(.top, -room).padding(.bottom, -bottom) }
        .padding(.top, room)
        .padding(.bottom, bottom)
        .ignoresSafeArea(edges: .bottom)
        .environment(\.cardScale, s)
        .environment(\.prefetchRow, PrefetchRow(key: "genre|\(folder.id)|\(filter.rawValue)", title: "\(logLabel) \(folder.title) \(filter.title)"))
        .task(id: filter) {
            if paging[filter] == nil { startFirst(filter) }
        }
        .onChange(of: focusedID) { _, id in
            guard let id, let i = paging[filter]?.items.firstIndex(where: { $0.id == id }) else { return }
            lastIndex = i
            prefetchIfNeeded(columns: cols)
        }
        .onAppear {
            onScreen = true
            if let brand {
                RemoteLog.info("genre", BrandPage.openLine(brand, title: folder.title, filter: filter))
            } else {
                RemoteLog.info("genre", "\(logLabel): \(folder.title) geöffnet, Filter \(filter.title) (\(sources.available.map(\.title).joined(separator: "/")))")
            }
        }
        .onDisappear { onScreen = false }
    }

    /// Last focused grid position (for the prefetch check when a block lands).
    @State private var lastIndex = 0
    @State private var columnsNow = 6

    private static let contentWidth: CGFloat = 1920 - 2 * Theme.Space.edge
    /// tvOS bottom safe area (as the home list, wave F-m).
    private static let bottomSafeArea: CGFloat = 60

    // MARK: Header

    /// Build 7: „Genre“ / „Studio“ in the log lines (`StudioPage`). Build 8: „Dienst“ / „Studio“ (`BrandPage`).
    private var logLabel: String { brand?.label ?? StudioPage.logLabel(folder) }

    /// Build 8: the logo of the header: studio plate, folder logo, else the TMDB logo once looked up.
    private var headerLogo: String? { StudioPage.headerLogo(folder) ?? brand?.header.logo ?? brandLogo }

    /// The title; the studio page shows the studio logo (white shape, as the detail plates), the name if it fails.
    /// Build 8: a studio / streaming tile without a logo shows its tile picture beside the name.
    @ViewBuilder private var header: some View {
        Group {
            if let logo = headerLogo, headerLogoFailed != logo {
                logoHeader(logo)
            } else if let tile = brand?.header.tile, headerTileFailed != tile {
                HStack(spacing: Theme.Space.m) {
                    RemoteImage(url: tile, maxPixels: 640, onFailure: { headerTileFailed = $0 })
                        .frame(width: Self.tileHeaderWidth, height: Self.tileHeaderHeight)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                        .accessibilityHidden(true)
                    Text(folder.title).textRole(.display).accessibilityAddTraits(.isHeader)
                }
            } else {
                Text(folder.title).textRole(.display).accessibilityAddTraits(.isHeader)
            }
        }
        .task(id: brand?.header.tmdbLogo) {
            guard let studio = brand?.header.tmdbLogo, brandLogo == nil else { return }
            brandLogo = await CompanySearchStore.shared.logo(studio, tmdb: model.tmdb)
        }
    }

    private static let tileHeaderWidth: CGFloat = 213
    private static let tileHeaderHeight: CGFloat = 120

    private func logoHeader(_ logo: String) -> some View {
        RemoteImage(url: logo, maxPixels: 900, fit: true, placeholder: AnyView(Color.clear),
                    onFailure: { headerLogoFailed = $0 })
            .saturation(0)
            .brightness(1)
            .frame(maxWidth: 520, maxHeight: 120, alignment: .leading)
            .accessibilityLabel(folder.title)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Filter

    private var filterBar: some View {
        HStack(spacing: Theme.Space.m) {
            ForEach(sources.available, id: \.self) { f in
                Button {
                    guard f != filter else { return }
                    RemoteLog.info("genre", "\(logLabel): \(folder.title) Filter \(f.title)")
                    lastIndex = 0
                    filter = f
                } label: {
                    HStack(spacing: Theme.Space.xs) {
                        if f == filter { Image(systemName: "checkmark") }
                        Text(f.title)
                    }
                }
                .buttonStyle(ThemeActionButtonStyle(selected: f == filter))
                .focused($focusedFilter, equals: f)
                .accessibilityAddTraits(f == filter ? .isSelected : [])
            }
        }
        // Focus lift + shadow of the action buttons (as the season picker).
        .padding(.vertical, Theme.Space.s)
        .focusSection()
    }

    // MARK: Grid

    @ViewBuilder
    private func grid(_ state: GenrePaging, columns: Int, tileWidth: CGFloat, spacing: CGFloat, rowGap: CGFloat) -> some View {
        switch state.phase {
        case .loadingFirst:
            ProgressView().padding(.vertical, Theme.Space.xl)
        case .empty:
            Text(model.tmdb == nil && isTMDB(filter) ? "TMDB-Key fehlt (Einstellungen)" : "Keine Titel gefunden.")
                .textRole(.rowDetail)
        case .failedFirst:
            retryButton(text: "Laden fehlgeschlagen – erneut versuchen", loading: false)
        case .items:
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(tileWidth), spacing: spacing), count: columns),
                      alignment: .leading, spacing: rowGap) {
                ForEach(state.items) { m in
                    NavigationLinkish(route: .detail(m), onActivate: { $0 }, label: PosterCard(item: m).equatable())
                        .tileMenu(m)   // Wave L (added at the L merge, see wave G2 note)
                        .focused($focusedID, equals: m.id)
                        // The lifted card draws above its neighbours (spacing is the home rows' spacing).
                        .zIndex(focusedID == m.id ? 1 : 0)
                }
            }
            .padding(.top, rowGap)
            .focusSection()
            .onAppear { columnsNow = columns }
            .onChange(of: columns) { _, c in columnsNow = c }
            // Build 8: grid posters decode at most at scale 1.5 (4K TV: one size step lower, image budget).
            .environment(\.imageDecodeScaleCap, GridImageScale.cap)
        }
    }

    @ViewBuilder
    private func footer(_ state: GenrePaging) -> some View {
        // Review I-2: after "Erneut versuchen" the button stays (spinner inside, one branch = same view identity, so
        // it keeps the focus also when the block fails again) and the focus does not fall back to the top of the page;
        // when the block lands the focus moves to its first new title.
        if state.footer == .retry || (state.footer == .loading && retrying.contains(filter)) {
            retryButton(text: "Erneut versuchen", loading: state.footer == .loading)
        } else if state.footer == .loading {
            ProgressView().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func retryButton(text: String, loading: Bool) -> some View {
        Button {
            guard !loading else { return }
            RemoteLog.info("genre", "\(logLabel): \(folder.title) \(filter.title) erneut versuchen")
            retry(filter)
        } label: {
            HStack(spacing: Theme.Space.xs) {
                if loading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                Text(text)
            }
        }
        .buttonStyle(ThemeActionButtonStyle())
        .focused($retryFocused)
        .padding(.vertical, Theme.Space.s)
    }

    private func isTMDB(_ f: GenreFilter) -> Bool {
        guard let s = sources.source(for: f) else { return false }
        if case .addon = s.kind { return false }
        return true
    }

    // MARK: Loading

    private func startFirst(_ f: GenreFilter) {
        guard let src = sources.source(for: f) else { return }
        var p = GenrePaging(source: src)
        // Review M-2: the home row's cached first block shows at once (same request: TMDB page 1 / addon skip 0).
        if src.limit == nil, let cached = model.cache[src.id], !cached.isEmpty, let first = p.beginNext() {
            let added = p.receive(first, items: cached)
            RemoteLog.info("genre", p.logLine(genre: folder.title, filter: f, added: added, label: logLabel) + " (Cache)")
            // Build 8 review: the first page time also when it came from the cache (warm-up or home row).
            if !firstLogged.contains(f) {
                let sinceOpen: Int? = firstLogged.isEmpty ? Int(Date().timeIntervalSince(openedAt) * 1000) : nil
                firstLogged.insert(f)
                RemoteLog.info("genre", BrandPage.firstPageLine(label: logLabel, title: folder.title, filter: f, count: cached.count,
                                                                fetchMs: 0, sinceOpenMs: sinceOpen) + " (Cache)")
            }
        }
        let r = p.beginNext()
        paging[f] = p
        if let r { load(f, r) }
    }

    private func prefetchIfNeeded(columns: Int) {
        let f = filter
        // Build 8: four rows ahead (more than a TMDB page), so holding the remote down does not reach the end first.
        guard var p = paging[f], p.shouldPrefetch(focusedIndex: lastIndex, columns: columns, rows: BrandPage.prefetchRows),
              let r = p.beginNext() else { return }
        paging[f] = p
        load(f, r)
    }

    private func retry(_ f: GenreFilter) {
        guard var p = paging[f], let r = p.retry() else { return }
        if p.items.isEmpty { retrying.remove(f) } else { retrying.insert(f) }
        paging[f] = p
        load(f, r)
    }

    private func load(_ f: GenreFilter, _ r: GenrePageRequest) {
        guard let src = sources.source(for: f) else { return }
        let name = folder.title, label = logLabel
        Task { @MainActor in
            do {
                let (items, total) = try await fetch(src, r)
                guard var p = paging[f] else { return }
                let before = p.items.count
                let added = p.receive(r, items: items, totalPages: total)
                paging[f] = p
                RemoteLog.info("genre", p.logLine(genre: name, filter: f, added: added, label: label))
                if retrying.remove(f) != nil, f == filter {
                    // Review I-2: the retry button goes away; its focus moves to the first new (else the last) title.
                    if retryFocused, let target = (p.items.count > before ? p.items[before] : p.items.last)?.id { focusedID = target }
                }
                // A short or duplicate-only block does not move the focus: check again at once (only on screen).
                if f == filter, onScreen { prefetchIfNeeded(columns: columnsNow) }
            } catch {
                guard var p = paging[f] else { return }
                let line = p.failLine(genre: name, filter: f, request: r, error: "\(error)", label: label)
                p.fail(r)
                paging[f] = p
                retrying.remove(f)
                RemoteLog.error("genre", line)
            }
        }
    }

    /// Build 8: one block, timed. The first block of each filter is logged (the first one also with the time since
    /// the tile was selected); an empty first page of a service in region DE moves that list to region US.
    private func fetch(_ src: CatalogSource, _ r: GenrePageRequest) async throws -> ([MetaPreview], Int?) {
        let first = r == .tmdbPage(1) || r == .addonSkip(0)
        let f = sources.filter(ofSourceID: src.id)
        let started = Date()
        var answer = try await fetchBlock(regionSwap[src.id] ?? src, r)
        if first, answer.0.isEmpty, regionSwap[src.id] == nil, let us = brand?.regionFallback[src.id] {
            if let f { RemoteLog.info("genre", BrandPage.regionLine(label: logLabel, title: folder.title, filter: f)) }
            regionSwap[src.id] = us
            answer = try await fetchBlock(us, r)
        }
        if first, let f, !firstLogged.contains(f) {
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            let sinceOpen: Int? = firstLogged.isEmpty ? Int(Date().timeIntervalSince(openedAt) * 1000) : nil
            firstLogged.insert(f)
            RemoteLog.info("genre", BrandPage.firstPageLine(label: logLabel, title: folder.title, filter: f,
                                                            count: answer.0.count, fetchMs: ms, sinceOpenMs: sinceOpen))
        }
        return answer
    }

    private func fetchBlock(_ src: CatalogSource, _ r: GenrePageRequest) async throws -> ([MetaPreview], Int?) {
        switch (src.kind, r) {
        case (.addon(let addonId, let catalogId, let type), .addonSkip(let skip)):
            guard let hit = AddonCatalogResolver.resolve(model.profile.addons, addonId: addonId, catalogId: catalogId, type: type) else {
                return ([], nil)
            }
            let items = try await model.addons.catalog(hit.addon, type: hit.type, id: catalogId,
                                                       extra: skip > 0 ? ["skip": String(skip)] : [:])
            return (items, nil)
        case (_, .tmdbPage(let page)):
            guard let tmdb = model.tmdb else { return ([], nil) }
            let answer = try await tmdb.page(for: src, page: page)
            return (answer.items, answer.totalPages)
        default:
            return ([], nil)
        }
    }
}
