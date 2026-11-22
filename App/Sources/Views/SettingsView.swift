import SwiftUI
import PlayerCore

/// Einstellungs-Kategorien (linke Spalte), Zielbaum §2.2 (Welle F-a).
enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case profile, addons, home, appearance, playback, audio, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: "Profil & Konten"
        case .addons: "Addons & Quellen"
        case .home: "Startseite"
        case .appearance: "Aussehen"
        case .playback: "Wiedergabe & Bild"
        case .audio: "Ton & Untertitel"
        case .system: "System"
        }
    }

    var symbol: String {
        switch self {
        case .profile: "person.crop.circle"
        case .addons: "puzzlepiece.extension"
        case .home: "house"
        case .appearance: "paintpalette"
        case .playback: "play.rectangle"
        case .audio: "captions.bubble"
        case .system: "gearshape.2"
        }
    }

    /// Kategoriefarbe der Symbolkacheln (F-0 `Theme.CategoryTint`).
    var tint: Color {
        switch self {
        case .profile: Theme.CategoryTint.profile.color
        case .addons: Theme.CategoryTint.addons.color
        case .home: Theme.CategoryTint.home.color
        case .appearance: Theme.CategoryTint.appearance.color
        case .playback: Theme.CategoryTint.playback.color
        case .audio: Theme.CategoryTint.audio.color
        case .system: Theme.CategoryTint.system.color
        }
    }
}

/// Einstellungen des aktiven Profils (jedes Profil ist komplett eigenständig).
/// Links Kopfkachel „Am Handy einrichten“ und die Kategorien, rechts der Inhalt der fokussierten Kategorie.
/// Fokus und Menu regelt `CategoryList` (Verhalten aus fix-einstellungen): Menu aus dem Inhalt auf die aktive
/// Kategorie, aus der Kategorienspalte `leave`. Unterseiten liegen im NavigationStack und schließen sich vorher selbst.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Binding var selected: SettingsCategory
    /// Zurück in der obersten Ebene: verlässt die Einstellungen (RootView wechselt in den vorherigen Bereich).
    /// Ohne Standardwert (fix-einstellungen Minor 1): ein vergessener Aufrufer fiele sonst still in ein No-op.
    let leave: () -> Void

    var body: some View {
        CategoryList(items: SettingsCategory.allCases, selected: $selected,
                     entry: { CategoryEntry(title: $0.title, symbol: $0.symbol, tint: $0.tint) },
                     onExit: leave,
                     header: { phoneTile },
                     content: { content($0) })
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .settingsSurface()
            .onChange(of: selected) { _, c in RemoteLog.info("nav", "Einstellungen: Kategorie \(c.title)") }
    }

    /// Kopfkachel: genau ein Knopf als Wurzel (Vorgabe von `CategoryList`).
    private var phoneTile: some View {
        NavigationLink {
            PhoneInputView()
        } label: {
            SettingsRowLabel(symbol: "qrcode", tint: Theme.CategoryTint.system.color, title: "Am Handy einrichten",
                             detail: "Addons, Schlüssel, Importe", accessory: .chevron,
                             detailAlwaysVisible: true, reserveDetailSpace: false)
        }
        .buttonStyle(ThemeRowButtonStyle(maxWidth: .infinity))
        .settingsRowAccessibility(title: "Am Handy einrichten", detail: "Addons, Schlüssel, Importe", accessory: .chevron)
    }

    @ViewBuilder private func content(_ c: SettingsCategory) -> some View {
        switch c {
        case .profile: ProfileSettings()
        case .addons: AddonSettings()
        case .home: HomeCategorySettings()
        case .appearance: AppearanceSettings()
        case .playback: PlaybackSettings()
        case .audio: AudioSettings()
        case .system: SystemSettings()
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

    /// Name wie in der Zusammenfassung (PlayerCore `SettingsSummary.accentName`).
    var label: String { SettingsSummary.accentName(self) }
}
