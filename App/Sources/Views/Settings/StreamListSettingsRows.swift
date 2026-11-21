import SwiftUI
import PlayerCore

/// Welle E-b: Einstellung „Quellen sortieren“ (Wie Addon / Smart (App)). Eigene Zeile, damit Welle F sie verschieben kann.
struct StreamOrderSettingsRow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Picker("Quellen sortieren", selection: model.binding(\.sources.order)) {
            ForEach(StreamOrderMode.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        Text(model.profile.sources.order == .smart
             ? "Gecachte Quellen und Quellen in der ersten Tonsprache zuerst; AV1 ab 1440p ohne Hardware-Dekoder und AV1 "
               + "bei Dolby Vision nach hinten; bei mehreren Diensten TorBox zuerst. Sonst bleibt die Reihenfolge der Addons."
             : "Reihenfolge, wie die Addons sie liefern. Weiterschauen, automatischer Wechsel und nächste Folge wählen "
               + "trotzdem klug (Tonsprache, AV1-Dekoder, Cache-Status).")
            .font(.caption).foregroundStyle(.secondary)
    }
}

/// Welle E-b: Einstellung „App-Plaketten in der Quellenliste“ (Aus / Kompakt). Eigene Zeile für Welle F.
struct StreamListBadgeSettingsRow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Picker("App-Plaketten in der Quellenliste", selection: model.binding(\.sources.appBadges)) {
            ForEach(StreamListBadgeMode.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        if model.profile.sources.appBadges == .compact {
            Text("Nur „sofort“ und Größe, und nur, wenn der Text des Addons sie nicht schon zeigt.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
