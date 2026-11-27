import SwiftUI
import PlayerCore

/// Kategorie 1, Abschnitte „Konten“ und „Schlüssel“: Trakt/Simkl verbinden, Schlüssel-Status.
/// Wave S: all keys in one place, TorBox included (was under Addons & Quellen › TorBox).
/// E7: Schlüssel und Client IDs nur noch am Handy; hier Status und Sprung auf die Handy-Seite (#keys).
struct AccountSettingsRows: View {
    @Environment(AppModel.self) var model
    @State private var logout: String?
    /// F-B-3: page opened from an account row. It lives outside the state switch, so the success of the page itself
    /// (keys saved, login done) only changes the row's value, never removes the link behind the open page.
    @State private var page: AccountPage?

    private enum AccountPage: Hashable, Identifiable {
        case login(String)
        case phoneKeys
        var id: Self { self }
    }

    private let tint = SettingsCategory.profile.tint

    private static func name(_ s: String) -> String { s == "trakt" ? "Trakt" : "Simkl" }

    private static func detail(_ state: SettingsSummary.AccountState) -> String {
        switch state {
        case .connected: "OK meldet ab."
        case .connectable: "Anmelden mit Code auf einem anderen Gerät."
        case .missingClient: "Client ID am Handy unter „Konten & Schlüssel“ eintragen."
        }
    }

    var body: some View {
        SettingsSection("Konten") {
            ForEach(AppModel.syncServices, id: \.self) { s in
                let name = Self.name(s)
                let state = SettingsSummary.AccountState.of(hasClient: model.hasClient(s), connected: model.isConnected(s))
                // One row with a stable identity in every state (F-B-3); only value, detail and action change.
                SettingsRow(symbol: "person.badge.key", tint: tint, title: name, detail: Self.detail(state),
                            accessory: state == .connected ? .value(state.valueText) : .valueChevron(state.valueText),
                            reserveDetailSpace: false) {
                    switch state {
                    case .connected: logout = s
                    case .connectable: page = .login(s)
                    case .missingClient: page = .phoneKeys
                    }
                }
            }
        }
        .navigationDestination(item: $page) { p in
            switch p {
            case .login(let s): SyncLoginView(service: s)
            case .phoneKeys: PhoneInputView(section: .keys)
            }
        }
        SettingsSection("Schlüssel") {
            PhoneLinkRow(section: .keys, symbol: "key", tint: tint, title: "TMDB-Schlüssel",
                         detail: "Kataloge, Bilder und Suche. Eingabe am Handy.", value: SettingsSummary.keyValue(model.profile.apiKeys["tmdb"]))
            PhoneLinkRow(section: .keys, symbol: "star", tint: tint, title: "MDBList-Schlüssel",
                         detail: "Bewertungen außer IMDb. Eingabe am Handy.", value: SettingsSummary.keyValue(model.profile.apiKeys["mdblist"]))
            // Phone anchor #keys: the TorBox field sits with the other keys on the phone page too (wave S).
            PhoneLinkRow(section: .keys, symbol: "externaldrive", tint: tint, title: "TorBox",
                         detail: "Schlüssel für „Meine TorBox-Dateien“. Eingabe am Handy.",
                         value: SettingsSummary.keyValue(model.profile.apiKeys["torbox"]))
        }
        // item-Variante: die Aktion läuft nach dem Schließen, `logout` ist dann schon nil (Zusammenführung F).
        .settingsConfirmation(item: $logout, title: { "Von \(Self.name($0)) abmelden?" },
                              message: { "Fortschritt und Listen von \(Self.name($0)) erscheinen nicht mehr, bis du dich neu anmeldest." },
                              verb: "Abmelden", symbol: "rectangle.portrait.and.arrow.right") { s in
            RemoteLog.info("einstellung", "\(Self.name(s)) abgemeldet")
            model.disconnect(s)
        }
    }
}
