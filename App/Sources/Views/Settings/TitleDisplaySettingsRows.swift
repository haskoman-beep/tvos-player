import SwiftUI
import PlayerCore

/// Welle E-a: „Qualität auf Postern“ (Zeile im Abschnitt „Plaketten“).
struct PosterQualitySettingRow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Picker("Qualität auf Postern", selection: model.binding(\.appearance.titles.posterBadges)) {
            Text("Aus").tag(PosterBadgePlacement.off)
            Text("Oben rechts").tag(PosterBadgePlacement.topTrailing)
            Text("Unten").tag(PosterBadgePlacement.bottom)
        }
    }
}

/// Welle E-a: Abschnitte „Bewertungen“ und „Metadaten-Addon“ – nur Hülle, damit der Einhängepunkt eine Zeile bleibt.
/// Die Einstellungen selbst sind eigene Zeilen-Structs (Welle F verschiebt sie im neuen Einstellungsbaum).
struct TitleDisplaySettingsSections: View {
    var body: some View {
        Section("Bewertungen") { RatingChoiceSettingRow() }
        Section("Metadaten-Addon") { MetadataAddonImagesSettingRow() }
    }
}

/// Welle E-a: gezeigte Bewertungsquellen (Schalter je Quelle), Standard IMDb, Rotten Tomatoes, Trakt.
struct RatingChoiceSettingRow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ForEach(RatingSelection.sources, id: \.source) { s in
            Toggle(s.name, isOn: Binding(
                get: { model.profile.appearance.titles.shows(rating: s.source) },
                set: { on in
                    model.update { $0.appearance.titles.set(rating: s.source, on) }
                    model.titleImagesChanged()
                    RemoteLog.info("einstellung", "Bewertung \(s.source) \(on ? "an" : "aus")")
                }))
        }
        Text("Detailseite und Startseite. IMDb kommt auch ohne MDBList-Schlüssel aus den Metadaten, "
             + "die übrigen Werte liefert MDBList.")
            .font(.caption).foregroundStyle(.secondary)
    }
}

/// Welle E-a: „Bilder vom Metadaten-Addon“, Standard an; ohne Metadaten-Addon gesperrt.
struct MetadataAddonImagesSettingRow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Toggle("Bilder vom Metadaten-Addon", isOn: Binding(
            get: { model.profile.appearance.titles.addonImages },
            set: { on in
                model.update { $0.appearance.titles.addonImages = on }
                model.titleImagesChanged()
                RemoteLog.info("einstellung", "Bilder vom Metadaten-Addon \(on ? "an" : "aus")")
            }))
            .disabled(!model.hasMetadataAddon)
        Text(model.hasMetadataAddon
             ? "Poster, Hintergrund und Logo des Metadaten-Addons (z. B. dort eingerichtete Bewertungs-Poster) vor den TMDB-Bildern, auch auf Kacheln der TMDB-Reihen."
             : "Kein Addon mit Metadaten installiert.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
