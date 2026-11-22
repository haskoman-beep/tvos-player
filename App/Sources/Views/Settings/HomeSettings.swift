import SwiftUI
import PlayerCore

/// Kategorie „Startseite“ (Plan §2.2): Verwalter „Reihen & Collections“, Fusion-Kit, Import am Handy.
/// Reihen ordnen, hinzufügen und ausblenden passiert im Verwalter (Welle F-b2); Importe laufen über die Handy-Seite.
struct HomeSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let n = model.profile.home.rows.count
        NavigationLink { HomeManagerView() } label: {
            SettingsRowLabel(symbol: "rectangle.stack", tint: Theme.CategoryTint.home.color, title: "Reihen & Collections",
                             detail: "Reihenfolge, Stil, hinzufügen und ausblenden",
                             accessory: .valueChevron(n == 1 ? "1 Reihe" : "\(n) Reihen"), reserveDetailSpace: false)
        }
        .buttonStyle(ThemeRowButtonStyle())
        .settingsRowAccessibility(title: "Reihen & Collections", detail: nil, accessory: .value(n == 1 ? "1 Reihe" : "\(n) Reihen"))
        FusionKitSettingsView()
        NavigationLink { PhoneInputView(section: .quickImport) } label: {
            SettingsRowLabel(symbol: "square.and.arrow.down", tint: Theme.CategoryTint.home.color, title: "Collections importieren",
                             detail: "Nuvio-Export, Fusion-Kit-URL, TMDB- oder Trakt-Liste am Handy einfügen",
                             accessory: .chevron, reserveDetailSpace: false)
        }
        .buttonStyle(ThemeRowButtonStyle())
        .settingsRowAccessibility(title: "Collections importieren", detail: "Am Handy", accessory: .chevron)
        // Wave F-o: sound of the focus video on package tiles (once per focus), default off.
        SettingsToggleRow(symbol: "speaker.wave.2", tint: Theme.CategoryTint.home.color, title: "Ton bei Kachel-Animation",
                          detail: "Spielt den Ton eines Kachel-Videos einmal pro Fokus – nur bei Videos mit Tonspur, z. B. aus einem Collection-Import. Die Videos der fertigen Pakete sind stumm.",
                          reserveDetailSpace: false, isOn: model.binding(\.appearance.tileAnimationSound))
    }
}
