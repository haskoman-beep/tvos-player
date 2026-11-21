import SwiftUI
import PlayerCore

/// Welle E-a: „Qualität auf Postern“ (Zeile im Abschnitt „Plaketten“).
struct PosterBadgePlacementRow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Picker("Qualität auf Postern", selection: model.binding(\.appearance.titles.posterBadges)) {
            Text("Aus").tag(PosterBadgePlacement.off)
            Text("Oben rechts").tag(PosterBadgePlacement.topTrailing)
            Text("Unten").tag(PosterBadgePlacement.bottom)
        }
    }
}

/// Welle E-a: Abschnitt „Detailseite“: gezeigte Bewertungen, Bilder vom Metadaten-Addon.
struct TitleDisplaySettingsSections: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Section("Bewertungen") {
            ForEach(RatingSelection.sources, id: \.source) { s in
                Toggle(s.name, isOn: Binding(
                    get: { model.profile.appearance.titles.shows(rating: s.source) },
                    set: { on in
                        model.update { $0.appearance.titles.set(rating: s.source, on) }
                        RemoteLog.info("einstellung", "Bewertung \(s.source) \(on ? "an" : "aus")")
                    }))
            }
            Text("Detailseite und Startseite. IMDb kommt auch ohne MDBList-Schlüssel aus den Metadaten, "
                 + "die übrigen Werte liefert MDBList.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Metadaten-Addon") {
            Toggle("Bilder vom Metadaten-Addon", isOn: model.binding(\.appearance.titles.addonImages))
                .disabled(!model.hasMetadataAddon)
            Text(model.hasMetadataAddon
                 ? "Poster, Hintergrund und Logo des Metadaten-Addons (z. B. dort eingerichtete Bewertungs-Poster) vor den TMDB-Bildern."
                 : "Kein Addon mit Metadaten installiert.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
