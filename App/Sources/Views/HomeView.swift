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

    var body: some View {
        let layout = model.profile.home
        let appearance = model.profile.appearance
        let hero = layout.heroSource(appearance)
        let rows = layout.rowsBelowHero(appearance)
        let showsHero = hero != nil && !(slides.loaded && slides.items.isEmpty)
        let edge = HomeTopEdge.topmost(hasHero: showsHero, rowCount: rows.count, layoutEmpty: layout.rows.isEmpty)
        Group {
            if showsHero {
                heroHome(rows)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: Theme.Space.xl) { rowList(rows) }
                            .padding(.vertical, 40)
                            .id(HomeTopEdgeWatch.topID)
                    }
                    .modifier(TopEdgeScroll(watch: topWatch, proxy: proxy))
                }
            }
        }
        .environment(\.homeRowFocusMemory, rowFocus)
        .background { HomeTabBarRequest(watch: topWatch) }
        .onChange(of: "\(edge.rawValue)|\(appearance.navigation.rawValue)", initial: true) {
            topWatch.configure(edge: edge, navigation: appearance.navigation)
        }
        .onAppear {
            rowFocus.state.covered = false
            topWatch.start()
        }
        .onDisappear {
            rowFocus.state.covered = true
            topWatch.stop()
        }
        .task(id: hero.map { "\($0.id)|\($0.content.key)" } ?? "-") {
            guard let hero else { return }
            let items = await model.heroItems(for: hero)
            // Abgebrochene Ladung (Neuaufbau beim Start, Katalog -999) liefert []: nicht als „kein Hero“ werten,
            // sonst springt die Startseite kurz auf das Layout ohne Hero und die Knopfzeile verliert den Fokus.
            guard !Task.isCancelled else { return }
            slides.set(items)
            RemoteLog.info("hero", "\(slides.items.count) Folien")
        }
        // Welle F-f: alle Listen vorladen (oben zuerst, begrenzt); sichtbare Reihen laden zusätzlich sofort selbst.
        // Neue Reihen ändern den Schlüssel und laden damit gleich.
        .task(id: rows.map(\.content.key)) { await model.preloadHomeRows(rows) }
        .navigationDestination(item: $manager) { t in HomeManagerView(focusRow: t.row, openBrowser: t.openBrowser) }
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
                HeroLayer(slides: slides)
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: Theme.Space.xl) {
                        HeroButtons(slides: slides, onFocusChange: { topWatch.report(.heroButtons, $0) })
                        rowList(rows)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 60)
                    .id(HomeTopEdgeWatch.topID)
                }
                .modifier(TopEdgeScroll(watch: topWatch, proxy: proxy))
                .environment(\.heroBackdropShared, true)
                // Weicher Rand oben, damit hochgescrollte Reihen nicht hart an der Info abreißen.
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 24)
                        Color.black
                    }
                }
                .padding(.top, HeroMetrics.listTop)
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .environment(focus)
    }

    @ViewBuilder private func rowList(_ rows: [HomeRow]) -> some View {
        let layout = model.profile.home
        let firstRow = rows.first?.id
        ForEach(rows) { row in
            HomeRowView(row: row, onActivate: { $0 }, menu: HomeRowMenu(
                canMoveUp: (layout.index(of: row.id) ?? 0) > 0,
                edit: { manager = ManagerTarget(row: row.id) },
                moveToTop: { quick { $0.moveToTop(row.id) } },
                hide: { hideCandidate = row },
                delete: { deleteCandidate = row }),
                onFocusInside: row.id == firstRow ? { topWatch.report(.firstRow, $0) } : nil)
        }
        if layout.rows.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Deine Startseite ist leer. Füge Reihen aus Addons, Collections oder dem Fusion-Kit hinzu.")
                    .textRole(.rowDetail)
                    .multilineTextAlignment(.leading)
                FocusReportingButton(title: "Reihen hinzufügen", action: { manager = ManagerTarget(openBrowser: true) },
                                     onFocus: { topWatch.report(.actionButton, $0) })
            }
            .padding(.leading, Theme.Space.edge)
        } else {
            // Keine Akzentfarbe (RootView .tint) auf der Startseite; Welle F-i: Token-Knopf wie Abspielen/Details.
            FocusReportingButton(title: "Reihen & Collections", action: { manager = ManagerTarget() },
                                 onFocus: { topWatch.report(.actionButton, $0) })
                .padding(.top, 20)
                .padding(.leading, Theme.Space.edge)
        }
    }

    /// Kontextmenü-Aktion über dieselbe Logik wie der Verwalter; speichert und loggt nur mit Wirkung.
    private func quick(_ action: (inout HomeManager) -> HomeManager.Outcome) {
        var m = HomeManager(layout: model.profile.home, hidden: model.profile.hiddenRows)
        guard let e = action(&m).event else { return }
        let layout = m.layout, hidden = m.hidden
        model.update { $0.home = layout; $0.hiddenRows = hidden }
        RemoteLog.info("home", e.logText(title: model.homeRowTitle(e.row.content)) + " (Kontextmenü)")
    }
}

/// Wave F-j: vertical home scroll view reports its distance from the very top and can scroll there.
private struct TopEdgeScroll: ViewModifier {
    let watch: HomeTopEdgeWatch
    let proxy: ScrollViewProxy

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Double.self, of: { Double($0.contentOffset.y + $0.contentInsets.top) }) { _, v in
                watch.setOffset(v)
            }
            .onAppear { watch.scrollToTop = { proxy.scrollTo(HomeTopEdgeWatch.topID, anchor: .top) } }
    }
}

/// Action button of the home page that reports its focus (wave F-j: top edge of a page without rows).
private struct FocusReportingButton: View {
    let title: LocalizedStringKey
    let action: () -> Void
    let onFocus: (Bool) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(title, action: action)
            .buttonStyle(ThemeActionButtonStyle())
            .focused($focused)
            .onChange(of: focused) { _, f in onFocus(f) }
            .onDisappear { onFocus(false) }
    }
}

/// Ziel der Verwalter-Navigation von der Startseite.
private struct ManagerTarget: Identifiable, Hashable {
    let id = UUID()
    var row: UUID? = nil
    var openBrowser = false
}
