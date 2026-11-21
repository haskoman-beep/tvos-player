import SwiftUI
import PlayerCore

/// Startseite. Langer Druck auf eine Kachel → Bearbeiten-Modus mit dieser Reihe angefasst (Spec §2).
/// Mit Hero (Spec §7a.1): hinten Hintergrund + Info des angezeigten Titels, darüber der ScrollView mit
/// Knopfzeile und Reihen. Angezeigt wird die Diashow-Folie oder, solange der Fokus in den Reihen liegt, die Kachel.
struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var editor: HomeEditor?
    @State private var cursor = 0
    @State private var longPressFired = false
    @State private var focus = HomeFocus()
    @State private var slides = HeroSlides()
    /// Welle C-b (#19): Fokus-Gedächtnis je Reihe; verdeckt, solange eine andere Seite darüber liegt.
    @State private var rowFocus = HomeRowFocusMemory()

    var body: some View {
        if editor != nil {
            HomeEditView(editor: Binding(get: { editor! }, set: { editor = $0 }), cursor: $cursor) { result in
                if let result { model.update { $0.home = result } }
                editor = nil
            }
        } else {
            let layout = model.profile.home
            let appearance = model.profile.appearance
            let hero = layout.heroSource(appearance)
            let rows = layout.rowsBelowHero(appearance)
            Group {
                if hero != nil && !(slides.loaded && slides.items.isEmpty) {
                    heroHome(rows)
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 56) { rowList(rows) }
                            .padding(.vertical, 40)
                    }
                }
            }
            .environment(\.homeRowFocusMemory, rowFocus)
            .onAppear { rowFocus.state.covered = false }
            .onDisappear { rowFocus.state.covered = true }
            .task(id: hero.map { "\($0.id)|\($0.content.key)" } ?? "-") {
                guard let hero else { return }
                let items = await model.heroItems(for: hero)
                // Abgebrochene Ladung (Neuaufbau beim Start, Katalog -999) liefert []: nicht als „kein Hero“ werten,
                // sonst springt die Startseite kurz auf das Layout ohne Hero und die Knopfzeile verliert den Fokus.
                guard !Task.isCancelled else { return }
                slides.set(items)
                RemoteLog.info("hero", "\(slides.items.count) Folien")
            }
        }
    }

    /// Hintergrund- und Info-Ebene hinter dem ScrollView; der Hero ist kein eigener Scroll-Abschnitt.
    private func heroHome(_ rows: [HomeRow]) -> some View {
        ZStack(alignment: .topLeading) {
            HeroLayer(slides: slides)
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 56) {
                    HeroButtons(slides: slides)
                    rowList(rows)
                }
                .padding(.top, 24)
                .padding(.bottom, 60)
            }
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
        .environment(focus)
    }

    @ViewBuilder private func rowList(_ rows: [HomeRow]) -> some View {
        ForEach(rows) { row in
            HomeRowView(row: row, onActivate: { route in
                if longPressFired { longPressFired = false; return nil }
                return route
            }, onLongPress: { startEditing(row.id) })
        }
        if model.profile.home.rows.isEmpty {
            Text("Noch keine Reihen. Collections importieren (Einstellungen) und dann hier bearbeiten.")
                .foregroundStyle(.secondary)
        }
        Button("Startseite bearbeiten") { startEditing(nil) }
            // Keine Akzentfarbe (RootView .tint) auf der Startseite: normaler tvOS-Knopf wie Abspielen/Details.
            .tint(Color?.none)
            .padding(.top, 20)
    }

    private func startEditing(_ id: UUID?) {
        longPressFired = id != nil
        let layout = model.profile.home
        editor = HomeEditor(layout: layout, grabbing: id)
        cursor = id.flatMap { i in layout.rows.firstIndex { $0.id == i } } ?? 0
    }
}

/// Bearbeiten-Modus: ein einziger fokussierbarer Knopf fängt alle Fernbedienungs-Befehle ab.
/// ▲▼ verschiebt die angefasste Reihe (oder bewegt die Auswahl), ◀▶ wechselt den Stil,
/// Play/Pause nimmt sie von der Startseite, OK fertig, Zurück verwirft.
struct HomeEditView: View {
    @EnvironmentObject var model: AppModel
    @Binding var editor: HomeEditor
    @Binding var cursor: Int
    let finish: (HomeLayout?) -> Void
    @State private var showAdd = false
    @FocusState private var focused: Bool

    private var rows: [HomeRow] { editor.layout.rows }

    var body: some View {
        ScrollViewReader { proxy in
            Button {
                ok()
            } label: {
                VStack(alignment: .leading, spacing: 30) {
                    Text(editor.grabbed == nil ? "▲▼ auswählen · OK anfassen · Zurück verwerfen"
                                               : "▲▼ verschieben · ◀▶ Stil · ⏯ entfernen · OK fertig · Zurück verwerfen")
                        .font(.headline).foregroundStyle(.secondary)
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 36) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                                HomeRowView(row: row, onActivate: { _ in nil }, onLongPress: {}, interactive: false)
                                    .padding(.vertical, 12)
                                    .overlay(alignment: .topTrailing) {
                                        if row.id == editor.grabbed {
                                            Text("◀ \(row.style.displayName) ▶").font(.headline)
                                                .padding(10).background(.yellow, in: Capsule()).foregroundStyle(.black)
                                        }
                                    }
                                    .background(
                                        RoundedRectangle(cornerRadius: 24)
                                            .stroke(row.id == editor.grabbed ? Color.yellow : (i == cursor ? Color.white : .clear), lineWidth: 6)
                                    )
                                    .scaleEffect(row.id == editor.grabbed ? 0.97 : 1)
                                    .id(row.id)
                            }
                            PlusTile(highlighted: cursor == rows.count).id("plus")
                        }
                        .padding(30)
                    }
                }
            }
            .buttonStyle(EditContainerStyle())
            .focused($focused)
            .onAppear { focused = true }
            .onMoveCommand { dir in
                switch dir {
                case .up:
                    if editor.grabbed != nil { editor.moveUp() } else { cursor = max(0, cursor - 1) }
                case .down:
                    if editor.grabbed != nil { editor.moveDown() } else { cursor = min(rows.count, cursor + 1) }
                case .left: editor.previousStyle()
                case .right: editor.nextStyle()
                @unknown default: break
                }
                if let g = editor.grabbed, let i = rows.firstIndex(where: { $0.id == g }) { cursor = i }
                withAnimation(.easeInOut(duration: 0.2)) {
                    if cursor < rows.count { proxy.scrollTo(rows[cursor].id, anchor: .center) } else { proxy.scrollTo("plus", anchor: .center) }
                }
            }
            .onPlayPauseCommand {
                withAnimation { editor.removeGrabbed() }
                cursor = min(cursor, rows.count)
            }
            .onExitCommand { finish(nil) }
            .sheet(isPresented: $showAdd) {
                AddRowSheet(options: editor.availableToAdd(collections: model.profile.collections,
                                                           extraLists: [.continueWatching, .watchlist, .upcoming] + addonCatalogs)) { content in
                    showAdd = false
                    if let content {
                        editor.add(content)
                        cursor = rows.count - 1
                    }
                    focused = true
                }
                .environmentObject(model)
            }
        }
    }

    private var addonCatalogs: [CatalogSource] {
        model.profile.addons.flatMap { a in
            a.manifest.catalogs.map { c in
                CatalogSource(id: "addon:\(a.manifest.id):\(c.type):\(c.id)", title: "\(c.name ?? c.id) (\(a.manifest.name))",
                              kind: .addon(addonId: a.manifest.id, catalogId: c.id, type: c.type),
                              mediaType: c.type == "series" ? .series : .movie)
            }
        }
    }

    private func ok() {
        if cursor >= rows.count { showAdd = true; return }
        if editor.grabbed == rows[cursor].id { finish(editor.commit()) } else { editor.grab(rows[cursor].id) }
    }
}

struct EditContainerStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

struct PlusTile: View {
    let highlighted: Bool
    var body: some View {
        HStack {
            Image(systemName: "plus.circle.fill").font(.system(size: 60))
            Text("Reihe hinzufügen").font(.title3)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .background(RoundedRectangle(cornerRadius: 24).fill(.white.opacity(highlighted ? 0.25 : 0.08)))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(highlighted ? .white : .clear, lineWidth: 6))
    }
}

/// Plus-Auswahl: alles, was nicht auf der Startseite liegt; unten "Neue Collection importieren".
struct AddRowSheet: View {
    @EnvironmentObject var model: AppModel
    let options: [RowContent]
    let done: (RowContent?) -> Void
    @State private var importURL = ""
    @State private var tmdbLink = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Hinzufügen") {
                    if options.isEmpty { Text("Alles ist schon auf der Startseite.").foregroundStyle(.secondary) }
                    ForEach(options, id: \.key) { o in
                        Button { done(o) } label: {
                            HStack {
                                Text(title(o))
                                Spacer()
                                Text(subtitle(o)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Fertige Pakete") {
                    ForEach(ReadyPackages.all.filter { pkg in !options.contains(.collection(id: pkg.id)) && model.collection(pkg.id) == nil }) { pkg in
                        Button { model.addCollection(pkg); done(.collection(id: pkg.id)) } label: {
                            HStack { Text(pkg.title); Spacer(); Text("\(pkg.folders.count) Ordner").foregroundStyle(.secondary) }
                        }
                    }
                }
                Section("TMDB- oder Trakt-Liste, Filmreihe, Studio") {
                    TextField("Link, z. B. themoviedb.org/list/… oder trakt.tv/users/…/lists/…", text: $tmdbLink)
                    Button("Als Reihe hinzufügen") {
                        if let s = TMDBLink.source(from: tmdbLink) ?? TraktLink.source(from: tmdbLink) { done(.list(s)) } else { model.lastError = "Link nicht erkannt: \(tmdbLink)" }
                    }
                    .disabled(tmdbLink.isEmpty)
                }
                Section("Neue Collection importieren") {
                    TextField("Nuvio-Export-URL (JSON)", text: $importURL)
                    Button("Importieren") { Task { await model.importNuvio(from: importURL); importURL = "" } }
                        .disabled(importURL.isEmpty)
                    Text("Trakt- und MDBList-Listen folgen (brauchen Konto/Key).").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Reihe hinzufügen")
        }
        .onExitCommand { done(nil) }
    }

    private func title(_ o: RowContent) -> String {
        switch o {
        case .list(let s): s.title
        case .collection(let id): model.collection(id)?.title ?? id
        }
    }

    private func subtitle(_ o: RowContent) -> String {
        switch o {
        case .list: "Liste"
        case .collection(let id): "Collection · \(model.collection(id)?.folders.count ?? 0) Ordner"
        }
    }
}
