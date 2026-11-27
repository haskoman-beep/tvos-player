import SwiftUI
import PlayerCore

/// Welle F-b2: Hinzufügen-Browser (Plan §2.5, Ebene 2) auf der `CategoryList` (F-0) mit den Gruppen aus `RowCatalog`.
/// Links die Quellen mit Anzahl, rechts die Einträge. OK hängt eine Reihe **unten** an (Häkchen „auf der Startseite“),
/// nochmal OK nimmt eine eben hinzugefügte zurück; schon vorher vorhandene Reihen nimmt OK erst nach Rückfrage weg.
/// Kopf: „Suchen“ öffnet eine eigene Suchseite (Rückfallweg §6.4 statt `.searchable` in der Spalte).
/// Menu links schließt; der Verwalter fokussiert dann die oberste neue Reihe.
/// Task 4.1a (F-A-6): a browser section with a stable key (title, numbered when it repeats; untitled: "-").
struct KeyedRowSection {
    let key: String
    let section: RowCatalogSection
    var title: String? { section.title }
    var entries: [RowCatalogEntry] { section.entries }
}

struct AddRowBrowser: View {
    let session: HomeRowsSession
    @Environment(AppModel.self) var model
    @ObservedObject private var kit = FusionKitStore.shared
    @Environment(\.dismiss) private var dismiss

    /// Linke Spalte: Gruppen aus dem Katalog plus „Importieren (Handy)“.
    enum Item: Hashable {
        case group(String)
        case phoneImport
    }

    @State private var selected: Item
    @State private var hideCandidate: HomeRow?
    @State private var showSearch = false
    @FocusState private var entryFocus: String?

    init(session: HomeRowsSession) {
        self.session = session
        _selected = State(initialValue: Self.initialItem(session.catalog()))
    }

    var body: some View {
        let catalog = session.catalog()
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Reihe hinzufügen").textRole(.pageTitle)
            list(catalog)
            Text("OK: hinzufügen (erscheint unten) · nochmal OK: wieder entfernen · Menu: fertig")
                .textRole(.rowDetail)
        }
        .padding(.horizontal, Theme.Space.edge)
        .padding(.vertical, Theme.Space.edgeVertical)
        .settingsSurface()
        .task { await kit.refresh(all: true) }
        .navigationDestination(isPresented: $showSearch) { AddRowSearch(session: session) }
        .hideConfirmation($hideCandidate, session: session)
    }

    private func list(_ catalog: RowCatalog) -> some View {
        CategoryList(items: catalog.groups.map { Item.group($0.id) } + [.phoneImport], selected: $selected,
                     entry: { entry($0, catalog) }, onExit: { dismiss() },
                     header: {
                         SettingsRow(symbol: "magnifyingglass", tint: Theme.CategoryTint.home.color, title: "Suchen",
                                     detail: "In allen Quellen", accessory: .chevron, reserveDetailSpace: false) {
                             showSearch = true
                         }
                     },
                     content: { item in content(item, catalog) })
    }

    /// Start auf „Meine Collections“, wenn dort etwas frei ist (Abnahme §6.3: neue Collection in ≤ 4 Drücken),
    /// sonst auf der ersten Gruppe mit freiem Eintrag.
    static func initialItem(_ catalog: RowCatalog) -> Item {
        let free = catalog.groups.filter { g in g.entries.contains { $0.status == .available } }
        let pick = free.first { $0.kind == .collections } ?? free.first ?? catalog.groups.first
        return pick.map { .group($0.id) } ?? .phoneImport
    }

    private func entry(_ item: Item, _ catalog: RowCatalog) -> CategoryEntry {
        switch item {
        case .phoneImport:
            return CategoryEntry(title: "Importieren (Handy)", symbol: "iphone", tint: Theme.CategoryTint.system.color)
        case .group(let id):
            guard let g = catalog.group(id) else { return CategoryEntry(title: id, symbol: "questionmark", tint: .gray) }
            return CategoryEntry(title: g.title, symbol: Self.symbol(g.kind), tint: Self.tint(g.kind), count: g.count)
        }
    }

    static func symbol(_ k: RowCatalogGroup.Kind) -> String {
        switch k {
        case .addon: "puzzlepiece.extension"
        case .collections: "square.grid.2x2"
        case .kit: "sparkles"
        case .trakt: "checkmark.seal"
        case .special: "star"
        case .packages: "shippingbox"
        }
    }

    static func tint(_ k: RowCatalogGroup.Kind) -> Color {
        switch k {
        case .addon: Theme.CategoryTint.addons.color
        case .collections, .packages: Theme.CategoryTint.home.color
        case .kit: Theme.CategoryTint.appearance.color
        case .trakt: .red
        case .special: Theme.CategoryTint.playback.color
        }
    }

    @ViewBuilder private func content(_ item: Item, _ catalog: RowCatalog) -> some View {
        switch item {
        case .phoneImport:
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                SettingsHeader(title: "Importieren", summary: "Nuvio-Export, Kit-Link oder TMDB-/Trakt-Liste am Handy einfügen")
                    .padding(.bottom, Theme.Space.m)
                NavigationLink { PhoneInputView(section: .quickImport) } label: {
                    SettingsRowLabel(symbol: "qrcode", tint: Theme.CategoryTint.system.color, title: "Am Handy importieren",
                                     detail: "Importierte Collections erscheinen danach unter „Meine Collections“.",
                                     accessory: .chevron, detailAlwaysVisible: true)
                }
                .buttonStyle(ThemeRowButtonStyle())
            }
        case .group(let id):
            if let g = catalog.group(id) { groupContent(g) }
        }
    }

    private func groupContent(_ g: RowCatalogGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: g.title, summary: groupSummary(g))
                .padding(.bottom, Theme.Space.m)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    if g.kind == .kit { kitHints(g) }
                    if g.entries.isEmpty {
                        Text(emptyText(g)).textRole(.rowDetail).multilineTextAlignment(.leading)
                    }
                    // Task 4.1a (F-A-6): sections keyed by title, not position; a kit file arriving later inserts
                    // sections before the focused one without changing that one's identity.
                    ForEach(Self.keyed(g.sections), id: \.key) { section in
                        if let t = section.title { SettingsSectionLabel(title: t) }
                        ForEach(section.entries) { e in
                            CatalogEntryRow(entry: e, isNew: isNew(e)) { toggle(e) }
                                .focused($entryFocus, equals: e.id)
                        }
                    }
                }
                .padding(.vertical, Theme.Space.s)
            }
            .scrollClipDisabled()
            // Entries scroll under the group title, never over it; the sides stay open for the focus zoom.
            .mask { Rectangle().padding(.horizontal, -Theme.Space.xl) }
        }
        .defaultFocus($entryFocus, g.firstAvailable?.id)
    }

    private func groupSummary(_ g: RowCatalogGroup) -> String {
        let on = g.entries.filter(\.isOnHome).count
        return DesignText.metaLine([g.count == 1 ? "1 Eintrag" : "\(g.count) Einträge",
                                    on > 0 ? "\(on) auf der Startseite" : nil])
    }

    private func emptyText(_ g: RowCatalogGroup) -> String {
        switch g.kind {
        case .collections: "Noch keine eigenen Collections. Unter „Importieren (Handy)“ oder „Fertige Pakete“ anlegen."
        case .kit: kit.listingLoading || !kit.loading.isEmpty ? "Fusion-Kit lädt …" : "Keine Kit-Reihen geladen."
        case .packages: "Alle fertigen Pakete sind schon angelegt."
        default: "Keine Einträge."
        }
    }

    /// E11: fehlender Schlüssel als ein Hinweis über der Liste, mit Weg zum Handy.
    @ViewBuilder private func kitHints(_ g: RowCatalogGroup) -> some View {
        if let hint = g.hint {
            NavigationLink { PhoneInputView(section: .keys) } label: {
                SettingsRowLabel(symbol: Theme.Tone.warn.symbol, tint: Theme.Tone.warn.color, title: hint,
                                 detail: "Am Handy eintragen", accessory: .chevron, detailAlwaysVisible: true,
                                 reserveDetailSpace: false)
            }
            .buttonStyle(ThemeRowButtonStyle())
        }
        if g.pendingSources > 0 {
            Text(g.pendingSources == 1 ? "1 Kit-Datei lädt noch …" : "\(g.pendingSources) Kit-Dateien laden noch …")
                .textRole(.rowDetail)
        }
        if let e = kit.listingError {
            Text("Kit-Katalog nicht erreichbar: \(e)").textRole(.rowDetail)
        }
        // Ladefehler je Kit-Datei, knapp (Review M4).
        ForEach(g.failures, id: \.self) { f in
            Label("Nicht geladen – \(f)", systemImage: Theme.Tone.warn.symbol)
                .textRole(.rowDetail)
                .lineLimit(2)
        }
    }

    private func isNew(_ e: RowCatalogEntry) -> Bool {
        session.manager.layout.row(withKey: e.id).map { session.manager.isNew($0.id) } ?? false
    }

    private func toggle(_ e: RowCatalogEntry) {
        switch session.toggle(e) {
        case .done: break
        case .confirmHide(let row): hideCandidate = row
        case .unavailable(let why): model.notice = why
        }
    }

    /// Task 4.1a (F-A-6): stable section keys; a repeated title gets its occurrence number.
    static func keyed(_ sections: [RowCatalogSection]) -> [KeyedRowSection] {
        var seen: [String: Int] = [:]
        return sections.map { sec in
            let base = sec.title ?? "-"
            let n = seen[base, default: 0]
            seen[base] = n + 1
            return KeyedRowSection(key: n == 0 ? base : "\(base)#\(n)", section: sec)
        }
    }
}

/// Suchseite des Browsers (Rückfallweg §6.4): `.searchable` über alle Quellen, Treffer mit Quelle im Untertitel.
private struct AddRowSearch: View {
    let session: HomeRowsSession
    @Environment(AppModel.self) var model
    @State private var query = ""
    @State private var hideCandidate: HomeRow?

    var body: some View {
        let hits = query.trimmingCharacters(in: .whitespaces).isEmpty ? [] : session.catalog().search(query)
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                if query.isEmpty {
                    Text("Name einer Liste, Collection oder Kit-Reihe eingeben.").textRole(.rowDetail)
                } else if hits.isEmpty {
                    Text("Nichts gefunden für „\(query)“.").textRole(.rowDetail)
                }
                ForEach(hits) { e in
                    CatalogEntryRow(entry: e, showSource: true,
                                    isNew: session.manager.layout.row(withKey: e.id).map { session.manager.isNew($0.id) } ?? false) {
                        switch session.toggle(e) {
                        case .done: break
                        case .confirmHide(let row): hideCandidate = row
                        case .unavailable(let why): model.notice = why
                        }
                    }
                }
            }
            .frame(maxWidth: Theme.Layout.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, Theme.Space.edge)
            .padding(.vertical, Theme.Space.edgeVertical)
        }
        .settingsSurface()
        .searchable(text: $query, prompt: "Reihen suchen")
        .hideConfirmation($hideCandidate, session: session)
    }
}

/// Eintrag der rechten Spalte: Titel · Art bzw. „auf der Startseite (7)“ · Häkchen bzw. Plus.
private struct CatalogEntryRow: View {
    let entry: RowCatalogEntry
    var showSource = false
    var isNew = false
    let action: () -> Void

    private var symbol: String {
        switch entry.status {
        case .onHome: "checkmark"
        case .available: "plus"
        case .unavailable: "lock"
        }
    }

    private var tint: Color {
        switch entry.status {
        case .onHome: Theme.Tone.ok.color
        case .available: Theme.CategoryTint.home.color
        case .unavailable: .gray
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.m) {
                IconTile(symbol: symbol, color: tint)
                VStack(alignment: .leading, spacing: Theme.Space.xs / 2) {
                    Text(entry.title).textRoleInRow(.rowTitle).lineLimit(1)
                    Text(DesignText.metaLine([entry.statusText, showSource ? entry.source : nil]))
                        .textRoleInRow(.rowDetail).lineLimit(1)
                }
                Spacer(minLength: Theme.Space.m)
                if isNew { ThemeBadge(kind: .status(.ok, onImage: false), text: "neu") }
            }
        }
        .buttonStyle(ThemeRowButtonStyle(minHeight: Theme.Layout.categoryRowMinHeight))
        .accessibilityLabel(entry.title)
        .accessibilityValue(DesignText.accessibilityLabel([entry.statusText, isNew ? "neu" : nil]))
        .accessibilityHint(entry.isOnHome ? "Auswählen nimmt die Reihe von der Startseite." : "Auswählen fügt die Reihe unten an.")
    }
}

extension View {
    /// Rückfrage vor dem Ausblenden einer Reihe, die schon vor dieser Sitzung auf der Startseite lag (F-b1-Review M1).
    @MainActor func hideConfirmation(_ row: Binding<HomeRow?>, session: HomeRowsSession) -> some View {
        // Eigene Rückfrage (F-a SettingsConfirmationView): „Behalten“ oben mit sicherem Standardfokus (§2.4).
        settingsConfirmation(item: row, title: { "„\(session.title($0))“ ausblenden?" },
                             message: { _ in "Die Reihe verschwindet von der Startseite. Unter „Ausgeblendet“ lässt sie sich wieder einblenden." },
                             verb: "Ausblenden", symbol: "eye.slash") { r in
            _ = session.hide(r.id)
        }
    }
}
