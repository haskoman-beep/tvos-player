import SwiftUI
import PlayerCore

/// Welle C-d: Einstellungen zur Quellenliste und zu Extras (Teil der Kategorie „Wiedergabe“).
struct SourceSettingsRows: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Toggle("Quellen klug ordnen", isOn: model.binding(\.sources.smartOrder))
        if model.profile.sources.smartOrder {
            Text("Gecachte Quellen und Quellen in der ersten Tonsprache zuerst; AV1 ab 1440p ohne Hardware-Dekoder und AV1 "
                 + "bei Dolby Vision nach hinten; bei mehreren Diensten TorBox zuerst. Sonst bleibt die Reihenfolge der Addons.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Welle C-d: Spoilerschutz für Folgenbilder (Teil der Kategorie „Aussehen“).
struct SpoilerSettingsRow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Toggle("Bilder ungesehener Folgen weichzeichnen", isOn: model.binding(\.sources.blurUnwatchedStills))
    }
}

/// Welle C-d: weitere Abschnitte der Kategorie „Aussehen“ (Kalender, Bewertungs-Icons).
struct ExtrasSettingsSections: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Section("Kalender") {
            Toggle("Sendezeiten von TVmaze", isOn: model.binding(\.sources.tvmazeAirtimes))
            Text("Zeigt Uhrzeit und den Tag in deiner Zeitzone (US-Abendfolgen stehen sonst einen Tag zu früh). "
                 + "Sendedaten von TVmaze.com, Lizenz CC BY-SA 4.0.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
