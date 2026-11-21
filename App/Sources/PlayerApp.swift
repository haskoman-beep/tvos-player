import SwiftUI
import PlayerCore

@main
struct PlayerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).task { await model.syncRemoteProgress() }
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

    var nextRequest: PlayRequest? {
        guard let s = season, let e = episode, let n = EpisodeRef.next(after: s, e, in: episodes),
              let base = id.split(separator: ":").first else { return nil }
        return PlayRequest(type: type, id: "\(base):\(n.season):\(n.episode)", title: "\(item.name) S\(n.season)E\(n.episode)",
                           item: item, season: n.season, episode: n.episode, episodes: episodes)
    }
}

/// Tabs der Hauptnavigation.
enum AppTab: Hashable { case home, search, library, calendar, settings }

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
        } message: { Text(model.lastError ?? "") }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            Tab("Start", systemImage: "house", value: AppTab.home) {
                stack($path) { HomeView() }
            }
            Tab("Suche", systemImage: "magnifyingglass", value: AppTab.search) {
                stack($searchPath) { SearchView() }
            }
            Tab("Bibliothek", systemImage: "books.vertical", value: AppTab.library) {
                stack($libraryPath) { LibraryView() }
            }
            Tab("Kalender", systemImage: "calendar", value: AppTab.calendar) {
                stack($calendarPath) { CalendarView() }
            }
            Tab("Einstellungen", systemImage: "gearshape", value: AppTab.settings) {
                stack($settingsPath) { SettingsView(selected: $settingsCategory) }
            }
        }
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
    private func stack<V: View>(_ p: Binding<NavigationPath>, @ViewBuilder root: () -> V) -> some View {
        let r = root()
        let push: (Route) -> Void = { route in
            RemoteLog.info("nav", "→ \(route.logName)")
            p.wrappedValue.append(route)
        }
        return NavigationStack(path: p) {
            r.navigationDestination(for: Route.self) { RouteView(route: $0).environment(\.navigate, push) }
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
