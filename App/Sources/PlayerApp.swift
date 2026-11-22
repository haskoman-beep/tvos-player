import SwiftUI
import PlayerCore

@main
struct PlayerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).task { DiskCacheProxy.cleanupAtLaunch(); MainThreadWatchdog.apply(); await model.syncRemoteProgress() }
        }
    }
}

/// Ziel einer Navigation.
enum Route: Hashable {
    case detail(MetaPreview)
    case folder(Folder)
    case collection(String)
    case streams(PlayRequest)
    case person(id: Int, name: String)

    /// Kurzname fürs Log.
    var logName: String {
        switch self {
        case .detail(let m): "detail \(m.name)"
        case .folder(let f): "folder \(f.title)"
        case .collection(let id): "collection \(id)"
        case .streams(let r): "streams \(r.title)"
        case .person(let id, let name): "person \(id) \(name)"
        }
    }
}

/// Was abgespielt werden soll: Stremio-ID ("tt…" oder "tt…:S:E") plus Anzeige-Eintrag für Weiterschauen.
struct PlayRequest: Hashable {
    var type: String
    var id: String
    var title: String
    var item: MetaPreview
    var season: Int?
    var episode: Int?
    /// Alle Folgen der Serie (für die nächste Folge).
    var episodes: [EpisodeRef] = []
    /// Erwartete Laufzeit in Minuten (für die Platzhalter-Erkennung), falls bekannt.
    var runtimeMinutes: Double? = nil
    /// Aus Weiterschauen: zuletzt gespielte Quelle ohne Auswahl starten.
    var resumeLastSource = false
    /// Welle G-a: „Sofort abspielen“ – diese Quelle (Beste Wahl der Detailseite) ohne Auswahl starten.
    var bestChoice: LastSource? = nil

    var nextRequest: PlayRequest? {
        guard let s = season, let e = episode, let n = EpisodeRef.next(after: s, e, in: episodes),
              let base = id.split(separator: ":").first else { return nil }
        return PlayRequest(type: type, id: "\(base):\(n.season):\(n.episode)", title: "\(item.name) S\(n.season)E\(n.episode)",
                           item: item, season: n.season, episode: n.episode, episodes: episodes)
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab: AppTab = .home
    @State private var path = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @State private var calendarPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @State private var pickedProfile = false
    /// Gewählte Einstellungs-Kategorie; liegt hier, damit sie den Neuaufbau beim Wechsel der Navigationsart übersteht.
    @State private var settingsCategory: SettingsCategory = .profile
    /// Wurzel der Einstellungen sichtbar (keine NavigationLink-Unterseite offen): deren Unterseiten liegen nicht
    /// in `settingsPath`, darum zählt hier onAppear/onDisappear der Wurzel (Review F-c I2).
    @State private var settingsRootVisible = false

    var body: some View {
        Group {
            if model.hasMultipleProfiles && !pickedProfile {
                ProfilePickerView { pickedProfile = true }
            } else {
                styled(tabs)
                    .overlay(alignment: .topTrailing) {
                        ClockView().padding(.top, 40).padding(.trailing, 80)
                            .opacity(model.profile.appearance.navigation == .top ? 1 : 0)
                    }
                    .tint(model.profile.appearance.accent.color)
            }
        }
        .alert("Fehler", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK") { model.lastError = nil }
        } message: { Text(LogRedact.text(model.lastError ?? "")) }   // Schlüssel nie auf dem Bildschirm
    }

    private var tabs: some View {
        TabView(selection: tabSelection) {
            Tab("Start", systemImage: "house", value: AppTab.home) {
                stack($path, tab: .home) { HomeView() }
            }
            Tab("Suche", systemImage: "magnifyingglass", value: AppTab.search) {
                stack($searchPath, tab: .search) { SearchView() }
            }
            Tab("Bibliothek", systemImage: "books.vertical", value: AppTab.library) {
                stack($libraryPath, tab: .library) { LibraryView() }
            }
            Tab("Kalender", systemImage: "calendar", value: AppTab.calendar) {
                stack($calendarPath, tab: .calendar) { CalendarView() }
            }
            Tab("Einstellungen", systemImage: "gearshape", value: AppTab.settings) {
                // Menu-Kette der Einstellungen: Inhalt → aktive Kategorie (CategoryList) → Start-Tab (N2).
                stack($settingsPath, tab: .settings, rootHandlesMenu: false) {
                    SettingsView(selected: $settingsCategory) { toStartTab(from: .settings, level: "Kategorienspalte") }
                        .onAppear { settingsRootVisible = true }
                        .onDisappear { settingsRootVisible = false }
                }
            }
        }
        .onChange(of: tab) { old, new in RemoteLog.info("nav", "Tab \(old.logName) → \(new.logName)") }
        // Menu in der Tab-/Seitenleiste eines anderen Tabs als Start: erst zum Start-Tab (N2). Auf Start und mit
        // gepushten Seiten `nil`: dann gilt das System (Stack poppen bzw. App verlassen). Einstellungen: nur bei
        // sichtbarer Wurzel (Unterseiten sind NavigationLinks außerhalb des Pfads); die Kategorienspalte hat als
        // innerer Handler Vorrang.
        .onExitCommand(perform: tabBarExit)
        // Wave F-m: after every pop (any tab) the guard checks that the top bar still follows the visible page.
        .modifier(TabBarGuardHook(tab: tab, depth: depth(tab), navigation: model.profile.appearance.navigation))
    }

    private var tabBarExit: (() -> Void)? {
        let t = tab
        let d = t == .settings && !settingsRootVisible ? depth(t) + 1 : depth(t)
        guard MenuChain.handlesAtTabLevel(tab: t, depth: d) else { return nil }
        return { toStartTab(from: t, level: "Handler Leiste") }
    }

    /// Auswahl der TabView. Zweiter Druck auf den aktiven Tab (§3.3) poppt NICHT: SwiftUI bietet für `Tab`/
    /// `.sidebarAdaptable` keinen Rückruf für die erneute Wahl; ob der Setter dann mit gleichem Wert kommt, ist
    /// nicht zugesichert (auf tvOS wählt schon der Fokus einen Tab). Regel nach Plan §6.4 gestrichen, die
    /// Menu-Kette reicht. Die Log-Zeile zeigt am Gerät, ob und wann der Setter mit gleichem Wert kommt.
    private var tabSelection: Binding<AppTab> {
        Binding(get: { tab }, set: { new in
            if new == tab {
                RemoteLog.info("nav", "Tab \(new.logName) erneut gewählt (Tiefe \(depth(new)), kein Pop)")
            } else {
                tab = new
            }
        })
    }

    /// Gepushte Seiten im Pfad eines Tabs (ohne NavigationLink-/navigationDestination(item:)-Seiten).
    private func depth(_ t: AppTab) -> Int {
        switch t {
        case .home: path.count
        case .search: searchPath.count
        case .library: libraryPath.count
        case .calendar: calendarPath.count
        case .settings: settingsPath.count
        }
    }

    /// N2: Menu auf der Tab-Ebene eines anderen Tabs führt zum Start-Tab; erst dort verlässt Menu die App.
    private func toStartTab(from t: AppTab, level: String) {
        RemoteLog.info("nav", "Menu auf Tab-Ebene (\(t.logName), \(level)) → Start")
        tab = .home
    }

    /// Seitenleiste oder Standard-Leiste oben. SwiftUI hat keinen typgelöschten TabViewStyle, daher bleibt die
    /// Verzweigung: beim Umschalten baut sich die TabView neu auf. Tab-Auswahl, Pfade und Einstellungs-Kategorie
    /// liegen deshalb in RootView und überstehen das.
    @ViewBuilder private func styled<V: View>(_ v: V) -> some View {
        if model.profile.appearance.navigation == .sidebar {
            v.tabViewStyle(.sidebarAdaptable)
        } else {
            v
        }
    }

    /// Eigener Navigationspfad je Tab.
    /// `\.navigate` wird zusätzlich IN jeder Destination gesetzt: mit der Tab-API (`Tab {}` / `.sidebarAdaptable`)
    /// erreicht der außen am NavigationStack gesetzte Wert die gepushten Seiten nicht (dort galt der No-op-Standard,
    /// Abspielen/Ähnliche Titel auf der Detailseite taten nichts).
    /// `rootHandlesMenu`: Menu im Inhalt der Wurzelseite führt zum Start-Tab (N2, nur Tabs außer Start). Der
    /// Handler sitzt an der Wurzelseite und greift nicht in gepushten Seiten (eigene Hosting-Ebene, der Stack
    /// geht dort selbst zurück); innere Handler (Blätter, Spalten) haben Vorrang.
    private func stack<V: View>(_ p: Binding<NavigationPath>, tab t: AppTab, rootHandlesMenu: Bool = true,
                                @ViewBuilder root: () -> V) -> some View {
        let r = root()
        let push: (Route) -> Void = { route in
            RemoteLog.info("nav", "→ \(route.logName)")
            p.wrappedValue.append(route)
        }
        let exit: (() -> Void)? = rootHandlesMenu && MenuChain.target(.tabRoot, tab: t) == .startTab
            ? { toStartTab(from: t, level: "Handler Inhalt") } : nil
        return NavigationStack(path: p) {
            r.onExitCommand(perform: exit)
                .navigationDestination(for: Route.self) { RouteView(route: $0).environment(\.navigate, push) }
        }
        .environment(\.navigate, push)
    }
}

struct RouteView: View {
    let route: Route
    var body: some View {
        switch route {
        case .detail(let m): DetailView(item: m)
        case .folder(let f): FolderView(folder: f)
        case .collection(let id): CollectionView(collectionID: id)
        case .streams(let r): StreamListView(request: r)
        case .person(let id, let name): PersonView(personID: id, name: name)
        }
    }
}

struct ProfilePickerView: View {
    @EnvironmentObject var model: AppModel
    let done: () -> Void
    var body: some View {
        VStack(spacing: 60) {
            Text("Wer schaut?").font(.largeTitle.bold())
            HStack(spacing: 50) {
                ForEach(model.stored.profiles) { p in
                    Button {
                        model.switchProfile(p.id); done()
                    } label: {
                        VStack {
                            Text(String(p.name.prefix(1))).font(.system(size: 90, weight: .bold))
                                .frame(width: 220, height: 220).background(.blue.gradient, in: Circle())
                            Text(p.name).font(.title3)
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}
