import SwiftUI
import Combine
import PlayerCore

/// Eine Startseiten-Reihe im gewählten Stil.
/// `onActivate` bekommt das Ziel und gibt zurück, ob navigiert werden soll (nil = Klick verschlucken).
struct HomeRowView: View {
    @EnvironmentObject var model: AppModel
    let row: HomeRow
    let onActivate: (Route) -> Route?
    /// Task 4.1a (F-A-3): home page focus target after a context-menu action (nil elsewhere).
    var focusTarget: HomeFocusTarget? = nil
    /// Welle F-b2: Kontextmenü der Startseite (langer Druck auf eine Kachel), nil = keins.
    var menu: HomeRowMenu? = nil
    /// Wave F-j: focus enters (true) or leaves (false) this row (home page: top edge watch, heading scroll).
    var onFocusInside: ((Bool) -> Void)? = nil
    /// Build 4 follow-up S4 (F-A-5): the loaded items and their cards (`ForEach` id `rowKey`, rank), built once when
    /// the items arrive instead of on every body pass. One value (S4 review), so ids and items cannot drift apart.
    @State private var list = RowList()
    private var items: [MetaPreview] { list.items }
    private var entries: [RowEntry] { list.entries }
    @State private var loaded = false
    /// Welle F-f: letzte Ladung schlug fehl (Statuskachel „erneut versuchen“).
    @State private var failed = false
    /// Erhöht durch „erneut versuchen“: startet die Ladung neu.
    @State private var retry = 0
    /// Welle F-f: fokussierter Platzhalter bzw. Statuskachel (0); nach dem Laden geht der Fokus an dieselbe Stelle.
    @FocusState private var focusedPlaceholder: Int?
    /// S5 (Build 4 follow-up): card the focus is handed to after the load; once it holds the focus, the home page's
    /// heading snap restarts (the row-level focus flag stays true through the hand-over, so nothing else reruns it).
    @State private var handoverTarget: Route?
    /// Startseite mit Hero: fokussierte Kachel meldet sich (nil außerhalb der Startseite).
    @Environment(HomeFocus.self) private var homeFocus: HomeFocus?
    @FocusState private var focusedRoute: Route?
    /// Welle C-b (#19): Fokus-Gedächtnis je Reihe (nil außerhalb der Startseite).
    @Environment(\.homeRowFocusMemory) private var focusMemory
    /// Welle C-d: nachgezogene Sendezeiten (TVmaze) → Reihe „Heute neu“ lädt aus dem Kalender-Cache neu.
    @ObservedObject private var upcomingRevision = UpcomingRevision.shared
    /// Welle F-g: Kit-Ladefehler und laufende Ladungen (Statuskachel der Kit-Collections).
    @ObservedObject private var kit = FusionKitStore.shared

    /// The row's load key: a change starts a new load. Split out of `body` (CI: "unable to type-check this
    /// expression in reasonable time"); same value as before.
    private var loadKey: String {
        var key: String = row.content.key
        if row.content == .list(.continueWatching) {
            let newest: Double = model.progress.continueWatching().first?.updated.timeIntervalSince1970 ?? 0
            key += "\(model.progress.entries.count)-\(newest)"
        }
        key += model.catalogStamp(row.content)
        if row.content == .list(.upcoming) { key += "|r\(upcomingRevision.value)" }
        key += "|t\(retry)"
        return key
    }

    var body: some View {
        // Build 4 follow-up S4: `metric: home.rowBody` counts these passes (two integer adds, a log line per 5 s).
        let _ = RowBodyMeter.pass(onHome: focusMemory != nil)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if row.style != .hero {
                Text(title).textRole(.sectionTitle).padding(.leading, Theme.Space.edge)
                    .accessibilityAddTraits(.isHeader)
            }
            content
                .focusSection()
                .defaultFocus($focusedRoute, rememberedRoute, priority: .userInitiated)
        }
        .task(id: loadKey) {
            guard case .list(let s) = row.content else { return }
            // Welle F-f: geteilte Ladung (AppModel+HomeRows), läuft beim Wegscrollen weiter.
            let r = await model.homeRowItems(s)
            guard !Task.isCancelled else { return }   // abgebrochen (neue Ladung folgt): kein „Keine Einträge“-Flackern
            let placeholder = focusedPlaceholder
            // Task 4.1a (F-A-5): a catalog may list a title twice; one card per (type, id), the first wins.
            list = RowList(loaded: r.items); failed = r.failed; loaded = true
            // Fokus lag auf einem Platzhalter: an dieselbe Stelle der fertigen Reihe (bzw. auf die Statuskachel).
            // Erst im nächsten Durchlauf: dann gibt es die Karten schon.
            if let placeholder {
                let p = phase
                var found: Route?
                if case .items = p { found = route(for: displayed[p.focusAfterLoad(placeholder: placeholder)]) }
                let target = found, slot = p.focusAfterLoad(placeholder: placeholder)
                // S5: home page only (pairs with the heading check lines); collections log their F-A-2 line below.
                if onFocusInside != nil {
                    RemoteLog.info("nav", HeadingSnap.handoverLine(title: title, placeholder: placeholder,
                                                                  card: target != nil ? slot : nil))
                }
                DispatchQueue.main.async {
                    // Review M2: the user left the row in the meantime: no hand-over (it would pull focus and page back).
                    guard rowHoldsFocus else {
                        if onFocusInside != nil { RemoteLog.info("nav", HeadingSnap.handoverSkippedLine(title: title)) }
                        return
                    }
                    if let target { handOver(to: target) } else { focusedPlaceholder = slot }
                }
            }
        }
        // Review M1: focus left the row: a pending hand-over ends here (no stale restart on a later visit).
        .onChange(of: focusedRoute != nil || focusedPlaceholder != nil) { _, f in
            if !f, handoverTarget != nil { handoverTarget = nil }
            onFocusInside?(f)
        }
        .onAppear { if focusedRoute != nil || focusedPlaceholder != nil { onFocusInside?(true) } }
        // Task 4.1a (F-A-2): collection rows hand over like list rows: a focused placeholder (or status tile) goes to
        // the tile at the same place when the kit file arrives, else to the status tile.
        .onChange(of: collectionLoadPhase) { _, p in
            // Review minor 1: the change into `.loading` (OK on the status tile) is no hand-over.
            guard let p, p != .loading, let placeholder = focusedPlaceholder, case .collection(let id) = row.content
            else { return }
            let slot = p.focusAfterLoad(placeholder: placeholder)
            var target: Route?
            if case .items = p, let folders = model.collection(id)?.folders, folders.indices.contains(slot) {
                target = .folder(folders[slot])
            }
            RemoteLog.info("fokus", "Collection \(title): Platzhalter \(placeholder) → \(target != nil ? "Kachel \(slot)" : "Statuskachel")")
            DispatchQueue.main.async {
                // Review M2: as for list rows, no hand-over once the user left the row.
                guard rowHoldsFocus else {
                    RemoteLog.info("fokus", "Collection \(title): Übergabe entfällt, Fokus nicht mehr in der Reihe")
                    return
                }
                // S5: the heading snap restarts once the tile holds the focus (the F-A-2 line above is the log).
                if let target { handOver(to: target) } else { focusedPlaceholder = slot }
            }
        }
        // Task 4.1a (F-A-3): `initial` also claims a target when the lazy list builds this row after the scroll.
        .onChange(of: focusTarget?.serial, initial: true) { _, _ in claimFocusTarget() }
        .onDisappear {
            onFocusInside?(false)
            if handoverTarget != nil { handoverTarget = nil }   // Review M1
            // Wave F-p R1: page left with focus in this row within the 350 ms rest: no stale request.
            if let r = focusedRoute { StreamPrefetcher.shared.cancelRest(r) }
        }
        .onChange(of: focusedRoute) { old, r in
            if r != nil { RowBodyMeter.focusMoved(onHome: focusMemory != nil) }   // S4: `fokus` field of `metric: home.rowBody`
            if r != nil { StreamPrefetcher.shared.focusMoved() }   // P3: visible-tile prefetch waits for 1 s focus quiet
            // Wave F-p: focus left this row's tile: its rest prefetch (pages without hero) does not start.
            if r == nil, let old { StreamPrefetcher.shared.cancelRest(old) }
            // S5: the hand-over landed: restart the heading snap (home page). Focus on any other tile ends the wait.
            if let r, let h = handoverTarget {
                handoverTarget = nil
                if r == h { onFocusInside?(true) }
            }
            guard let r, focusMemory?.state.covered != true else { return }   // verdeckte Startseite: nichts merken
            focusMemory?.state.record(row: row.id.uuidString, item: r.heroPreview.id)
            MainThreadWatchdog.note("Fokus \(r.heroPreview.id)")
            if focusMemory != nil { FrameMeter.focusMoved() }   // S1: home rows only (the meter checks the page too)
            if let homeFocus {
                homeFocus.set(r.heroPreview) { StreamPrefetcher.shared.request(r, model: model) }
            } else {
                // Wave F-p: folder pages and Library rows have no hero, so nothing fetched the sources of a resting
                // tile there; the detail page then waited 2–4 s for its tech badges (build 214 log).
                StreamPrefetcher.shared.requestAfterRest(r, model: model)
            }
        }
    }

    private var emptyText: String {
        if row.content == .list(.continueWatching) { return "Noch nichts angefangen." }
        if model.tmdb == nil { return "TMDB-Key fehlt (Einstellungen)" }
        if row.content == .list(.upcoming) { return "Heute keine neuen Folgen." }
        return "Keine Einträge"
    }

    private var title: String {
        switch row.content {
        case .list(let s): s.title
        case .collection(let id): model.collection(id)?.title ?? kit.sourceTitle(ofID: id) ?? "Collection"
        }
    }

    /// Welle F-g: Phase der Collection-Reihe (Kit-Datei lädt, schlug fehl, leer, Kacheln).
    private func collectionPhase(_ id: String, _ c: MediaCollection?) -> CollectionRowPhase {
        CollectionRowPhase.of(collectionID: id, folders: c?.folders, kitErrors: kit.errors, kitLoading: kit.loading)
    }


    /// Task 4.1a (F-A-2): phase of a collection row as `HomeRowPhase` (nil for list rows).
    private var collectionLoadPhase: HomeRowPhase? {
        guard case .collection(let id) = row.content else { return nil }
        let c = model.collection(id)
        return HomeRowPhase(collection: collectionPhase(id, c), count: c?.folders.count ?? 0)
    }

    /// Welle F-f: Phase der Listen-Reihe (jede Phase hat ein Fokusziel, PlayerCore `HomeRowPhase`).
    private var phase: HomeRowPhase { HomeRowPhase(loaded: loaded, failed: failed, count: displayed.count) }

    /// Gezeigte Einträge (Top 10: höchstens zehn).
    private var displayed: [MetaPreview] { row.style == .top10 ? Array(items.prefix(10)) : items }
    /// Cards of `displayed` (same prefix rule), ids already computed.
    private var displayedEntries: [RowEntry] { row.style == .top10 ? Array(entries.prefix(10)) : entries }

    @ViewBuilder private var content: some View {
        switch row.content {
        case .collection(let id):
            let c = model.collection(id)
            let p = collectionPhase(id, c)
            switch p {
            case .tiles:
                let folders = c?.folders ?? []
                let line = CollectionArtStats(folders: folders, logoStyle: row.style == .logoTiles).logLine(title: title)
                // Welle F-l: Paket-Reihen melden zusätzlich, wie viele Paket-Kacheln ein Bild bzw. GIF haben.
                let packLine = PackageArtStats(folders: folders)?.logLine(row: title)
                Strip(kind: tileKind) {
                    ForEach(folders) { f in
                        card(.folder(f)) { FolderTile(folder: f, logoStyle: row.style == .logoTiles,
                                                              sound: model.profile.appearance.tileAnimationSound) }
                    }
                }
                .task(id: line + (packLine ?? "")) {
                    CollectionRowLog.note(row: row.id.uuidString, line: line)
                    if let packLine { CollectionRowLog.note(row: row.id.uuidString + ".pakete", line: packLine) }
                }
            case .failed(let key):
                // Welle F-g: Kit-Datei schlug fehl: erreichbare Statuskachel statt ewiger Platzhalter; OK lädt neu.
                Strip(kind: tileKind) {
                    statusTile(p.statusText ?? "", retry: true) {
                        focusedPlaceholder = 0
                        Task { await FusionKitStore.shared.retry(sourceKey: key) }
                    }
                }
                .task(id: "failed|\(key)") { CollectionRowLog.note(row: row.id.uuidString, line: "Collection \(title): Laden fehlgeschlagen") }
            case .empty:
                Strip(kind: tileKind) { statusTile(p.statusText ?? "Keine Einträge", retry: false) }
            case .loading:
                // Fusion-Kit lädt die Collection noch nach: fokussierbare Platzhalter statt leerer Reihe.
                placeholders
            }
        case .list:
            switch phase {
            case .loading:
                placeholders
            case .empty, .failed:
                Strip(kind: tileKind) { statusTile(phase.statusText(empty: emptyText) ?? emptyText, retry: phase == .failed) }
            case .items:
                let routes = routeTable   // Task 3.8: once per row pass, not once per card
                Strip(expands: row.style == .poster, kind: tileKind) {
                    ForEach(displayedEntries) { e in
                        let m = e.item
                        card(routes[m.id] ?? .detail(m)) {
                            if row.content == .list(.upcoming) {
                                UpcomingTodayCard(item: m, landscape: row.style == .landscape || row.style == .hero)
                            } else {
                                switch row.style {
                                case .hero: HeroCard(item: m)
                                case .landscape: LandscapeCard(item: m).equatable()
                                case .top10: Top10Card(item: m, rank: e.rank).equatable()
                                default: PosterCard(item: m).equatable()
                                }
                            }
                        }
                    }
                }
                // Wave F-k R1: row of these tiles for the visible-tile prefetch (order, log line).
                .environment(\.prefetchRow, PrefetchRow(key: "home|\(row.id.uuidString)", title: title))
                // Wave F-k: how many tiles know their quality (source cache only), again when a prefetch lands here.
                .task(id: displayed.map(\.id)) { noteBadges() }
                .onReceive(QualityBadgeCache.shared.stored) { id in
                    // S3: cheap per item (`streamCacheKeyMatches`), same answer as comparing `streamCacheKey(for:)`.
                    guard tileKind == .poster, displayed.contains(where: { model.streamCacheKeyMatches(id, for: $0) }) else { return }
                    noteBadges()
                }
            }
        }
    }

    /// Wave F-k: log line „Plaketten: <row> n/m mit Qualität“ for poster rows (only these carry quality badges);
    /// logged only when the count changes and has rested 2 s (prefetch results arrive one by one).
    private func noteBadges() {
        guard tileKind == .poster, !displayed.isEmpty else { return }
        let m = model, items = displayed, name = title
        CollectionRowLog.noteLater(row: "badges|\(row.id.uuidString)") {
            let a = m.profile.appearance
            let n = items.filter { PosterBadgeStats.hasBadges(QualityBadgeCache.shared.best(for: $0, model: m), settings: a.badges) }.count
            return PosterBadgeStats.logLine(row: name, withQuality: n, total: items.count, placement: a.titles.posterBadges)
        }
    }

    /// Kachelform der Reihe; „Heute neu“ im Hero-Stil zeigt Querformat-Karten (UpcomingTodayCard).
    private var tileKind: TileKind {
        if row.content == .list(.upcoming), row.style == .hero { return .landscape }
        return PosterSize.kind(for: row.style)
    }

    /// Welle F-f: ladende Reihe, fokussierbare Platzhalter in Endgröße (Höhe springt beim Eintreffen nicht).
    /// Das Kontextmenü gilt auch hier (eine hängende Reihe lässt sich ausblenden oder löschen).
    private var placeholders: some View {
        let n = PosterSize.placeholderCount(for: model.profile.appearance.cardSize, style: row.style)
        return Strip(expands: row.style == .poster, kind: tileKind) {
            ForEach(0..<n, id: \.self) { i in
                Button {} label: { TilePlaceholder(kind: tileKind, rank: row.style == .top10 ? i + 1 : nil) }
                    .buttonStyle(.card)
                    .focused($focusedPlaceholder, equals: i)
                    .homeRowMenu(menu)
                    .accessibilityLabel("\(title), lädt")
            }
        }
    }

    /// Welle F-f: leere oder fehlgeschlagene Reihe bleibt erreichbar: eine Kachel in Reihenhöhe mit dem Grund;
    /// bei Fehlschlag lädt OK neu.
    /// `action`: eigener Neuversuch (Kit-Collection, Welle F-g); sonst lädt die Listen-Reihe neu.
    private func statusTile(_ text: String, retry canRetry: Bool, action: (() -> Void)? = nil) -> some View {
        Button {
            guard canRetry else { return }
            RemoteLog.info("home", "Reihe erneut laden: \(title)")
            if let action { action(); return }
            loaded = false; failed = false; retry += 1
            focusedPlaceholder = 0
        } label: {
            TileStatus(kind: tileKind, text: text, symbol: canRetry ? "arrow.clockwise" : nil)
        }
        .buttonStyle(.card)
        .focused($focusedPlaceholder, equals: 0)
        .homeRowMenu(menu)
    }

    /// Review M2 (S5): focus is still on a placeholder or a card of this row. Not the placeholder alone: the
    /// placeholders are another `switch` branch, so the loaded row removes them, and the focus engine may already
    /// have moved the focus to a card of this row (placeholder nil) when the hand-over runs.
    private var rowHoldsFocus: Bool { focusedRoute != nil || focusedPlaceholder != nil }

    /// S5 (Build 4 follow-up): focus goes from a placeholder to the loaded card. The home page's heading snap
    /// restarts once the card holds the focus (`onChange(of: focusedRoute)`), or right away when it already does.
    private func handOver(to target: Route) {
        if focusedRoute == target { onFocusInside?(true); return }
        handoverTarget = target
        focusedRoute = target
    }

    /// Task 4.1a (F-A-3): this row is the home page's focus target: remembered tile, else the first tile, else
    /// placeholder/status tile 0. Next run loop, after the layout change built the row.
    private func claimFocusTarget() {
        guard let focusTarget, focusTarget.claim(.row(row.id)) else { return }
        let target = rememberedRoute ?? firstRoute
        DispatchQueue.main.async {
            if let target { focusedRoute = target } else { focusedPlaceholder = 0 }
        }
    }

    /// First tile of the row, if tiles are shown.
    private var firstRoute: Route? {
        switch row.content {
        case .collection(let id):
            guard case .tiles = collectionPhase(id, model.collection(id)) else { return nil }
            return model.collection(id)?.folders.first.map { Route.folder($0) }
        case .list:
            guard case .items = phase, let m = displayed.first else { return nil }
            return routeTable[m.id] ?? .detail(m)
        }
    }

    /// Zuletzt fokussierte Kachel dieser Reihe, sofern noch vorhanden (sonst entscheidet die Fokus-Engine).
    private var rememberedRoute: Route? {
        guard let id = focusMemory?.state.remembered(row: row.id.uuidString) else { return nil }
        switch row.content {
        case .collection(let c):
            return model.collection(c)?.folders.first { "folder:\($0.id)" == id }.map { Route.folder($0) }
        case .list:
            return items.first { $0.id == id }.map(route(for:))
        }
    }

    /// Weiterschauen mit gemerkter Quelle → direkt abspielen, sonst Detailseite.
    private func route(for m: MetaPreview) -> Route {
        guard row.content == .list(.continueWatching), let e = model.progress.resumeTargets()[m.id] else { return .detail(m) }
        return Self.resumeRoute(m, e)
    }

    /// Task 3.8 ([04 §6.5]): play targets of the shown cards (item id → route), built once per row pass from one
    /// `resumeTargets()` call. Before, every card sorted the whole progress book on every focus step.
    /// Cards missing here open the detail page. Empty outside the continue row.
    private var routeTable: [String: Route] {
        guard row.content == .list(.continueWatching) else { return [:] }
        let targets = model.progress.resumeTargets()
        var out: [String: Route] = [:]
        for m in displayed { if let e = targets[m.id] { out[m.id] = Self.resumeRoute(m, e) } }
        return out
    }

    private static func resumeRoute(_ m: MetaPreview, _ e: WatchProgress) -> Route {
        let title = e.season.map { "\(m.name) S\($0)E\(e.episode ?? 0)" } ?? m.name
        return .streams(PlayRequest(type: e.season == nil ? "movie" : "series", id: e.id, title: title, item: m,
                                    season: e.season, episode: e.episode, resumeLastSource: true))
    }

    private func card<L: View>(_ route: Route, @ViewBuilder label: () -> L) -> some View {
        NavigationLinkish(route: route, onActivate: onActivate, label: label())
            .focused($focusedRoute, equals: route)
            .tileMenu(route.tileItem, inContinueRow: row.content == .list(.continueWatching),
                      inWatchlistRow: row.content == .list(.watchlist), row: menu) { focusNeighbour(of: route) }   // Wave L
    }

    /// Wave L: the card leaves the row through its long-press menu: focus moves to the right neighbour, else the left.
    private func focusNeighbour(of r: Route) {
        let table = routeTable
        let routes = displayed.map { table[$0.id] ?? .detail($0) }
        guard let i = routes.firstIndex(of: r), let n = TileMenuAction.neighbour(removing: i, count: routes.count) else { return }
        let target = routes[n]
        // Closing the menu hands focus back to the card: retry up to 3 times, 100 ms apart, until it lands.
        Task { @MainActor in
            for _ in 0..<3 {
                try? await Task.sleep(for: .milliseconds(100))
                if focusedRoute == target { return }
                focusedRoute = target
            }
        }
    }
}

/// Welle F-g: eine Logzeile je Collection-Reihe („Collection <titel>: <n> Kacheln, Bilder <n>, GIF <n>“), erneut nur,
/// wenn sich der Stand ändert (LazyVStack baut Reihen beim Scrollen ab und wieder auf).
/// Wave F-k: also the badge line of poster rows (own key per row, same rule).
@MainActor
enum CollectionRowLog {
    private static var last: [String: String] = [:]

    static func note(row: String, line: String) {
        guard last[row] != line else { return }
        last[row] = line
        RemoteLog.info("home", line)
    }

    private static var pending: [String: Task<Void, Never>] = [:]

    /// Wave F-k R1: like `note`, but only after the line has rested 2 s (a newer call replaces a waiting one).
    static func noteLater(row: String, line: @escaping @MainActor () -> String) {
        pending[row]?.cancel()
        pending[row] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            CollectionRowLog.pending[row] = nil
            CollectionRowLog.note(row: row, line: line())
        }
    }
}

/// Wie NavigationLink, aber das Ziel kann verschluckt werden (`onActivate` gibt nil zurück).
struct NavigationLinkish<L: View>: View {
    let route: Route
    let onActivate: (Route) -> Route?
    let label: L
    @Environment(\.navigate) private var navigate

    var body: some View {
        Button { if let r = onActivate(route) { navigate(r) } } label: { label }
            .buttonStyle(.card)
    }
}

private struct NavigateKey: EnvironmentKey {
    /// Ohne gesetztes Ziel: nichts tun, aber im Log sichtbar machen (Diagnose für verlorene Umgebung).
    static let defaultValue: (Route) -> Void = { r in
        Task { @MainActor in RemoteLog.info("nav", "kein Navigationsziel für \(r.logName)") }
    }
}

extension EnvironmentValues {
    var navigate: (Route) -> Void {
        get { self[NavigateKey.self] }
        set { self[NavigateKey.self] = newValue }
    }
}

struct Strip<C: View>: View {
    @EnvironmentObject var model: AppModel
    /// Nur Posterreihen klappen auf (und bekommen den Platz am Reihenende).
    var expands = false
    /// Wave F-k: tile form of the row; sets the room for the focus lift (same for placeholders, status tile and
    /// cards of one row, so the row does not jump when its entries arrive). No default (R1 M4): every row names it.
    let kind: TileKind
    @ViewBuilder let content: C
    /// Wave F-p R1: write-only scroll target of this row (see below); never read.
    @State private var position = ScrollPosition(idType: String.self)
    /// Build 4 follow-up S4: the anchor action handed to the cards. One box per strip, so every body pass puts the
    /// same value into the environment (a fresh closure per pass made every card's environment differ).
    @State private var anchorAction = CardAnchorAction()
    var body: some View {
        // Points the box at this strip's scroll position (a plain store into the box, observed by nobody).
        let _ = anchorAction.bind($position)
        let a = model.profile.appearance
        let s = a.cardSize.scale
        let expand = a.expandPosters && expands
        // Wave F-k: room above and below for the system card lift + shadow (`Theme.Focus.cardRowPadding`), at least
        // the former 32·s; the quality strip below a poster is part of the lifted card.
        let band = kind == .poster && a.titles.posterBadges == .bottom ? PosterQualityBadges.bandHeight : 0
        let pad = Theme.Focus.cardRowPadding(height: FocusHeadroom.tallest([kind], cardScale: s, posterExtra: band),
                                             minimum: Theme.Space.l * s)
        // Wave F-p: an expanding poster moves to the leading edge with one programmatic scroll, only when it expands
        // after its 350 ms rest. Before, `.scrollPosition(id:anchor:)` held a two-way `String?` binding that stayed on
        // the last expanded card; the row re-renders on every focus move, and the bound position competed with the
        // focus engine's own scroll to the new card. Fast left/right made the row wobble (build 214).
        // R1: the scroll goes through a `ScrollPosition` that the row only writes (`scrollTo(id:anchor:)`) and never
        // reads or compares, so a focus move never triggers it. Unlike `ScrollViewProxy` it acts on this horizontal
        // scroll view alone (no vertical jump of the page) and honours the leading content margin (edge 80).
        // Without the anchor the focus engine would not follow the card's growth (up to 640·s wide) to the right.
        // The lifted card (×1.15) must not cover its neighbour; landscape and collection tiles were too tight (23.11.).
        // Hero rows keep their spacing (one wide card per screen).
        let gap = kind == .hero ? Theme.Space.m * s
            : Theme.Focus.tileSpacing(width: PosterSize.tileSize(kind, scale: s).width, minimum: Theme.Space.m * s)
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: gap) { content }
                .scrollTargetLayout()
                .padding(.vertical, pad)
        }
        // Wave F-k: the lifted card (tag at the poster's top edge) and its shadow may reach past the row; the row
        // spans the full width, so nothing else becomes visible.
        .scrollClipDisabled()
        // Rand 80 (§4.3): Reihentitel, Hero-Info und erste Kachel starten auf einer Linie.
        .contentMargins(.leading, Theme.Space.edge, for: .scrollContent)
        // Platz rechts, damit auch die letzten Karten aufgeklappt (640·s) an den linken Rand rücken können.
        .contentMargins(.trailing, expand ? max(Theme.Space.edge, 1920 - Theme.Space.edge - 640 * s) : Theme.Space.edge,
                        for: .scrollContent)
        .scrollPosition($position)
        .environment(\.cardScale, s)
        .environment(\.expandPosters, expand)
        // Ohne eigene Animation: läuft in der Transaktion des Aufklappens mit, damit nur eine Bewegung entsteht.
        .environment(\.anchorFocusedCard, anchorAction)
    }
}


struct PosterCard: View {
    let item: MetaPreview
    @Environment(\.isFocused) private var focused
    @Environment(\.cardScale) private var scale
    @Environment(\.expandPosters) private var expandable
    @Environment(\.anchorFocusedCard) private var anchor
    /// S4 review: set on the home page only (both layouts); gates the card counter of the row metric.
    @Environment(\.homeRowFocusMemory) private var homeMemory
    /// Fokus + 350 ms Ruhe → Querformat mit Hintergrund und Logo.
    @State private var expanded = false

    var body: some View {
        // S4 review: `karten` field of `metric: home.rowBody` (shows whether `.equatable()` skips unchanged cards).
        let _ = RowBodyMeter.cardPass(onHome: homeMemory != nil)
        let w = Theme.Tile.width(.poster, scale), h = Theme.Tile.height(.poster, scale)
        // Welle E-a: Plaketten nie unten auf dem Bild; bei „Unten“ sitzen sie im Streifen darunter (PosterBadgeBand).
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                // Wave F-k: without any loadable picture the tile shows its title (TilePosterImage), never an empty card.
                TilePosterImage(item: item, showsTitle: !expanded)
                    .frame(width: w, height: h).clipped()
                if expanded { ExpandedPoster(item: item).transition(.opacity) }
            }
            .frame(width: (expanded ? h * 16 / 9 : w), height: h, alignment: .leading).clipped()
            .overlay { CardStateOverlay(itemID: item.id) }
            PosterBadgeBand(width: expanded ? h * 16 / 9 : w)
        }
        .overlay { PosterQualityBadges(item: item, scale: scale) }
        .task(id: focused && expandable) {
            guard focused && expandable else {
                if expanded { withAnimation(.easeInOut(duration: 0.25)) { expanded = false } }
                return
            }
            // Schnelles Durchscrollen bricht hier ab: kein Aufklappen, keine Bildanforderung.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            // Verankern nur zusammen mit dem Aufklappen: schnelles Durchscrollen löst kein Programm-Scrollen aus.
            // Task 4.1a (C1): the anchor id must equal the row's `ForEach` id (`rowKey`, type|id since F-A-5).
            withAnimation(.easeInOut(duration: 0.25)) { expanded = true; anchor(item.rowKey) }
        }
    }
}

/// Aufgeklappter Inhalt: Hintergrundbild (Größe nach Anzeige, ImageTarget) + Logo (oder Titel). Existiert erst nach der Ruhezeit,
/// deshalb wird das Bild auch erst dann angefordert.
private struct ExpandedPoster: View {
    let item: MetaPreview
    @Environment(\.displayScale) private var displayScale
    @Environment(\.heroBackdropShared) private var heroShared
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .bottomLeading) {
                // Mit Hero: gleiche Variante wie der Vollbild-Hintergrund (gleiche Adresse), ein Download, ein Bitmap.
                // Ohne Hero: nach gezeichneter Größe.
                RemoteImage(url: item.background ?? item.poster, fixedTarget: heroShared ? .fullScreen(scale: displayScale) : nil)
                    .frame(width: g.size.width, height: g.size.height).clipped()
                LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .bottom, endPoint: .center)
                Group {
                    // Breite begrenzt (rechts bleibt Platz für Bild und Plaketten oben rechts).
                    let maxW = g.size.width * PosterQualityBadges.leadingContentMaxFraction
                    if let logo = item.logo {
                        RemoteImage(url: logo, maxPixels: 600, fit: true)
                            .frame(maxWidth: maxW, maxHeight: g.size.height * 0.3, alignment: .bottomLeading)
                    } else {
                        Text(item.name).font(.headline).lineLimit(2).shadow(radius: 6)
                            .frame(maxWidth: maxW, alignment: .leading)
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 26)
            }
        }
    }
}

struct LandscapeCard: View {
    let item: MetaPreview
    @Environment(\.cardScale) private var scale
    var body: some View {
        let size = Theme.Tile.size(.landscape, scale)
        RemoteImage(url: item.background ?? item.poster, maxPixels: 900)
            .frame(width: size.width, height: size.height).clipped()
            .overlay(alignment: .bottomLeading) {
                Text(item.name).font(.headline).shadow(radius: 6).padding(.horizontal, 14).padding(.bottom, 24)
            }
            .overlay { CardStateOverlay(itemID: item.id) }
    }
}

struct HeroCard: View {
    let item: MetaPreview
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: item.background ?? item.poster)
                .frame(width: Theme.Tile.width(.hero, 1), height: Theme.Tile.height(.hero, 1)).clipped()
            LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .bottom, endPoint: .center)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(item.name).textRole(.display)
                if let d = item.description { Text(d).lineLimit(2).frame(maxWidth: 1000, alignment: .leading) }
                MetaLine(parts: [item.releaseInfo, DesignText.decimal(parsing: item.imdbRating).map { "★ \($0)" }])
            }
            .padding(Theme.Space.xl)
        }
        .frame(width: Theme.Tile.width(.hero, 1), height: Theme.Tile.height(.hero, 1))
    }
}

struct Top10Card: View {
    let item: MetaPreview
    let rank: Int
    @Environment(\.cardScale) private var scale
    var body: some View {
        HStack(alignment: .bottom, spacing: -30 * scale) {
            Text("\(rank)").font(.system(size: 220 * scale, weight: .black)).foregroundStyle(.white.opacity(0.85))
                .shadow(radius: 8)
            PosterCard(item: item)
        }
    }
}

struct FolderTile: View {
    let folder: Folder
    let logoStyle: Bool
    /// Wave F-o: setting "Ton bei Kachel-Animation" (sound of the focus video, once per focus).
    var sound = false
    @Environment(\.cardScale) private var scale
    /// Fokus der umgebenden Karte (Fokus-GIF, Welle F-g).
    @Environment(\.isFocused) private var focused
    var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(folder.title)
    }

    @ViewBuilder private var content: some View {
        let style = ReadyPackages.tileStyle(forFolderID: folder.id)
        if let style, logoStyle ? folder.logo == nil : (folder.coverImage == nil && folder.backdrop == nil) {
            // Welle F-g/F-l: eigene Paket-Kachel, solange kein Bild aus Import oder Kit vorliegt
            // (Farbverlauf + SF Symbol + deutscher Titel).
            packageTile(style, kind: logoStyle ? .logo : .landscape)
                // Wave F-o: focus video (else GIF) on every tile style that shows package art.
                .overlay { motion }
                .clipped()
        } else if logoStyle {
            ZStack {
                Color.white.opacity(0.08)
                if let l = folder.logo { RemoteImage(url: l, maxPixels: 800, fit: true).padding(30 * scale) } else { Text(folder.title).font(.headline) }
            }
            .frame(width: Theme.Tile.width(.logo, scale), height: Theme.Tile.height(.logo, scale))
            .overlay { motion }
            .clipped()
        } else {
            // Welle F-l: Titel über dem Bild wie bei der Quelle der Kachel. Paket-Kacheln mit Bild aus Kit oder Import
            // zeigen keinen zweiten Titel (der Name steht im Bild); die Bedienungshilfe liest ihn weiter vor.
            let titleOverImage = folder.coverImage == nil || folder.showsTitleOverImage
            // Welle F-l: Paket-Kachel, deren Bild noch lädt (oder nicht lädt): eigener Farbverlauf statt grauer Fläche,
            // mit Titel, solange keiner über dem Bild steht.
            RemoteImage(url: folder.coverImage ?? folder.backdrop,
                        placeholder: style.map { AnyView(packageTile($0, kind: .landscape, title: !titleOverImage)) })
                .frame(width: Theme.Tile.width(.landscape, scale), height: Theme.Tile.height(.landscape, scale)).clipped()
                // Welle F-g/F-o: bewegtes Fokusbild über dem Standbild (nur auf der fokussierten Kachel):
                // Video vor GIF.
                .overlay { motion }
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    if titleOverImage { Text(folder.title).font(.headline).shadow(radius: 4).padding(14) }
                }
        }
    }

    /// Wave F-o: what the focused tile plays over its still (video, else GIF, else nothing).
    private var motion: some View { TileMotionOverlay(folder: folder, focused: focused, sound: sound) }

    private func packageTile(_ style: PackageTileStyle, kind: TileKind, title: Bool = true) -> some View {
        ZStack {
            Theme.Tile.packageGradient(style.tone)
            VStack(spacing: 14 * scale) {
                Image(systemName: style.symbol).font(.system(size: 64 * scale, weight: .semibold))
                if title { Text(folder.title).font(.headline).lineLimit(1).minimumScaleFactor(0.7) }
            }
            .foregroundStyle(Theme.Palette.primary)
            .padding(.horizontal, 20 * scale)
        }
        .frame(width: Theme.Tile.width(kind, scale), height: Theme.Tile.height(kind, scale))
    }
}

/// Welle F-f: Platzhalter einer ladenden Reihe in Endgröße (gleiche Maße wie die Karte, Poster mit Plakettenstreifen,
/// Top 10 mit Rangziffer), damit die Reihe beim Eintreffen der Einträge nicht springt.
struct TilePlaceholder: View {
    let kind: TileKind
    var rank: Int? = nil
    @Environment(\.cardScale) private var scale

    var body: some View {
        if let rank {
            HStack(alignment: .bottom, spacing: -30 * scale) {
                Text("\(rank)").font(.system(size: 220 * scale, weight: .black)).foregroundStyle(.white.opacity(0.25))
                tile
            }
        } else {
            tile
        }
    }

    private var tile: some View {
        let size = Theme.Tile.size(kind, scale)
        return VStack(spacing: 0) {
            Theme.Tile.placeholder.frame(width: size.width, height: size.height)
            if kind == .poster { PosterBadgeBand(width: size.width) }
        }
        .accessibilityHidden(true)
    }
}

/// Welle F-f: Statuskachel einer leeren oder fehlgeschlagenen Reihe (Reihenhöhe wie die Karten, mindestens 440 breit,
/// damit der Text auch bei kleinen Postern in wenige Zeilen passt).
struct TileStatus: View {
    let kind: TileKind
    let text: String
    var symbol: String? = nil
    @EnvironmentObject var model: AppModel
    @Environment(\.cardScale) private var scale

    var body: some View {
        let size = Theme.Tile.size(kind, scale)
        // Poster: Streifen für Plaketten „Unten“ mitzählen (PosterBadgeBand), sonst springt die Reihe.
        let band = kind == .poster && model.profile.appearance.titles.posterBadges == .bottom ? PosterQualityBadges.bandHeight : 0
        let height = size.height + band
        VStack(spacing: Theme.Space.s) {
            if let symbol { Image(systemName: symbol).font(.title3) }
            Text(text).textRole(.rowDetail).multilineTextAlignment(.center).lineLimit(3)
        }
        .padding(Theme.Space.m)
        .frame(width: max(size.width, Theme.Tile.width(.landscape, 1)), height: height)
        .background(Theme.Tile.placeholder)
        .accessibilityElement(children: .combine)
    }
}

/// Kachelzustand: Haken (gesehen), Folge + Restzeit oben, Fortschrittsbalken unten.
struct CardStateOverlay: View {
    @EnvironmentObject var model: AppModel
    let itemID: String
    /// „Heute neu“ zeigt oben links sein eigenes Folgen-Label; dann entfällt hier die obere Kapsel.
    @Environment(\.hidesCardTopLabel) private var hidesTopLabel

    var body: some View {
        if let st = model.progress.cardState(itemID: itemID) {
            ZStack {
                if st.watched {
                    Image(systemName: "checkmark.circle.fill").font(.title3)
                        .symbolRenderingMode(.palette).foregroundStyle(.black, .white)
                        .shadow(radius: 4).padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                let top = DesignText.metaLine([st.episode, st.remainingSeconds.map { "noch \(max(1, Int($0 / 60))) min" }])
                if !top.isEmpty && !hidesTopLabel {
                    ThemeBadge(kind: .status(nil, onImage: true), text: top).padding(Theme.Space.xs)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                if let f = st.fraction, f > 0 {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.3))
                            Capsule().fill(.white).frame(width: g.size.width * min(1, f))
                        }
                    }
                    .frame(height: 6).padding(.horizontal, 10).padding(.bottom, 10)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Kartengröße und Aufklappen (Umgebung, von `Strip` gesetzt)

private struct CardScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
/// Außerhalb der Startseiten-Reihen (Detail, Person) klappt nichts auf.
private struct ExpandPostersKey: EnvironmentKey { static let defaultValue = false }
private struct AnchorFocusedCardKey: EnvironmentKey { static let defaultValue = CardAnchorAction() }

/// Build 4 follow-up S4: the strip's "anchor this card" action. Equal only to itself (box identity), so a strip
/// body pass hands its cards an unchanged environment value and their `.equatable()` holds. Outside a strip (no
/// bound position) the call does nothing, as the former default closure did.
struct CardAnchorAction: Equatable {
    /// Used on the main thread only (strip body and card focus task).
    final class Box: @unchecked Sendable {
        var position: Binding<ScrollPosition>?
    }
    private let box = Box()

    /// Strip body: the position the action scrolls (same binding on every pass).
    func bind(_ position: Binding<ScrollPosition>) { box.position = position }

    /// Card: scroll the strip so the card with this `ForEach` id sits at the leading edge.
    func callAsFunction(_ id: String) {
        guard let position = box.position else { return }
        position.wrappedValue.scrollTo(id: id, anchor: .leading)
    }

    static func == (a: CardAnchorAction, b: CardAnchorAction) -> Bool { a.box === b.box }
}
private struct HidesCardTopLabelKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// `appearance.cardSize.scale` für die Kartenmaße.
    var cardScale: CGFloat {
        get { self[CardScaleKey.self] }
        set { self[CardScaleKey.self] = newValue }
    }
    var expandPosters: Bool {
        get { self[ExpandPostersKey.self] }
        set { self[ExpandPostersKey.self] = newValue }
    }
    /// Fokussierte, aufklappbare Karte meldet ihre ID; die Reihe verankert die Scrollposition daran.
    /// The id is the `ForEach` id of the strip: `MetaPreview.rowKey` (Task 4.1a, C1).
    var anchorFocusedCard: CardAnchorAction {
        get { self[AnchorFocusedCardKey.self] }
        set { self[AnchorFocusedCardKey.self] = newValue }
    }
    /// Blendet in `CardStateOverlay` die Folgen/Restzeit-Kapsel oben links aus (Haken und Balken bleiben).
    var hidesCardTopLabel: Bool {
        get { self[HidesCardTopLabelKey.self] }
        set { self[HidesCardTopLabelKey.self] = newValue }
    }
}
