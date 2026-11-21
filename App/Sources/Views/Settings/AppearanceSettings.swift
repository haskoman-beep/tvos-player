import SwiftUI
import PlayerCore

/// Kategorie „Aussehen“: Navigation, Akzentfarbe, Kartengröße, Hero, Poster aufklappen, Plaketten.
struct AppearanceSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Section("Navigation") {
            Picker("Navigation", selection: model.binding(\.appearance.navigation)) {
                Text("Seitenleiste").tag(NavigationStyle.sidebar)
                Text("Obere Leiste").tag(NavigationStyle.top)
            }
        }
        Section("Akzentfarbe: \(model.profile.appearance.accent.label)") {
            HStack(spacing: 30) {
                ForEach(AccentChoice.allCases, id: \.self) { a in
                    Button { model.update { $0.appearance.accent = a } } label: {
                        Circle().fill(a.color).frame(width: 60, height: 60)
                            .overlay {
                                if a == model.profile.appearance.accent {
                                    Image(systemName: "checkmark").font(.headline.bold())
                                        .foregroundStyle(a == .white ? .black : .white)
                                }
                            }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(a.label)
                }
            }
            .padding(.vertical, 10)
        }
        Section("Karten") {
            Picker("Kartengröße", selection: model.binding(\.appearance.cardSize)) {
                Text("Klein").tag(CardSize.small)
                Text("Mittel").tag(CardSize.medium)
                Text("Groß").tag(CardSize.large)
            }
            Toggle("Poster aufklappen", isOn: model.binding(\.appearance.expandPosters))
        }
        Section("Hero") {
            Toggle("Hero oben auf der Startseite", isOn: model.binding(\.appearance.heroEnabled))
            Picker("Hero-Quelle", selection: heroSelection) {
                Text("Automatisch").tag(UUID?.none)
                ForEach(listRows) { r in
                    Text(title(r)).tag(UUID?.some(r.id))
                }
            }
            .disabled(!model.profile.appearance.heroEnabled)
        }
        Section("Plaketten") {
            Picker("Plaketten-Stil", selection: model.binding(\.appearance.badges.style)) {
                Text("Logo").tag(BadgeStyle.logo)
                Text("Text").tag(BadgeStyle.text)
            }
            Toggle("Plaketten auf Postern", isOn: model.binding(\.appearance.badges.onPosters))
            ForEach(Self.badgeTypes.indices, id: \.self) { i in
                Toggle(Self.badgeTypes[i].0, isOn: model.binding((\Profile.appearance.badges).appending(path: Self.badgeTypes[i].1)))
            }
        }
    }

    /// Einzeln abschaltbare Plaketten-Typen (Quellenliste, Detailseite, Poster).
    private static let badgeTypes: [(String, WritableKeyPath<BadgeSettings, Bool>)] = [
        ("Auflösung", \.resolution), ("HDR / Dolby Vision", \.hdr), ("Quelle (REMUX, BluRay, WEB)", \.source),
        ("Videocodec", \.videoCodec), ("Tonformat", \.audio), ("Kanäle", \.channels), ("Sprachen", \.languages),
        ("Größe", \.size), ("Cache-Status (sofort / lädt erst)", \.cacheStatus),
    ]

    /// Zeigt „Automatisch“, wenn die gespeicherte Reihe keine Listen-Reihe (mehr) ist.
    private var heroSelection: Binding<UUID?> {
        Binding(get: {
            let id = model.profile.appearance.heroRowID
            return listRows.contains { $0.id == id } ? id : nil
        }, set: { v in model.update { $0.appearance.heroRowID = v } })
    }

    /// Nur Listen-Reihen, nie Collection-Reihen.
    private var listRows: [HomeRow] {
        model.profile.home.rows.filter { row in
            if case .list = row.content { return true }
            return false
        }
    }

    private func title(_ r: HomeRow) -> String {
        if case .list(let s) = r.content { return s.title }
        return ""
    }
}
