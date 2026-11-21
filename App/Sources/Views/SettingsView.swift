import SwiftUI
import PlayerCore

/// Einstellungs-Kategorien (wie NuvioTVOS `SettingsCategory`).
enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case profile, addons, services, home, appearance, playback, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: "Profil"
        case .addons: "Addons"
        case .services: "Dienste & Schlüssel"
        case .home: "Startseite"
        case .appearance: "Aussehen"
        case .playback: "Wiedergabe"
        case .about: "Über"
        }
    }

    var symbol: String {
        switch self {
        case .profile: "person.crop.circle"
        case .addons: "puzzlepiece"
        case .services: "key"
        case .home: "house"
        case .appearance: "paintpalette"
        case .playback: "play.circle"
        case .about: "info.circle"
        }
    }
}

/// Einstellungen des aktiven Profils (jedes Profil ist komplett eigenständig).
/// Links die Kategorien, rechts der Inhalt der fokussierten Kategorie.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var selected: SettingsCategory = .profile
    @FocusState private var focused: SettingsCategory?

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            List {
                NavigationLink {
                    PhoneInputView()
                } label: {
                    Label("Am Handy eingeben (QR-Code)", systemImage: "qrcode")
                }
                ForEach(SettingsCategory.allCases) { c in
                    Button { selected = c } label: {
                        HStack {
                            Label(c.title, systemImage: c.symbol)
                            Spacer()
                            if c == selected { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                        }
                    }
                    .focused($focused, equals: c)
                }
            }
            .frame(width: 520)
            .focusSection()

            List {
                Section {
                    Text(selected.title).font(.title2.bold())
                }
                content(selected)
            }
            .id(selected)
            .focusSection()
        }
        .onChange(of: focused) { _, f in if let f { selected = f } }
        .navigationTitle("Einstellungen")
    }

    @ViewBuilder private func content(_ c: SettingsCategory) -> some View {
        switch c {
        case .profile: ProfileSettings()
        case .addons: AddonSettings()
        case .services: ServiceSettings()
        case .home: HomeSettings()
        case .appearance: AppearanceSettings()
        case .playback: PlaybackSettings()
        case .about: AboutSettings()
        }
    }
}

extension AppModel {
    /// Bindung an ein Feld des aktiven Profils; Änderungen laufen über `update` (speichert sofort).
    func binding<T>(_ kp: WritableKeyPath<Profile, T>) -> Binding<T> {
        Binding(get: { self.profile[keyPath: kp] }, set: { v in self.update { $0[keyPath: kp] = v } })
    }
}

extension AccentChoice {
    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .orange: .orange
        case .green: .green
        case .white: .white
        }
    }

    var label: String {
        switch self {
        case .blue: "Blau"
        case .purple: "Lila"
        case .pink: "Pink"
        case .orange: "Orange"
        case .green: "Grün"
        case .white: "Weiß"
        }
    }
}
