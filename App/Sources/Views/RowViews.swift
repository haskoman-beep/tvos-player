import SwiftUI
import Combine
import PlayerCore

/// Eine Startseiten-Reihe im gewählten Stil.
/// `onActivate` bekommt das Ziel und gibt zurück, ob navigiert werden soll (nil = Klick verschlucken).
struct HomeRowView: View {
    @Environment(AppModel.self) var model
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
    /// Device test 1 (Build 4 follow-up 2): filters the row's raw focus state for `onFocusInside` (a gap between two
    /// cards is no leave). A reference held in `@State`: changes do not re-render the row.
    @State private var presence = RowFocusPresenceBox()
    /// Build 6 (redraw): the row's focus as reported by its cards and placeholders (`RowFocusTracker`). A reference
    /// held in `@State`, observed by nobody: the row body never reads its `@FocusState`s, so a focus move does not
    /// run it. The `@FocusState`s stay for `.focused`, `.defaultFocus` and the programmatic moves (written only).
    @State private var focusBox = RowFocusBox()
    /// Build 6: bumped with every programmatic focus write (`focusCard`, `focusPlaceholder`). Read in the body and
    /// part of the cards' `==`, so such a write runs the row and its cards once, as the body read did before.
    @State private var focusSerial = 0
    /// Build 6: bumped when the focus really left the row; the one row pass it causes refreshes `rememberedRoute`
    /// for `.defaultFocus` (before, every focus move ran the body and kept it current).
    @State private var leavePass = 0
    /// Startseite mit Hero: fokussierte Kachel meldet sich (nil außerhalb der Startseite).
    @Environment(HomeFocus.self) private var homeFocus: HomeFocus?
    @FocusState private var focusedRoute: Route?
    /// Welle C-b (#19): Fokus-Gedächtnis je Reihe (nil außerhalb der Startseite).
    @Environment(\.homeRowFocusMemory) private var focusMemory
    /// Welle C-d: nachgezogene Sendezeiten (TVmaze) → Reihe „Heute neu“ lädt aus dem Kalender-Cache neu.
    @ObservedObject private var upcomingRevision = UpcomingRevision.shared
    /// Welle F-g: Kit-Ladefehler und laufende Ladungen (Statuskachel der Kit-Collections).
    @ObservedObject private var kit = FusionKitStore.shared
    /// Task 5.1: card and row options (`ThemeValues.cards`) and the diagnosis switch „alte Karte“.
    @Environment(\.theme) private var theme
    @AppStorage(CardDiagnostics.oldCardKey) private var oldCard = false

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
        // Build 6 (redraw): the only focus-related reads at body time (see the two `@State`s).
        let _ = focusSerial
        let _ = leavePass
        // Points the box at this pass's handlers (a plain store, like `CardAnchorAction.bind`); only while the row is
        // on screen (third review L2: a pass while covered would bring the retain cycle back).
        let _ = bindFocusBox()
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if row.style != .hero {
                // P2 fix round (review M1): one line, the collapsed hero list fits a row with a one-line heading.
                RowHeading(title: title, size: cardStyle.legacy ? .standard : cardStyle.rowTitle)
                    .padding(.leading, Theme.Space.edge)
            }
            content
                .focusSection()
                .defaultFocus($focusedRoute, rememberedRoute, priority: .userInitiated)
        }
        // Task 5.1: the strip and its cards draw these options (default outside: legacy).
        .environment(\.cardStyle, cardStyle)
        .onChange(of: cardStyle, initial: true) { _, s in if focusMemory != nil { CardStyleLog.note(s) } }
        .task(id: loadKey) {
            guard case .list(let s) = row.content else { return }
            // Welle F-f: geteilte Ladung (AppModel+HomeRows), läuft beim Wegscrollen weiter.
            let r = await model.homeRowItems(s)
            guard !Task.isCancelled else { return }   // abgebrochen (neue Ladung folgt): kein „Keine Einträge“-Flackern
            // Build 6 re-review H1: the box, not the FocusState; third review M1: or the slot a programmatic write
            // (retry tile) is still waiting for.
            let placeholder = focusBox.placeholderSlot ?? focusBox.pendingSlot
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
                    focusBox.clearPending()   // third review M1: the hand-over consumes the latched slot
                    if let target { handOver(to: target) } else { focusPlaceholder(slot) }
                }
            }
        }
        // Build 6 (redraw): no `onChange(of: focusedRoute)` here any more. Before, the row read its focus state at body
        // time (these handlers, the cards' focus flags) and every focus move (old card → nil → new card) ran the whole
        // row body twice (`metric: home.rowBody` ≈ 2 × `fokus`). The cards report instead (`focusBox`).
        .onAppear {
            // Build 6 re-review M2: `onDisappear` dropped the handlers; the body may not run again.
            focusBox.appear()
            bindFocusBox()
            // Third review L3: a probe that appeared before the row reported its card to unbound handlers: replay it.
            // (Probes after this point report through the handlers, so nothing runs twice.)
            if let r = focusBox.card { routeChanged(from: nil, to: r) }
            if focusBox.inside { reportInside(true) }
        }
        // Task 4.1a (F-A-2): collection rows hand over like list rows: a focused placeholder (or status tile) goes to
        // the tile at the same place when the kit file arrives, else to the status tile.
        .onChange(of: collectionLoadPhase) { _, p in
            // Review minor 1: the change into `.loading` (OK on the status tile) is no hand-over.
            // Third review M1: the placeholders' `onDisappear` may have run first; their slot is latched then.
            guard let p, p != .loading, let placeholder = focusBox.placeholderSlot ?? focusBox.pendingSlot,
                  case .collection(let id) = row.content
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
                focusBox.clearPending()   // third review M1
                // S5: the heading snap restarts once the tile holds the focus (the F-A-2 line above is the log).
                if let target { handOver(to: target) } else { focusPlaceholder(slot) }
            }
        }
        // Task 4.1a (F-A-3): `initial` also claims a target when the lazy list builds this row after the scroll.
        .onChange(of: focusTarget?.serial, initial: true) { _, _ in claimFocusTarget() }
        .onDisappear {
            presence.disappear()
            // Build 6 re-review M2: drop the handlers (they capture the row, the box lives in the row's state: a
            // cycle for every row the lazy stack unloads). L3: the focus itself is not reset; the probes report false
            // when they leave and their focus again when they appear.
            focusBox.unbind()
            focusBox.clearPending()   // third review M1: no hand-over for a row that left the screen
            onFocusInside?(false)
            if handoverTarget != nil { handoverTarget = nil }   // Review M1
            // Wave F-p R1: page left with focus in this row before its prefetch rest ended: no stale request.
            if let r = focusBox.card { StreamPrefetcher.shared.cancelRest(r) }
        }
    }

    /// Review M1: focus left the row: a pending hand-over ends here (no stale restart on a later visit).
    /// Build 6: called through `focusBox` (was `onChange` on the row).
    private func insideChanged(_ f: Bool) {
        if !f, handoverTarget != nil { handoverTarget = nil }
        reportInside(f)
    }

    /// The row's focused card changed (`old` → `r`; nil between two cards). Build 6: called through `focusBox`.
    private func routeChanged(from old: Route?, to r: Route?) {
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
                // Build 6: a genre row counts no motion (it shows none, `TileMotion.isStillRow`).
                let still = c.map(TileMotion.isStillRow) ?? false
                let line = CollectionArtStats(folders: folders, logoStyle: row.style == .logoTiles, stillRow: still)
                    .logLine(title: title)
                // Welle F-l: Paket-Reihen melden zusätzlich, wie viele Paket-Kacheln ein Bild bzw. GIF haben.
                let packLine = PackageArtStats(folders: folders, stillRow: still)?.logLine(row: title)
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
                        focusPlaceholder(0)
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
                let kind = tileKind
                let titles = titleSlot(kind)
                Strip(expands: rowExpands(kind), kind: kind) {
                    ForEach(displayedEntries) { e in
                        let m = e.item
                        let r = routes[m.id] ?? .detail(m)
                        listCard(r, item: m, rank: row.style == .top10 ? e.rank : nil, titles: titles, kind: kind) {
                            cardContent(e, kind: kind, titled: titles != nil)
                        }
                    }
                }
                // Wave F-k R1: row of these tiles for the visible-tile prefetch (order, log line).
                .environment(\.prefetchRow, PrefetchRow(key: "home|\(row.id.uuidString)", title: title))
                // Wave F-k: how many tiles know their quality (source cache only), again when a prefetch lands here.
                .task(id: displayed.map(\.id)) { noteBadges() }
                .onReceive(QualityBadgeCache.shared.stored) { ids in
                    // S3: cheap per item (`streamCacheKeyMatches`), same answer as comparing `streamCacheKey(for:)`.
                    // Log only: no state of the row changes here (P3 check), so the row body does not run again.
                    guard cardsCarryBadges, batchTouchesRow(ids) else { return }
                    noteBadges()
                }
            }
        }
    }

    /// Task 5.1: the card of one entry. The form comes from `tileKind` (card form option), not from the row style
    /// alone; Top 10 and hero rows keep their own cards.
    @ViewBuilder private func cardContent(_ e: RowEntry, kind: TileKind, titled: Bool) -> some View {
        let m = e.item
        if row.content == .list(.upcoming) {
            UpcomingTodayCard(item: m, landscape: kind == .landscape, titleOnPicture: !titled)
        } else {
            switch row.style {
            case .hero: HeroCard(item: m)
            case .top10: Top10Card(item: m, rank: e.rank).equatable()
            default:
                if kind == .landscape { LandscapeCard(item: m).equatable() } else { PosterCard(item: m).equatable() }
            }
        }
    }

    /// Task 5.1: the card options in effect for this row: the look on the home page (both layouts), Build 4 cards
    /// with the diagnosis switch „alte Karte“ and on the other pages that reuse this row (library, collection, list).
    private var cardStyle: CardStyle { CardStyle.resolve(theme, oldCard: oldCard || focusMemory == nil) }

    /// Task 5.1: geometry of this row's cards (title strip, title shift), nil when the row shows no titles below.
    private func titleSlot(_ kind: TileKind) -> CardTitleSlot? {
        let style = cardStyle
        guard !style.legacy, style.titles != .aus, CardLayout.showsTitleStrip(style: row.style) else { return nil }
        let band = kind == .poster && model.profile.appearance.titles.posterBadges == .bottom ? PosterQualityBadges.bandHeight : 0
        let g = CardLayout.row(kind: kind, home: theme.cards.home, badgeBand: band,
                               titleLine: CardTitleMetrics.line(theme.type))
        guard g.titleStrip > 0 else { return nil }
        let width: CGFloat = Theme.Tile.width(kind, model.profile.appearance.cardSize.scale)
        return CardTitleSlot(mode: style.titles, width: width, shift: g.titleShift, strip: g.titleStrip)
    }

    /// Task 5.1: poster rows expand (Build 4: style „Poster“; now also landscape rows recut to posters).
    private func rowExpands(_ kind: TileKind) -> Bool {
        if cardStyle.legacy { return row.style == .poster }
        return (row.style == .poster || row.style == .landscape) && kind == .poster
    }

    /// P3: one of the batched cache IDs belongs to a tile of this row.
    private func batchTouchesRow(_ ids: Set<String>) -> Bool {
        displayed.contains { QualityBadgeCache.shared.match(ids, for: $0, model: model) != nil }
    }

    /// Wave F-k: log line „Plaketten: <row> n/m mit Qualität“ for poster rows (only these carry quality badges);
    /// logged only when the count changes and has rested 2 s (prefetch results arrive one by one).
    private func noteBadges() {
        guard cardsCarryBadges, !displayed.isEmpty else { return }
        let m = model, items = displayed, name = title
        CollectionRowLog.noteLater(row: "badges|\(row.id.uuidString)") {
            let a = m.profile.appearance
            let n = items.filter { PosterBadgeStats.hasBadges(QualityBadgeCache.shared.best(for: $0, model: m), settings: a.badges) }.count
            return PosterBadgeStats.logLine(row: name, withQuality: n, total: items.count, placement: a.titles.posterBadges)
        }
    }

    /// Kachelform der Reihe; „Heute neu“ im Hero-Stil zeigt Querformat-Karten (UpcomingTodayCard).
    /// Task 5.1: list rows of style poster or landscape follow the card form option (`CardLayout.tileKind`).
    private var tileKind: TileKind {
        CardLayout.tileKind(of: row, home: theme.cards.home, oldCard: cardStyle.legacy)
    }

    /// Wave F-k / Task 5.1: the row's cards carry quality badges (posters; since 5.1 also landscape film cards).
    private var cardsCarryBadges: Bool {
        let kind = tileKind
        if kind == .poster { return true }
        return kind == .landscape && !cardStyle.legacy && row.content != .list(.upcoming)
            && CardLayout.showsTitleStrip(style: row.style)
    }

    /// Row style matching the shown tile form (placeholder count).
    private var placeholderStyle: RowStyle {
        guard row.style == .poster || row.style == .landscape else { return row.style }
        return tileKind == .landscape ? .landscape : .poster
    }

    /// Welle F-f: ladende Reihe, fokussierbare Platzhalter in Endgröße (Höhe springt beim Eintreffen nicht).
    /// Das Kontextmenü gilt auch hier (eine hängende Reihe lässt sich ausblenden oder löschen).
    private var placeholders: some View {
        let n = PosterSize.placeholderCount(for: model.profile.appearance.cardSize, style: placeholderStyle)
        let kind = tileKind
        // Task 5.1: same title room as the loaded cards, so the row does not grow when they arrive.
        let strip = titleSlot(kind)?.strip ?? 0
        let box = focusBox
        return Strip(expands: rowExpands(kind), kind: kind) {
            ForEach(0..<n, id: \.self) { i in
                VStack(spacing: 0) {
                    Button {} label: {
                        TilePlaceholder(kind: kind, rank: row.style == .top10 ? i + 1 : nil)
                            // Build 6; third review M1: removed while focused (row loaded) = latched for the hand-over.
                            .background {
                                ButtonFocusProbe(report: { f in box.placeholder(i, focused: f) },
                                                 gone: { box.placeholderGone(i) })
                            }
                    }
                        .modifier(CardButtonStyleModifier())
                        .focused($focusedPlaceholder, equals: i)
                        .homeRowMenu(menu)
                        .accessibilityLabel("\(title), lädt")
                    if strip > 0 { Color.clear.frame(height: strip).accessibilityHidden(true) }
                }
            }
        }
    }

    /// Welle F-f: leere oder fehlgeschlagene Reihe bleibt erreichbar: eine Kachel in Reihenhöhe mit dem Grund;
    /// bei Fehlschlag lädt OK neu.
    /// `action`: eigener Neuversuch (Kit-Collection, Welle F-g); sonst lädt die Listen-Reihe neu.
    private func statusTile(_ text: String, retry canRetry: Bool, action: (() -> Void)? = nil) -> some View {
        let box = focusBox
        return Button {
            guard canRetry else { return }
            RemoteLog.info("home", "Reihe erneut laden: \(title)")
            if let action { action(); return }
            // Build 7 review (L4): a retry asks the source again even within the 30 s failure memory.
            if case .list(let s) = row.content { model.recentLoadFailures.forget(s.id) }
            loaded = false; failed = false; retry += 1
            focusPlaceholder(0)
        } label: {
            TileStatus(kind: tileKind, text: text, symbol: canRetry ? "arrow.clockwise" : nil)
                // Build 6 re-review L4: own tracker slot (its `.focused` value stays 0, like the first placeholder).
                .background {
                    let slot: Int = RowFocusTracker<Route>.statusSlot
                    ButtonFocusProbe(report: { f in box.placeholder(slot, focused: f) },
                                     gone: { box.placeholderGone(slot) })
                }
        }
        .modifier(CardButtonStyleModifier())
        .focused($focusedPlaceholder, equals: 0)
        .homeRowMenu(menu)
        // Task 5.1 fix round (m1): same title room as placeholders and cards, so a failed or empty row keeps its height.
        .padding(.bottom, titleSlot(tileKind)?.strip ?? 0)
    }

    /// Review M2 (S5): focus is still on a placeholder or a card of this row. Not the placeholder alone: the
    /// placeholders are another `switch` branch, so the loaded row removes them, and the focus engine may already
    /// have moved the focus to a card of this row (placeholder nil) when the hand-over runs.
    /// Build 6 re-review H1: from the cards' reports (`focusBox`); the `@FocusState`s are written only, never read,
    /// so the row never becomes a dependent of them.
    /// Third review M1: or a placeholder slot still latched for the hand-over (the old focus state kept its value
    /// until the focus engine moved, the probe reports the removal at once).
    private var rowHoldsFocus: Bool { focusBox.inside || focusBox.pendingSlot != nil }

    /// Device test 1 (Build 4 follow-up 2): moving right, the raw state passed through "nothing focused" between two
    /// cards, so the row reported leave + enter on every step and the heading snap scrolled again each time (the
    /// heading jittered). An enter is reported at once, a leave only after `RowFocusPresence.leaveDelayMs` without
    /// the focus coming back; the `nav` line on the real leave counts the bridged gaps.
    private func reportInside(_ inside: Bool) {
        guard let onFocusInside else { return }
        let box = presence
        switch box.state.raw(inside, now: ProcessInfo.processInfo.systemUptime) {
        case .none:
            break
        case .enter:
            box.cancelLeave()
            onFocusInside(true)
        case .cancelLeave:
            box.cancelLeave()
        case .scheduleLeave(let serial):
            box.cancelLeave()
            let name = title
            box.leave = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(RowFocusPresence.leaveDelayMs))
                guard !Task.isCancelled else { return }
                box.leave = nil
                // Third review M1: the reported focus, not `rowHoldsFocus`: a latched slot that never lands must not
                // hold the row "inside" for good.
                guard let leave = box.state.leaveDue(serial: serial, inside: focusBox.inside) else { return }
                if let line = leave.line(title: name) { RemoteLog.info("nav", line) }
                onFocusInside(false)
            }
        }
    }

    /// S5 (Build 4 follow-up): focus goes from a placeholder to the loaded card. The home page's heading snap
    /// restarts once the card holds the focus (`routeChanged`), or right away when it already does.
    private func handOver(to target: Route) {
        if focusBox.card == target { onFocusInside?(true); return }
        handoverTarget = target
        focusCard(target)
    }

    /// Build 6: points `focusBox` at this row's handlers (every body pass and `onAppear`).
    private func bindFocusBox() {
        guard focusBox.onScreen else { return }
        focusBox.bind(onRoute: { old, r in routeChanged(from: old, to: r) },
                      onInside: { f in insideChanged(f) },
                      onLeftRow: { leavePass &+= 1 })
    }

    /// Build 6 (redraw): programmatic focus moves. The row body does not read the `@FocusState`s, so a plain write
    /// would not run it; the serial does (row pass + every card, `HomeRowCard ==`), as the body read did before, so
    /// the `.focused` modifiers of skipped cards and placeholders see the write in the same update.
    private func focusCard(_ r: Route) {
        focusSerial &+= 1
        focusedRoute = r
    }

    private func focusPlaceholder(_ slot: Int) {
        focusSerial &+= 1
        focusBox.expectPlaceholder(slot)   // third review M1: pending until a placeholder reports the focus
        focusedPlaceholder = slot
    }

    /// Task 4.1a (F-A-3): this row is the home page's focus target: remembered tile, else the first tile, else
    /// placeholder/status tile 0. Next run loop, after the layout change built the row.
    private func claimFocusTarget() {
        guard let focusTarget, focusTarget.claim(.row(row.id)) else { return }
        let target = rememberedRoute ?? firstRoute
        DispatchQueue.main.async {
            if let target { focusCard(target) } else { focusPlaceholder(0) }
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

    /// Task 5.1: a film/series card with its title below (`ThemeCard`) and its VoiceOver label and value.
    /// Fix round (M1): one structure for every option value (titles, „alte Karte“), so the focusable Button keeps its
    /// identity when an option changes while a card holds the focus; the options only change values. (Glow vs. the
    /// look's own focus effect stays a button style switch, `CardButtonStyleModifier`: the system card style has no
    /// value form.)
    /// b5r: an equatable `HomeRowCard`, so a focus move runs only the cards whose focus flag changed.
    private func listCard<L: View>(_ route: Route, item m: MetaPreview, rank: Int?, titles: CardTitleSlot?,
                                   kind: TileKind, @ViewBuilder label: () -> L) -> some View {
        let st: CardState? = model.progress.cardState(itemID: m.id)
        let value: String = CardLayout.accessibilityValue(year: m.releaseInfo, fraction: st?.fraction,
                                                          watched: st?.watched == true)
        // Review m6: Top 10 cards keep their rank in the label.
        let name: String = rank.map { "Platz \($0), \(m.name)" } ?? m.name
        let key = HomeRowCardKey(item: m, rank: rank, kind: kind, titled: titles != nil, style: row.style,
                                 upcoming: row.content == .list(.upcoming), row: row)
        // Build 6 (redraw): no focus flag from here; the card follows its own button focus and reports it to
        // `focusBox` (the row body must not read `focusedRoute`).
        let box = focusBox
        return HomeRowCard(route: route, name: name, accessibilityText: value, titles: titles, focusSerial: focusSerial,
                           inContinueRow: row.content == .list(.continueWatching),
                           inWatchlistRow: row.content == .list(.watchlist), labelKey: key, focus: $focusedRoute,
                           onActivate: onActivate, menu: menu, onLeave: { focusNeighbour(of: route) },
                           onFocus: { f in box.card(route, focused: f) },
                           label: label())
            .equatable()
    }

    private func card<L: View>(_ route: Route, @ViewBuilder label: () -> L) -> some View {
        let box = focusBox
        // Build 6: the folder tile reports its focus like the list cards (`focusBox`).
        let probed = label().background { ButtonFocusProbe { f in box.card(route, focused: f) } }
        return NavigationLinkish(route: route, onActivate: onActivate, label: probed)
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
                if focusBox.card == target { return }
                focusCard(target)
            }
        }
    }
}

/// Build 6 (redraw): the focus of one `HomeRowView` from its cards' and placeholders' own reports
/// (`ButtonFocusProbe` → `RowFocusTracker`), and the row handlers it runs. Not observable: the row never re-renders
/// for it. The handlers are stored on every row pass (`bind`); they reach the row's state through its storage.
@MainActor
final class RowFocusBox {
    private var tracker = RowFocusTracker<Route>()
    private var onRoute: (Route?, Route?) -> Void = { _, _ in }
    private var onInside: (Bool) -> Void = { _ in }
    private var onLeftRow: () -> Void = {}

    var inside: Bool { tracker.inside }
    /// The focused card of the row, nil without one.
    var card: Route? { tracker.card }
    /// The focused placeholder as the row's `focusedPlaceholder` value (status tile → 0).
    var placeholderSlot: Int? { tracker.focusStateSlot }
    /// Third review M1: the latched placeholder (focus state value), see `RowFocusTracker.pendingSlot`.
    var pendingSlot: Int? { tracker.pendingSlot }
    /// Third review L2: between the row's `onAppear` and `onDisappear`; handlers are bound only then.
    private(set) var onScreen = false

    func appear() { onScreen = true }

    func placeholderGone(_ slot: Int) { run(tracker.placeholderGone(slot)) }

    func expectPlaceholder(_ slot: Int) { tracker.expectPlaceholder(slot) }

    func clearPending() { tracker.clearPending() }

    func bind(onRoute: @escaping (Route?, Route?) -> Void, onInside: @escaping (Bool) -> Void,
              onLeftRow: @escaping () -> Void) {
        self.onRoute = onRoute
        self.onInside = onInside
        self.onLeftRow = onLeftRow
    }

    func card(_ r: Route, focused: Bool) { run(tracker.card(r, focused: focused)) }

    func placeholder(_ slot: Int, focused: Bool) { run(tracker.placeholder(slot, focused: focused)) }

    /// The row left the screen: drop the handlers (they capture the row; see `HomeRowView.onDisappear`). Reports
    /// still update the focus, without running anything.
    func unbind() {
        onScreen = false
        onRoute = { _, _ in }
        onInside = { _ in }
        onLeftRow = {}
    }

    private func run(_ events: [RowFocusTracker<Route>.Event]) {
        for e in events {
            switch e {
            case .route(let old, let new):
                onRoute(old, new)
            case .inside(let f):
                onInside(f)
                // Both reports of a move arrive in one update; still outside afterwards = a real leave.
                guard !f else { break }
                Task { @MainActor [weak self] in
                    guard let self, !self.inside else { return }
                    self.onLeftRow()
                }
            }
        }
    }
}

/// Device test 1 (Build 4 follow-up 2): `RowFocusPresence` of one row and its pending leave timer. Not observable:
/// the row never re-renders for it.
@MainActor
final class RowFocusPresenceBox {
    var state = RowFocusPresence()
    var leave: Task<Void, Never>?

    func cancelLeave() {
        leave?.cancel()
        leave = nil
    }

    /// The row left the screen: the visit ends without delay (the caller reports the leave).
    func disappear() {
        cancelLeave()
        _ = state.disappear()
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
            // Task 5.1: system card (glow, legacy and every page outside the home rows) or the look's focus effect.
            .modifier(CardButtonStyleModifier())
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
    @Environment(AppModel.self) var model
    /// Nur Posterreihen klappen auf (und bekommen den Platz am Reihenende).
    var expands = false
    /// Wave F-k: tile form of the row; sets the room for the focus lift (same for placeholders, status tile and
    /// cards of one row, so the row does not jump when its entries arrive). No default (R1 M4): every row names it.
    let kind: TileKind
    @ViewBuilder let content: C
    /// Wave F-p R1: write-only scroll target of this row (see below); never read.
    @State private var position = ScrollPosition(idType: String.self)
    /// Build 7 device test: the strip's horizontal scroll state for `StripFocusScroll` (written per scroll frame into
    /// the box, observed by nobody).
    @State private var scrollBox = StripScrollBox()
    /// Build 4 follow-up S4: the anchor action handed to the cards. One box per strip, so every body pass puts the
    /// same value into the environment (a fresh closure per pass made every card's environment differ).
    @State private var anchorAction = CardAnchorAction()
    /// Task 5.1: card options of the home rows (set by `HomeRowView`); legacy (Build 4 room) everywhere else.
    @Environment(\.cardStyle) private var cards
    @Environment(\.theme) private var theme
    var body: some View {
        // Points the box at this strip's scroll position (a plain store into the box, observed by nobody).
        let _ = anchorAction.bind($position)
        let a = model.profile.appearance
        let s = a.cardSize.scale
        // Task 5.1: `LookTheme.expandsPosters` (option, never under reduce motion; also with „alte Karte“: an
        // accessibility rule, not a look). `theme.cards.home.expandPosters` equals `a.expandPosters` (`Profile.themeLook`).
        let expand = expands && theme.expandsPosters
        let room = rowRoom(a, scale: s)
        let pad = room.pad
        let gap = room.gap
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
        // Build 7 device test ("Poster links abgeschnitten"): a left move ends with the card on the 80 pt line, not at
        // the screen edge where its lift is cut.
        .onScrollGeometryChange(for: StripScrollBox.Geometry.self) { g in
            StripScrollBox.Geometry(offsetX: Double(g.contentOffset.x), insetLeading: Double(g.contentInsets.leading))
        } action: { _, v in
            scrollBox.geometry = v
        }
        .scrollTargetBehavior(StripFocusScroll(box: scrollBox, clearance: Double(Theme.Space.edge)))
        .environment(\.cardScale, s)
        .environment(\.expandPosters, expand)
        // Ohne eigene Animation: läuft in der Transaktion des Aufklappens mit, damit nur eine Bewegung entsteht.
        .environment(\.anchorFocusedCard, anchorAction)
    }

    /// Lift room above/below the cards and the card ↔ card gap. Legacy (Build 4, every non-home strip): the system
    /// card lift (`Theme.Focus.cardRowPadding`, at least 32·s; the quality strip below a poster is part of the lifted
    /// card) and `Theme.Focus.tileSpacing`. Task 5.1 home rows: `CardLayout.row` (the look's focus effect and
    /// `rowSpacing`; with glow the same lift as Build 4, gap at least the look's card gap).
    private func rowRoom(_ a: Appearance, scale s: CGFloat) -> (pad: CGFloat, gap: CGFloat) {
        let band = kind == .poster && a.titles.posterBadges == .bottom ? PosterQualityBadges.bandHeight : 0
        if cards.legacy {
            let pad = Theme.Focus.cardRowPadding(height: FocusHeadroom.tallest([kind], cardScale: s, posterExtra: band),
                                                 minimum: Theme.Space.l * s)
            let gap: CGFloat = kind == .hero ? Theme.Space.m * s
                : Theme.Focus.tileSpacing(width: PosterSize.tileSize(kind, scale: s).width, minimum: Theme.Space.m * s)
            return (pad, gap)
        }
        let g = CardLayout.row(kind: kind, home: theme.cards.home, badgeBand: band, titleLine: 0, showsTitles: false)
        return (g.padding, g.cardGap)
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
    /// Task 5.1: rest and transition of the expand (Build 4: 350 ms / 0.25 s; look: 500 ms / `motion.expand`).
    @Environment(\.cardStyle) private var cards
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
            let animation: Animation? = cards.expandDuration > 0 ? .easeInOut(duration: cards.expandDuration) : nil
            guard focused && expandable else {
                if expanded { withAnimation(animation) { expanded = false } }
                return
            }
            // Schnelles Durchscrollen bricht hier ab: kein Aufklappen, keine Bildanforderung.
            try? await Task.sleep(for: .milliseconds(Int((cards.expandRest * 1000).rounded())))
            guard !Task.isCancelled else { return }
            // Verankern nur zusammen mit dem Aufklappen: schnelles Durchscrollen löst kein Programm-Scrollen aus.
            // Task 4.1a (C1): the anchor id must equal the row's `ForEach` id (`rowKey`, type|id since F-A-5).
            FrameMeter.event(.expand)   // P3: counted in the next `ruckler` line
            withAnimation(animation) { expanded = true; anchor(item.rowKey) }
        }
    }
}

/// Aufgeklappter Inhalt: Hintergrundbild (Größe nach Anzeige, ImageTarget) + Logo (oder Titel). Existiert erst nach der Ruhezeit,
/// deshalb wird das Bild auch erst dann angefordert.
private struct ExpandedPoster: View {
    let item: MetaPreview
    @Environment(\.heroBackdropShared) private var heroShared
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .bottomLeading) {
                // Mit Hero: gleiche Variante wie der Vollbild-Hintergrund (gleiche Adresse), ein Download, ein Bitmap.
                // Ohne Hero: nach gezeichneter Größe.
                // P3 device test 1: the hero's 1920×1080 target (`ImageTarget.heroBackdrop`), so it stays one bitmap.
                RemoteImage(url: item.background ?? item.poster, fixedTarget: heroShared ? .heroBackdrop : nil)
                    .frame(width: g.size.width, height: g.size.height).clipped()
                ImageScrim()   // Task 5.1 (D-8): one scrim under text on pictures
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
    /// Task 5.1: the look's cards (title below instead of on the picture, quality badges, scene picture or poster).
    @Environment(\.cardStyle) private var cards
    var body: some View {
        let size = Theme.Tile.size(.landscape, scale)
        if cards.legacy {
            RemoteImage(url: item.background ?? item.poster, maxPixels: 900)
                .frame(width: size.width, height: size.height).clipped()
                .overlay(alignment: .bottomLeading) {
                    Text(item.name).font(.headline).shadow(radius: 6).padding(.horizontal, 14).padding(.bottom, 24)
                }
                .overlay { CardStateOverlay(itemID: item.id) }
        } else {
            LandscapePicture(item: item, size: size, titleOnPicture: cards.titles == .aus)
                .overlay { CardStateOverlay(itemID: item.id) }
                .overlay { PosterQualityBadges(item: item, scale: scale, landscape: true) }
        }
    }
}

/// Task 5.1 (D-6): picture of a landscape card: the scene picture; without one the poster, cut to the card under a
/// scrim (the „querformat“ default recuts every poster row, and many catalogs carry no background).
/// With `cardTitles` „aus“ the title sits on the picture over `ImageScrim`.
private struct LandscapePicture: View {
    let item: MetaPreview
    let size: CGSize
    let titleOnPicture: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let bg = item.background {
                RemoteImage(url: bg, maxPixels: 900).frame(width: size.width, height: size.height).clipped()
            } else {
                TilePosterImage(item: item, showsTitle: false).frame(width: size.width, height: size.height).clipped()
                ImageScrim()
            }
            if titleOnPicture {
                if item.background != nil { ImageScrim() }
                Text(item.name).textRole(.rowTitleEmphasis).lineLimit(2)
                    .frame(maxWidth: size.width * PosterQualityBadges.leadingContentMaxFraction, alignment: .leading)
                    .padding(.horizontal, Theme.Space.s).padding(.bottom, Theme.Space.m)
            }
        }
        .frame(width: size.width, height: size.height)
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
    @Environment(AppModel.self) var model
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
/// Phase 0b: this view only looks the state up; the marks get it as a plain value and are redrawn only when it
/// differs (the progress book changes every 10 s during playback, the state of most tiles does not).
struct CardStateOverlay: View {
    @Environment(AppModel.self) var model
    let itemID: String

    var body: some View {
        if let st = model.progress.cardState(itemID: itemID) { CardStateMarks(state: st).equatable() }
    }
}

private struct CardStateMarks: View, Equatable {
    let state: CardState
    /// „Heute neu“ zeigt oben links sein eigenes Folgen-Label; dann entfällt hier die obere Kapsel.
    @Environment(\.hidesCardTopLabel) private var hidesTopLabel

    nonisolated static func == (a: CardStateMarks, b: CardStateMarks) -> Bool { a.state == b.state }

    var body: some View {
        let st = state
        ZStack {
            // Task 5.1 (D-23): shared marks of every card (same look as before).
            if st.watched { WatchedMark() }
            let top = DesignText.metaLine([st.episode, st.remainingSeconds.map { "noch \(max(1, Int($0 / 60))) min" }])
            if !top.isEmpty && !hidesTopLabel {
                ThemeBadge(kind: .status(nil, onImage: true), text: top).padding(Theme.Space.xs)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if let f = st.fraction, f > 0 { ThemeProgressBar(fraction: f) }
        }
        .allowsHitTesting(false)
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
/// Build 7 device test: last horizontal scroll state of one strip (main thread only, like `CardAnchorAction.Box`):
/// the leading inset for the start clamp and the offset for the log line.
final class StripScrollBox: @unchecked Sendable {
    struct Geometry: Equatable {
        var offsetX: Double
        var insetLeading: Double
    }
    var geometry: Geometry?
}

/// Build 7 device test ("Poster immer noch links abgeschnitten, wenn nach links geklickt"): moving left, the focus
/// engine scrolls only until the card's frame shows, i.e. to the screen edge, where the lifted card (scale, glow,
/// shadow) is cut. A target toward the leading end goes `clearance` (the 80 pt content margin) further, never past the
/// start position (`FocusScrollTarget.leading`); right moves and programmatic scrolls toward the trailing end are
/// unchanged. Device check: `nav: Fokus-Scroll links mit Rand …` lines show it is called.
struct StripFocusScroll: ScrollTargetBehavior {
    let box: StripScrollBox
    let clearance: Double

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard context.axes.contains(.horizontal), Thread.isMainThread else { return }   // b7 review 4
        let proposed = Double(target.rect.minX)
        // b7 review 1: the direction comes from the behaviour's own original target (same coordinate space as
        // `target`), so a right move or a resize can never count as a left move.
        let current = Double(context.originalTarget.rect.minX)
        let box = self.box
        let clearance = self.clearance
        let adjusted: Double = MainActor.assumeIsolated {
            // Build 8: the start is 0. The b7-1 log showed "vorher" = "Versatz" + 160 in all 7 lines with a 160 pt
            // leading inset: the target rect is inset-adjusted (0 = the strip's start position), not the raw
            // content offset, so the b7 clamp `-insetLeading` allowed an overscroll of the first card by the inset.
            guard let g = box.geometry else { return proposed }
            let start = 0.0
            let x = FocusScrollTarget.leading(proposed: proposed, current: current, clearance: clearance, minimum: start)
            if x != proposed, StripFocusScrollLog.allow() {
                RemoteLog.info("nav", FocusScrollTarget.leadingLine(proposed: proposed, adjusted: x, current: current,
                                                                    offset: g.offsetX, start: start))
            }
            return x
        }
        if adjusted != proposed { target.rect.origin.x = CGFloat(adjusted) }
    }
}

/// One `Fokus-Scroll links` line per second at most (all strips together).
@MainActor private enum StripFocusScrollLog {
    static var throttle = LogThrottle(interval: 1)
    static func allow() -> Bool { throttle.allow("links", now: ProcessInfo.processInfo.systemUptime) }
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
