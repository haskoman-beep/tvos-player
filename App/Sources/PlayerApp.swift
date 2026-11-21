import SwiftUI
import PlayerCore

@main
struct PlayerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
        }
    }
}

/// Ziel einer Navigation.
enum Route: Hashable {
    case detail(MetaPreview)
    case folder(Folder)
    case collection(String)
    case streams(type: String, id: String, title: String)
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var path = NavigationPath()
    @State private var settingsPath = NavigationPath()
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
        case .streams(let type, let id, let title): StreamListView(type: type, id: id, title: title)
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
