import SwiftUI
import PlayerCore

/// Kategorie „Startseite“ (Plan §2.2): Verwalter „Reihen & Collections“, Fusion-Kit, Import am Handy.
/// Reihen ordnen, hinzufügen und ausblenden passiert im Verwalter (Welle F-b2); Importe laufen über die Handy-Seite.
struct HomeSettings: View {
    @Environment(AppModel.self) var model

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
                             detail: "Collection-Link oder -Code, TMDB- oder Trakt-Liste am Handy einfügen",
                             accessory: .chevron, reserveDetailSpace: false)
        }
        .buttonStyle(ThemeRowButtonStyle())
        .settingsRowAccessibility(title: "Collections importieren", detail: "Am Handy", accessory: .chevron)
        // Wave F-o round 2: collection link in the app (fetch, detect, import; "Aktualisieren" later).
        let links = CollectionLinkStore.shared.links.count
        NavigationLink { CollectionLinksPage() } label: {
            SettingsRowLabel(symbol: "link", tint: Theme.CategoryTint.home.color, title: "Collection-Link hinzufügen",
                             detail: "Widget-Export, Preview Pack oder Collection-Export als Link – mit Videos und Ton der Kacheln",
                             accessory: links == 0 ? .chevron : .valueChevron(links == 1 ? "1 Link" : "\(links) Links"),
                             reserveDetailSpace: false)
        }
        .buttonStyle(ThemeRowButtonStyle())
        .settingsRowAccessibility(title: "Collection-Link hinzufügen", detail: nil, accessory: .chevron)
        // Wave F-o: sound of the focus video on tiles (once per focus, at most about 12 s), default off.
        SettingsToggleRow(symbol: "speaker.wave.2", tint: Theme.CategoryTint.home.color, title: "Ton bei Kachel-Animation",
                          detail: "Spielt den Ton eines importierten Kachel-Videos einmal pro Fokus (höchstens etwa 12 s) – z. B. aus einem Preview Pack.",
                          reserveDetailSpace: false, isOn: model.binding(\.appearance.tileAnimationSound))
    }
}
