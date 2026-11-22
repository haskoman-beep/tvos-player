import SwiftUI
import PlayerCore

/// Kategorie 1, Abschnitte „Konten“ und „Schlüssel“: Trakt/Simkl verbinden, Schlüssel-Status.
/// Wave S: all keys in one place, TorBox included (was under Addons & Quellen › TorBox).
/// E7: Schlüssel und Client IDs nur noch am Handy; hier Status und Sprung auf die Handy-Seite (#keys).
struct AccountSettingsRows: View {
    @EnvironmentObject var model: AppModel
    @State private var logout: String?

    private let tint = SettingsCategory.profile.tint

    private static func name(_ s: String) -> String { s == "trakt" ? "Trakt" : "Simkl" }

    var body: some View {
        SettingsSection("Konten") {
            ForEach(AppModel.syncServices, id: \.self) { s in
                let name = Self.name(s)
                let state = SettingsSummary.AccountState.of(hasClient: model.hasClient(s), connected: model.isConnected(s))
                switch state {
                case .connected:
                    SettingsRow(symbol: "person.badge.key", tint: tint, title: name, detail: "OK meldet ab.",
                                accessory: .value(state.valueText), reserveDetailSpace: false) { logout = s }
                case .connectable:
                    SettingsLinkRow(symbol: "person.badge.key", tint: tint, title: name,
                                    detail: "Anmelden mit Code auf einem anderen Gerät.", value: state.valueText) {
                        SyncLoginView(service: s)
                    }
                case .missingClient:
                    PhoneLinkRow(section: .keys, symbol: "person.badge.key", tint: tint, title: name,
                                 detail: "Client ID am Handy unter „Konten & Schlüssel“ eintragen.", value: state.valueText)
                }
            }
        }
        SettingsSection("Schlüssel") {
            PhoneLinkRow(section: .keys, symbol: "key", tint: tint, title: "TMDB-Schlüssel",
                         detail: "Kataloge, Bilder und Suche. Eingabe am Handy.", value: SettingsSummary.keyValue(model.profile.apiKeys["tmdb"]))
            PhoneLinkRow(section: .keys, symbol: "star", tint: tint, title: "MDBList-Schlüssel",
                         detail: "Bewertungen außer IMDb. Eingabe am Handy.", value: SettingsSummary.keyValue(model.profile.apiKeys["mdblist"]))
            // Same row as before (phone anchor #addon, where the TorBox field lives), only moved.
            PhoneLinkRow(section: .addon, symbol: "externaldrive", tint: tint, title: "TorBox",
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
