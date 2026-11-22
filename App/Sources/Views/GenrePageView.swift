import SwiftUI
import PlayerCore

/// Wave G2: genre page (a genre tile of the home screen). Filter Filme / Serien (always opens on Filme) and an endless
/// poster grid: one block at a time (TMDB page or addon `skip` page), the next block about two rows before the end,
/// duplicates dropped, a failed block ends the grid with a small "Erneut versuchen" row. Paging logic: PlayerCore
/// `GenrePaging`; tiles, poster size and badges as in the home rows (`PosterCard`); focus room as wave F-m
/// (`Theme.Focus`, `FocusHeadroom`).
struct GenrePageView: View {
    @EnvironmentObject var model: AppModel
    let folder: Folder
    let sources: GenrePageSources
    /// New on every open of the page (pushed view), so the page always starts on Filme.
    @State private var filter: GenreFilter
    @State private var paging: [GenreFilter: GenrePaging] = [:]
    @FocusState private var focusedID: String?
    @FocusState private var focusedFilter: GenreFilter?

    init(folder: Folder, sources: GenrePageSources) {
        self.folder = folder; self.sources = sources
        _filter = State(initialValue: GenreFilter.initial(available: sources.available))
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
                Text(folder.title).textRole(.display).accessibilityAddTraits(.isHeader)
                filterBar
                grid(state, columns: cols, tileWidth: tile.width, spacing: spacing, rowGap: rowGap)
                footer(state, cardHeight: cardHeight)
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
        .environment(\.prefetchRow, PrefetchRow(key: "genre|\(folder.id)|\(filter.rawValue)", title: "Genre \(folder.title) \(filter.title)"))
        .task(id: filter) {
            if paging[filter] == nil { startFirst(filter) }
        }
        .onChange(of: focusedID) { _, id in
            guard let id, let i = paging[filter]?.items.firstIndex(where: { $0.id == id }) else { return }
            lastIndex = i
            prefetchIfNeeded(columns: cols)
        }
        .onAppear { RemoteLog.info("genre", "Genre: \(folder.title) geöffnet, Filter \(filter.title) (\(sources.available.map(\.title).joined(separator: "/")))") }
    }

    /// Last focused grid position (for the prefetch check when a block lands).
    @State private var lastIndex = 0
    @State private var columnsNow = 6

    private static let contentWidth: CGFloat = 1920 - 2 * Theme.Space.edge
    /// tvOS bottom safe area (as the home list, wave F-m).
    private static let bottomSafeArea: CGFloat = 60

    // MARK: Filter

    private var filterBar: some View {
        HStack(spacing: Theme.Space.m) {
            ForEach(sources.available, id: \.self) { f in
                Button {
                    guard f != filter else { return }
                    RemoteLog.info("genre", "Genre: \(folder.title) Filter \(f.title)")
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
            retryButton(text: "Laden fehlgeschlagen – erneut versuchen")
        case .items:
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(tileWidth), spacing: spacing), count: columns),
                      alignment: .leading, spacing: rowGap) {
                ForEach(state.items) { m in
                    NavigationLinkish(route: .detail(m), onActivate: { $0 }, label: PosterCard(item: m).equatable())
                        .focused($focusedID, equals: m.id)
                        // The lifted card draws above its neighbours (spacing is the home rows' spacing).
                        .zIndex(focusedID == m.id ? 1 : 0)
                }
            }
            .padding(.top, rowGap)
            .focusSection()
            .onAppear { columnsNow = columns }
            .onChange(of: columns) { _, c in columnsNow = c }
        }
    }

    @ViewBuilder
    private func footer(_ state: GenrePaging, cardHeight: CGFloat) -> some View {
        switch state.footer {
        case .none: EmptyView()
        case .loading: ProgressView().frame(maxWidth: .infinity, alignment: .leading)
        case .retry: retryButton(text: "Erneut versuchen")
        }
    }

    private func retryButton(text: String) -> some View {
        Button {
            RemoteLog.info("genre", "Genre: \(folder.title) \(filter.title) erneut versuchen")
            retry(filter)
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "arrow.clockwise")
                Text(text)
            }
        }
        .buttonStyle(ThemeActionButtonStyle())
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
        let r = p.beginNext()
        paging[f] = p
        if let r { load(f, r) }
    }

    private func prefetchIfNeeded(columns: Int) {
        let f = filter
        guard var p = paging[f], p.shouldPrefetch(focusedIndex: lastIndex, columns: columns),
              let r = p.beginNext() else { return }
        paging[f] = p
        load(f, r)
    }

    private func retry(_ f: GenreFilter) {
        guard var p = paging[f], let r = p.retry() else { return }
        paging[f] = p
        load(f, r)
    }

    private func load(_ f: GenreFilter, _ r: GenrePageRequest) {
        guard let src = sources.source(for: f) else { return }
        let name = folder.title
        Task { @MainActor in
            do {
                let (items, total) = try await fetch(src, r)
                guard var p = paging[f] else { return }
                let added = p.receive(r, items: items, totalPages: total)
                paging[f] = p
                RemoteLog.info("genre", p.logLine(genre: name, filter: f, added: added))
                // A short or duplicate-only block does not move the focus: check again at once.
                if f == filter { prefetchIfNeeded(columns: columnsNow) }
            } catch {
                guard var p = paging[f] else { return }
                let line = p.failLine(genre: name, filter: f, request: r, error: "\(error)")
                p.fail(r)
                paging[f] = p
                RemoteLog.error("genre", line)
            }
        }
    }

    private func fetch(_ src: CatalogSource, _ r: GenrePageRequest) async throws -> ([MetaPreview], Int?) {
        switch (src.kind, r) {
        case (.addon(let addonId, let catalogId, let type), .addonSkip(let skip)):
            guard let a = model.profile.addons.first(where: { $0.manifest.id == addonId }) else { return ([], nil) }
            let items = try await model.addons.catalog(a, type: type, id: catalogId, extra: skip > 0 ? ["skip": String(skip)] : [:])
            return (items, nil)
        case (_, .tmdbPage(let page)):
            guard let tmdb = model.tmdb else { return ([], nil) }
            let r = try await tmdb.page(for: src, page: page)
            return (r.items, r.totalPages)
        default:
            return ([], nil)
        }
    }
}
