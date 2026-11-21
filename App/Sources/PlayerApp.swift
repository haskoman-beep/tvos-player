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

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var path = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var pickedProfile = false

    var body: some View {
        Group {
            if model.hasMultipleProfiles && !pickedProfile {
                ProfilePickerView { pickedProfile = true }
            } else {
                TabView {
                    NavigationStack(path: $path) {
                        HomeView()
                            .navigationDestination(for: Route.self) { RouteView(route: $0) }
                    }
                    .environment(\.navigate, { path.append($0) })
                    .tabItem { Text("Start") }
                    NavigationStack(path: $searchPath) {
                        SearchView()
                            .navigationDestination(for: Route.self) { RouteView(route: $0) }
                    }
                    .environment(\.navigate, { searchPath.append($0) })
                    .tabItem { Text("Suche") }
                    NavigationStack(path: $settingsPath) {
                        SettingsView()
                            .navigationDestination(for: Route.self) { RouteView(route: $0) }
                    }
                    .environment(\.navigate, { settingsPath.append($0) })
                    .tabItem { Text("Einstellungen") }
                }
            }
        }
        .alert("Fehler", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK") { model.lastError = nil }
        } message: { Text(model.lastError ?? "") }
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
