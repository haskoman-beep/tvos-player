import SwiftUI
import PlayerCore

/// Startseite. Langer Druck auf eine Kachel → Kontextmenü der Reihe („Reihe bearbeiten“, „Ganz nach oben“, „Ausblenden …“);
/// geordnet wird im Verwalter „Reihen & Collections“ (Welle F-b2, Plan §2.5), nicht mehr im Vollbild-Editor.
/// Mit Hero (Spec §7a.1): hinten Hintergrund + Info des angezeigten Titels, darüber der ScrollView mit
/// Knopfzeile und Reihen. Angezeigt wird die Diashow-Folie oder, solange der Fokus in den Reihen liegt, die Kachel.
struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var focus = HomeFocus()
    /// Verwalter öffnen (Kontextmenü, Knopf unten, leere Startseite).
    @State private var manager: ManagerTarget?
    /// Rückfrage „Ausblenden“ aus dem Kontextmenü.
    @State private var hideCandidate: HomeRow?
    /// Welle F-f: Rückfrage „Löschen“ aus dem Kontextmenü.
    @State private var deleteCandidate: HomeRow?
    @State private var slides = HeroSlides()
    /// Welle C-b (#19): Fokus-Gedächtnis je Reihe; verdeckt, solange eine andere Seite darüber liegt.
    @State private var rowFocus = HomeRowFocusMemory()
    /// Wave F-j: top edge of the page, tab bar request and focus log.
    @State private var topWatch = HomeTopEdgeWatch()
    /// Build 3 device test: row whose heading is being snapped to the list's top edge (focus inside it).
    @State private var headingRow: UUID?
    /// Task 4.1a (F-A-3): focus target after a context-menu action (claimed by the row or the action button).
    @State private var focusTarget = HomeFocusTarget()
    /// Task 4.1a (F-A-11): rows holding the focus (launch claim of the page without hero).
    @State private var focusedRows: Set<UUID> = []
    /// P2 (follow-up 2): collapsing hero info while the focus is in the rows (read by `HeroListFrame` and `HeroLayer`).
    @State private var collapse = HeroCollapse()

    var body: some View {
        let layout = model.profile.home
        let appearance = model.profile.appearance
        let hero = layout.heroSource(appearance)
        let rows = layout.rowsBelowHero(appearance)
        // Task 4.1a (F-A-4): a failed or empty hero source keeps the hero layout (status in the hero frame); switching
        // the whole layout rebuilt every row and lost the focus.
        let showsHero = hero != nil
        let edge = HomeTopEdge.topmost(hasHero: showsHero, rowCount: rows.count, layoutEmpty: layout.rows.isEmpty)
        Group {
            if showsHero {
                heroHome(rows)
            } else {
                ScrollViewReader { proxy in
                    // Wave F-m: focus scrolling stops a card's frame at the list's edges, the lift reaches past them.
                    // The list is inset by the lift at the top and at the bottom and draws into that room; the mask
                    // keeps the old top clip line (review F-m I3: nothing in the overscan or the bar area) and lets
                    // the bottom room show. Bottom at least the safe area (review M2: overscan on some TVs).
                    let room = listBottomRoom(rows)
                    let bottom = max(room, Self.bottomSafeArea)
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: Theme.Space.xl) { rowList(rows, hero: false) }
                            .padding(.top, max(0, 40 - room))
                            .padding(.bottom, 40)
                            .coordinateSpace(.named(HomeTopEdgeWatch.contentSpace))   // S5: row frames
                            .id(HomeTopEdgeWatch.topID)
                            // Wave F-m R2: the tab bar guard binds the bar to this list, not to a tall row.
                            .background(alignment: .topLeading) { PageScrollViewProbe() }
                    }
                    .modifier(TopEdgeScroll(watch: topWatch, proxy: proxy))
                    .scrollClipDisabled()
                    .mask(alignment: .top) { Color.black.padding(.top, -room).padding(.bottom, -bottom) }
                    .padding(.top, room)
                    .padding(.bottom, bottom)
                    .ignoresSafeArea(edges: .bottom)
                }
                .task { await claimLaunchFocusWithoutHero(rows) }
            }
        }
        .environment(\.homeRowFocusMemory, rowFocus)
        .background { HomeTabBarRequest(watch: topWatch) }
        // Task 1.8: start page without hero (none configured or no slides): usable as soon as it shows; with a hero
        // the button row reports `start.usable` (`LaunchFocus`).
        .onChange(of: showsHero, initial: true) { _, hero in if !hero { RemoteLog.startUsable("ohneHero") } }
        .onChange(of: "\(edge.rawValue)|\(appearance.navigation.rawValue)", initial: true) {
            topWatch.configure(edge: edge, navigation: appearance.navigation)
        }
        .onAppear {
            rowFocus.state.covered = false
            topWatch.start()
            FrameMeter.homeVisible(true)   // S1: frame meter while focus moves on this page
        }
        .onDisappear {
            VisiblePage.covered()   // F-A-1: the manager is outside the path; a late hero jump is dropped too
            rowFocus.state.covered = true
            topWatch.stop()
            FrameMeter.homeVisible(false)
            focusTarget.drop("verworfen, Startseite verlassen")   // review I1
        }
        // Task 4.1a (F-A-4, A-B-6): the catalog stamp of the source is part of the key, so the slides follow a
        // background refresh and a failed source tries again at the next `catalogWake`; `retry` is the status tile.
        .task(id: hero.map { "\($0.id)|\($0.content.key)\(model.catalogStamp($0.content))|h\(slides.retry)" } ?? "-") {
            guard let hero else { return }
            guard case .list(let s) = hero.content else { slides.set([]); return }
            let r = await model.homeRowItems(s)   // same shared load as the row (heroItems without the failure)
            // Abgebrochene Ladung (Neuaufbau beim Start, Katalog -999) liefert []: nicht als „kein Hero“ werten.
            guard !Task.isCancelled else { return }
            slides.set(Array(RowItems.deduped(r.items).prefix(8)), failed: r.failed)
            RemoteLog.info("hero", "\(slides.items.count) Folien\(slides.phase == .failed ? " (Laden fehlgeschlagen)" : "")")
        }
        // Welle F-f: alle Listen vorladen (oben zuerst, begrenzt); sichtbare Reihen laden zusätzlich sofort selbst.
        // Neue Reihen ändern den Schlüssel und laden damit gleich.
        .task(id: rows.map(\.content.key)) { await model.preloadHomeRows(rows) }
        .navigationDestination(item: $manager) { t in HomeManagerView(focusRow: t.row, openBrowser: t.openBrowser) }
        // Task 4.1a (F-A-8): back from the manager (outside the path, no depth change): a new visit with a check.
        .onChange(of: manager) { old, new in if old != nil, new == nil { TabBarGuard.shared.check(.popped) } }
        // Eigene Rückfrage (F-a SettingsConfirmationView): „Behalten“ oben mit sicherem Standardfokus (§2.4).
        .settingsConfirmation(item: $hideCandidate, title: { "„\(model.homeRowTitle($0.content))“ ausblenden?" },
                              message: { _ in "Die Reihe verschwindet von der Startseite. In „Reihen & Collections“ lässt sie sich wieder einblenden." },
                              verb: "Ausblenden", symbol: "eye.slash") { row in
            quick { $0.hide(row.id) }
        }
        .settingsConfirmation(item: $deleteCandidate, title: { "„\(model.homeRowTitle($0.content))“ löschen?" },
                              message: { HomeView.deleteMessage($0) }, verb: "Löschen", symbol: "trash") { row in
            quick { $0.delete(row.id) }
        }
    }

    /// Folge des Löschens (Startseite und Verwalter gleich).
    static func deleteMessage(_ row: HomeRow) -> String {
        if case .collection = row.content {
            return "Die Reihe verschwindet für immer von der Startseite und steht nicht unter „Ausgeblendet“. "
                + "Die Collection selbst bleibt und lässt sich über „Reihe hinzufügen“ wieder anlegen."
        }
        return "Die Reihe verschwindet für immer von der Startseite und steht nicht unter „Ausgeblendet“. "
            + "Über „Reihe hinzufügen“ lässt sie sich neu anlegen."
    }

    /// Hintergrund- und Info-Ebene hinter dem ScrollView; der Hero ist kein eigener Scroll-Abschnitt.
    private func heroHome(_ rows: [HomeRow]) -> some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .topLeading) {
                HeroLayer(slides: slides, collapse: collapse)
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: Theme.Space.xl) {
                        HeroButtons(slides: slides, onFocusChange: { topWatch.report(.heroButtons, $0) })
                        rowList(rows, hero: true)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 60)
                    .coordinateSpace(.named(HomeTopEdgeWatch.contentSpace))   // S5: row frames
                    .id(HomeTopEdgeWatch.topID)
                    .background(alignment: .topLeading) { PageScrollViewProbe() }
                }
                .modifier(TopEdgeScroll(watch: topWatch, proxy: proxy))
                .environment(\.heroBackdropShared, true)
                // Wave F-k: focus scrolling keeps only the card's frame inside the list, the lift (tag at the poster's
                // top edge) reaches above it. The list draws past its top edge into a band as high as that lift
                // (`Theme.Focus.listEdgeBand`, clear of the hero info); only the band's top fades.
                .scrollClipDisabled()
                // Weicher Rand oben, damit hochgescrollte Reihen nicht hart an der Info abreißen.
                .mask(alignment: .top) {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: Theme.Focus.listFade)
                        Color.black
                    }
                    .padding(.top, -listEdgeBand(rows))
                    // Wave F-m: the mask reaches into the room below the list too (lifted card stays opaque).
                    .padding(.bottom, -listBottomRoom(rows))
                }
                // P2 (follow-up 2): list top (collapsing info) and the wave F-m room below the list.
                .modifier(heroListFrame(rows))
            }
        }
        .environment(focus)
    }

    /// P2 (follow-up 2): frame of the hero list; the collapsed top fits the tallest row (`HeroInfoCollapse`).
    private func heroListFrame(_ rows: [HomeRow]) -> HeroListFrame {
        let a = model.profile.appearance
        let strip = a.titles.posterBadges == .bottom ? PosterQualityBadges.bandHeight : 0
        return HeroListFrame(focus: focus, collapse: collapse, kinds: rows.map { PosterSize.kind(for: $0.style) },
                             cardScale: a.cardSize.scale, posterStrip: strip, bottomRoom: listBottomRoom(rows),
                             edgeBand: listEdgeBand(rows))
    }

    /// Wave F-k: band above the hero list for the lift of its tallest tile (card size, quality strip below posters).
    private func listEdgeBand(_ rows: [HomeRow]) -> CGFloat {
        let a = model.profile.appearance
        let strip = a.titles.posterBadges == .bottom ? PosterQualityBadges.bandHeight : 0
        let kinds = rows.map { PosterSize.kind(for: $0.style) }
        return Theme.Focus.listEdgeBand(height: FocusHeadroom.tallest(kinds, cardScale: a.cardSize.scale, posterExtra: strip))
    }

    /// tvOS bottom safe area (the list ended there before wave F-m).
    private static let bottomSafeArea: CGFloat = 60

    /// Wave F-m: room below the home list for the lift of its tallest tile (same tile heights as `listEdgeBand`).
    private func listBottomRoom(_ rows: [HomeRow]) -> CGFloat {
        let a = model.profile.appearance
        let strip = a.titles.posterBadges == .bottom ? PosterQualityBadges.bandHeight : 0
        let kinds = rows.map { PosterSize.kind(for: $0.style) }
        return Theme.Focus.listBottomRoom(height: FocusHeadroom.tallest(kinds, cardScale: a.cardSize.scale, posterExtra: strip))
    }

    /// Build 2 device test: focus scrolling only keeps the focused card's frame inside the list, so a row entered
    /// from above (hero buttons, tab bar) ended with its heading above the list's top edge, in the faded band.
    /// When focus enters a row, the row (heading included) scrolls to the list's top edge like in the Apple TV app.
    /// Queued after the focus update so this scroll replaces the system's focus scroll instead of racing it.
    private func showHeading(of row: HomeRow) {
        guard let scroll = topWatch.scrollToRow else { return }
        let id = row.id
        // S5: a hand-over inside the row (placeholder → card) calls this again: the checks restart, no second line.
        let restart = headingRow == id
        if !restart { headingRow = id }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.25)) { scroll(id) }
        }
        let title = model.homeRowTitle(row.content)
        if !restart { RemoteLog.info("nav", "Reihe fokussiert, Überschrift nach oben: \(title)") }
        // Build 3 device test: the row stopped too low (heading visible, posters cut at the bottom); the system's
        // focus scroll finished after ours. S5 (Build 4 follow-up): one blind re-snap at 400 ms was not enough on
        // first entry (hand-overs, slow first decodes). While focus stays in the row it is checked at 0.4, 0.9 and
        // 1.5 s and snapped again only when its top is off the list's top edge (`HeadingSnap`).
        let watch = topWatch
        watch.headingChecks?.cancel()
        watch.headingChecks = Task { @MainActor in
            let start = ContinuousClock.now
            let checks = HeadingSnap.checksMs
            for (i, at) in checks.enumerated() {
                try? await Task.sleep(until: start + Duration.milliseconds(at), clock: ContinuousClock())
                guard !Task.isCancelled, headingRow == id else { return }
                let before = watch.headingSample(row: id)
                let decision = HeadingSnap.decide(row: before.row, scroll: before.scroll)
                guard HeadingSnap.shouldSnap(decision, check: i) else {
                    if i == checks.count - 1 {
                        RemoteLog.info("nav", HeadingSnap.checkLine(title: title, ms: at, decision: decision, sample: before))
                    }
                    continue
                }
                withAnimation(.easeOut(duration: 0.2)) { scroll(id) }
                try? await Task.sleep(for: .milliseconds(HeadingSnap.afterSnapMs))
                guard !Task.isCancelled else { return }
                RemoteLog.info("nav", HeadingSnap.snapLine(title: title, ms: at, before: before,
                                                           after: watch.headingSample(row: id)))
            }
        }
    }

    @ViewBuilder private func rowList(_ rows: [HomeRow], hero: Bool) -> some View {
        let layout = model.profile.home
        let firstRow = rows.first?.id
        let space = HomeTopEdgeWatch.contentSpace
        let watch = topWatch
        ForEach(rows) { row in
            HomeRowView(row: row, onActivate: { $0 }, focusTarget: focusTarget, menu: HomeRowMenu(
                canMoveUp: (layout.index(of: row.id) ?? 0) > 0,
                edit: { manager = ManagerTarget(row: row.id) },
                moveToTop: { quick { $0.moveToTop(row.id) } },
                hide: { hideCandidate = row },
                delete: { deleteCandidate = row }),
                onFocusInside: { inside in
                    if row.id == firstRow { topWatch.report(.firstRow, inside) }
                    if hero { focus.row(row.id, focused: inside) }   // F-A-12
                    if inside { focusedRows.insert(row.id) } else { focusedRows.remove(row.id) }
                    // Without a hero the first row is the top edge: `TopEdgeScroll` snaps the page to the very top.
                    if inside, hero || row.id != firstRow { showHeading(of: row) }
                    if !inside, headingRow == row.id { headingRow = nil }
                })
            // S5: the row's frame in the list content (the scroll target of `scrollToRow`); changes only with the
            // layout, not per scroll frame, and is stored without a re-render.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { watch.setRowFrame(row.id, $0) }
        }
        if layout.rows.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Deine Startseite ist leer. Füge Reihen aus Addons, Collections oder dem Fusion-Kit hinzu.")
                    .textRole(.rowDetail)
                    .multilineTextAlignment(.leading)
                FocusReportingButton(title: "Reihen hinzufügen", action: { manager = ManagerTarget(openBrowser: true) },
                                     onFocus: { topWatch.report(.actionButton, $0) }, focusTarget: focusTarget)
            }
            .padding(.leading, Theme.Space.edge)
        } else {
            // Keine Akzentfarbe (RootView .tint) auf der Startseite; Welle F-i: Token-Knopf wie Abspielen/Details.
            // P2: below the rows the hero info stays collapsed (`HeroCollapse.belowRows`).
            FocusReportingButton(title: "Reihen & Collections", action: { manager = ManagerTarget() },
                                 onFocus: { f in
                                     topWatch.report(.actionButton, f)
                                     if hero, collapse.belowRows != f { collapse.belowRows = f }
                                 }, focusTarget: focusTarget)
                .padding(.top, 20)
                .padding(.leading, Theme.Space.edge)
        }
    }

    /// Task 4.1a (F-A-11): without a hero nobody claimed the first focus after a cold start, so the sidebar kept
    /// it. Same rule as `HeroButtons.claimLaunchFocus`: the first row (remembered or first tile, else placeholder 0;
    /// empty page: the action button) takes it back until a row held it 300 ms or the launch window is over.
    private func claimLaunchFocusWithoutHero(_ rows: [HomeRow]) async {
        guard !LaunchFocus.done else { return }
        let deadline = LaunchFocus.deadline ?? ContinuousClock.now + LaunchFocus.window
        LaunchFocus.deadline = deadline
        if LaunchFocus.shownAt == nil { LaunchFocus.shownAt = ContinuousClock.now }
        let target: HomeManager.Focus = rows.first.map { .row($0.id) } ?? .add
        var heldSince: ContinuousClock.Instant?
        while !Task.isCancelled, !LaunchFocus.done, ContinuousClock.now < deadline {
            if focusedRows.isEmpty {
                heldSince = nil
                if !focusTarget.isPending { focusTarget.request(target) }
            } else {
                let since = heldSince ?? ContinuousClock.now
                heldSince = since
                if ContinuousClock.now - since >= LaunchFocus.hold {
                    LaunchFocus.finish("Reihe hält den Fokus (ohne Hero)", way: "reihen", usableAt: since); return
                }
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        if !LaunchFocus.done, ContinuousClock.now >= deadline {
            LaunchFocus.finish("Startfenster vorbei (ohne Hero)", way: "fenster", usableAt: LaunchFocus.shownAt ?? ContinuousClock.now)
        }
    }

    /// Kontextmenü-Aktion über dieselbe Logik wie der Verwalter; speichert und loggt nur mit Wirkung.
    /// Task 4.1a (F-A-3): the outcome's focus target is applied too (hide/delete: the row moving up, else the
    /// action button; "Ganz nach oben": the moved row, scrolled to). The confirmations run this in `onDismiss`,
    /// after the system put the focus back on the tile, so the request wins over the vanished tile.
    private func quick(_ action: (inout HomeManager) -> HomeManager.Outcome) {
        var m = HomeManager(layout: model.profile.home, hidden: model.profile.hiddenRows)
        let outcome = action(&m)
        guard let e = outcome.event else { return }
        let layout = m.layout, hidden = m.hidden
        model.update { $0.home = layout; $0.hiddenRows = hidden }
        RemoteLog.info("home", e.logText(title: model.homeRowTitle(e.row.content)) + " (Kontextmenü)")
        let shown = layout.rowsBelowHero(model.profile.appearance).map(\.id)
        let target = HomeManager.homeTarget(outcome.focus, rows: layout.rows.map(\.id), shown: shown)
        focusTarget.request(target)
        let name = focusTarget.logName(target) { id in
            layout.rows.first { $0.id == id }.map { model.homeRowTitle($0.content) } ?? "?"
        }
        RemoteLog.info("fokus", "Kontextmenü: Ziel \(name)")
        if case .row(let id) = target, let scroll = topWatch.scrollToRow {
            // The row may sit outside the built part of the lazy list (moved to the top): scroll there first.
            DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.25)) { scroll(id) } }
        }
    }
}

/// Wave F-j: vertical home scroll view reports its distance from the very top and can scroll there.
private struct TopEdgeScroll: ViewModifier {
    let watch: HomeTopEdgeWatch
    let proxy: ScrollViewProxy

    func body(content: Content) -> some View {
        content
            // S5: offset from the very top plus the largest offset (heading check); the bar logic reads the offset.
            .onScrollGeometryChange(for: HomeListScroll.self, of: { g in
                HomeListScroll(contentOffsetY: Double(g.contentOffset.y), contentHeight: Double(g.contentSize.height),
                               insetTop: Double(g.contentInsets.top), insetBottom: Double(g.contentInsets.bottom),
                               viewportHeight: Double(g.containerSize.height))
            }) { _, v in
                watch.setScroll(v)
            }
            .onAppear {
                watch.scrollToTop = { proxy.scrollTo(HomeTopEdgeWatch.topID, anchor: .top) }
                watch.scrollToRow = { proxy.scrollTo($0, anchor: .top) }
            }
    }
}

/// Action button of the home page that reports its focus (wave F-j: top edge of a page without rows).
private struct FocusReportingButton: View {
    let title: LocalizedStringKey
    let action: () -> Void
    let onFocus: (Bool) -> Void
    /// Task 4.1a (F-A-3): claims a pending `.add` target (last row hidden or deleted).
    var focusTarget: HomeFocusTarget? = nil
    @FocusState private var focused: Bool

    var body: some View {
        Button(title, action: action)
            .buttonStyle(ThemeActionButtonStyle())
            .focused($focused)
            .onChange(of: focused) { _, f in onFocus(f) }
            .onDisappear { onFocus(false) }
            .onChange(of: focusTarget?.serial, initial: true) { _, _ in
                guard focusTarget?.claim(.add) == true else { return }
                DispatchQueue.main.async { focused = true }
            }
    }
}

/// Task 4.1a (F-A-3): pending focus target of the home page after a context-menu action. The row (or the action
/// button) it names claims it once: on the change, or when the lazy list builds it after the scroll.
@MainActor @Observable final class HomeFocusTarget {
    private(set) var pending: HomeManager.Focus?
    /// Increases with every request, so the same target twice still fires `onChange`.
    private(set) var serial = 0
    /// Review I1: a target that nobody claimed in time expires, so a row built minutes later (scrolled to, or
    /// back from a detail page) does not pull the focus, and the F-A-11 launch claim is not blocked.
    @ObservationIgnored private var pendingUntil: ContinuousClock.Instant?
    static let lifetime: Duration = .seconds(2)

    func request(_ f: HomeManager.Focus) {
        pending = f
        pendingUntil = ContinuousClock.now + Self.lifetime
        serial += 1
    }

    /// A target is pending and not expired yet (an expired one is dropped here).
    var isPending: Bool {
        guard pending != nil else { return false }
        if let until = pendingUntil, ContinuousClock.now >= until { drop("verfallen"); return false }
        return true
    }

    /// True once for the view that matches the pending, unexpired target.
    func claim(_ f: HomeManager.Focus) -> Bool {
        guard isPending, pending == f else { return false }
        pending = nil
        pendingUntil = nil
        return true
    }

    /// Clears a target nobody claimed (expired, or the home page went away).
    func drop(_ reason: String) {
        guard let p = pending else { return }
        pending = nil
        pendingUntil = nil
        RemoteLog.info("fokus", "Ziel \(reason) (\(logName(p) { _ in "Reihe" }))")
    }

    func logName(_ f: HomeManager.Focus, title: (UUID) -> String) -> String {
        switch f {
        case .row(let id): "Reihe \(title(id))"
        case .add, .hidden: "Knopf unten"
        }
    }
}

/// Ziel der Verwalter-Navigation von der Startseite.
private struct ManagerTarget: Identifiable, Hashable {
    let id = UUID()
    var row: UUID? = nil
    var openBrowser = false
}
