import SwiftUI
import PlayerCore

/// Kategorie „Aussehen“: Navigation, Akzentfarbe, Kartengröße, Hero, Poster aufklappen.
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
            Picker("Hero-Quelle", selection: model.binding(\.appearance.heroRowID)) {
                Text("Automatisch").tag(UUID?.none)
                ForEach(listRows) { r in
                    Text(title(r)).tag(UUID?.some(r.id))
                }
            }
            .disabled(!model.profile.appearance.heroEnabled)
        }
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
