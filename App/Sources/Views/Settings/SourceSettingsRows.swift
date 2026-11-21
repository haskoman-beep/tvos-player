import SwiftUI
import PlayerCore

/// Welle C-d: Einstellungen zur Quellenliste und zu Extras (Teil der Kategorie „Wiedergabe“).
struct SourceSettingsRows: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        // Welle E-b: Liste folgt standardmäßig dem Addon (Reihenfolge und Text wie dessen Formatter).
        Picker("Quellen sortieren", selection: model.binding(\.sources.order)) {
            ForEach(StreamOrderMode.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        Text(model.profile.sources.order == .smart
             ? "Gecachte Quellen und Quellen in der ersten Tonsprache zuerst; AV1 ab 1440p ohne Hardware-Dekoder und AV1 "
               + "bei Dolby Vision nach hinten; bei mehreren Diensten TorBox zuerst. Sonst bleibt die Reihenfolge der Addons."
             : "Reihenfolge, wie die Addons sie liefern. Weiterschauen, automatischer Wechsel und nächste Folge wählen "
               + "trotzdem klug (Tonsprache, AV1-Dekoder, Cache-Status).")
            .font(.caption).foregroundStyle(.secondary)
        Picker("App-Plaketten in der Quellenliste", selection: model.binding(\.sources.appBadges)) {
            ForEach(StreamListBadgeMode.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        if model.profile.sources.appBadges == .compact {
            Text("Nur „sofort“ und Größe, und nur, wenn der Text des Addons sie nicht schon zeigt.")
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
        RatingIconSettings()
    }
}

/// Welle C-d: Adresse eines eigenen Bewertungs-Icon-Satzes (JSON, wird nur zur Laufzeit geladen).
struct RatingIconSettings: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var store = RatingIconStore.shared
    @State private var text = ""

    var body: some View {
        Section("Bewertungs-Icons") {
            TextField("https://…/icons.json", text: $text)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .onSubmit { save(text) }
            if let current = model.profile.sources.ratingIconSetURL {
                HStack { Text("Aktiv"); Spacer(); Text(store.status ?? "lädt …").foregroundStyle(.secondary) }
                Text(current).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Button("Eingebaute Plaketten verwenden") { save("") }
            }
            Text("JSON wie {\"imdb\": \"https://…/imdb.png\", \"tomatoes\": \"https://…\"} oder [{\"name\", \"url\"}]. "
                 + "Nur https, Bilder als PNG/JPG/WebP/HEIC (kein SVG), höchstens 50 Einträge; fehlt oder scheitert ein Icon, bleibt der Text.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task(id: model.profile.sources.ratingIconSetURL) { store.ensure(model.profile.sources.ratingIconSetURL) }
    }

    private func save(_ s: String) {
        let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if !v.isEmpty, !RatingIconSet.isValidSetURL(v) { model.lastError = "Icon-Satz: nur https-Adressen"; return }
        model.update { $0.sources.ratingIconSetURL = v.isEmpty ? nil : v }
        text = ""
        RemoteLog.info("bewertung", v.isEmpty ? "Icon-Satz aus" : "Icon-Satz gesetzt")
    }
}
