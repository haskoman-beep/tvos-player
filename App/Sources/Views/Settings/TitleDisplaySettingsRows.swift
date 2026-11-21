import SwiftUI
import PlayerCore

/// Welle E-a: „Qualität auf Postern“; Welle F-a: Zeile im Abschnitt „Karten“ der Kategorie Aussehen.
struct PosterQualitySettingRow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        SettingsChoiceRow(symbol: "4k.tv", tint: SettingsCategory.appearance.tint, title: "Qualität auf Postern",
                          detail: "Auflösung und HDR als Plakette auf den Kacheln.",
                          options: [PosterBadgePlacement.off, .topTrailing, .bottom],
                          selection: model.binding(\.appearance.titles.posterBadges),
                          label: Self.name)
    }

    static func name(_ p: PosterBadgePlacement) -> String {
        switch p {
        case .off: "Aus"
        case .topTrailing: "Oben rechts"
        case .bottom: "Unten"
        }
    }
}

/// Welle E-a: gezeigte Bewertungsquellen (Schalter je Quelle), Standard IMDb, Rotten Tomatoes, Trakt.
/// Welle F-a: auf der Unterseite „Bewertungen“ (Aussehen › Detailseite).
struct RatingChoiceSettingRow: View {
    @EnvironmentObject var model: AppModel

    /// Wert der Zeile „Bewertungen ›“: „IMDb, Trakt“ bzw. „3 Quellen“ / „Keine“.
    static func summary(_ t: TitleDisplaySettings) -> String {
        let names = RatingSelection.sources.filter { t.shows(rating: $0.source) }.map(\.name)
        switch names.count {
        case 0: return "Keine"
        case 1, 2: return names.joined(separator: ", ")
        default: return "\(names.count) Quellen"
        }
    }

    var body: some View {
        ForEach(RatingSelection.sources, id: \.source) { s in
            SettingsToggleRow(symbol: "star", tint: SettingsCategory.appearance.tint, title: s.name,
                              reserveDetailSpace: false,
                              isOn: Binding(
                                  get: { model.profile.appearance.titles.shows(rating: s.source) },
                                  set: { on in
                                      model.update { $0.appearance.titles.set(rating: s.source, on) }
                                      model.titleImagesChanged()
                                      RemoteLog.info("einstellung", "Bewertung \(s.source) \(on ? "an" : "aus")")
                                  }))
        }
        SettingsFootnote("IMDb kommt auch ohne MDBList-Schlüssel aus den Metadaten, die übrigen Werte liefert MDBList.")
    }
}

/// Unterseite „Bewertungen“ (§2.2 Aussehen › Detailseite).
struct RatingsSettingsPage: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        SettingsSubpage(title: "Bewertungen", summary: "Auf Detailseite und Startseite · " + RatingChoiceSettingRow.summary(model.profile.appearance.titles)) {
            RatingChoiceSettingRow()
        }
    }
}

/// Welle E-a: „Bilder vom Metadaten-Addon“, Standard an; ohne Metadaten-Addon gesperrt.
struct MetadataAddonImagesSettingRow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        SettingsToggleRow(symbol: "photo", tint: SettingsCategory.appearance.tint, title: "Bilder vom Metadaten-Addon",
                          detail: model.hasMetadataAddon
                              ? "Poster, Hintergrund und Logo des Metadaten-Addons vor den TMDB-Bildern, auch auf Kacheln der TMDB-Reihen."
                              : "Kein Addon mit Metadaten installiert.",
                          detailAlwaysVisible: !model.hasMetadataAddon,
                          reserveDetailSpace: false,
                          isOn: Binding(
                              get: { model.profile.appearance.titles.addonImages },
                              set: { on in
                                  model.update { $0.appearance.titles.addonImages = on }
                                  model.titleImagesChanged()
                                  RemoteLog.info("einstellung", "Bilder vom Metadaten-Addon \(on ? "an" : "aus")")
                              }))
            .disabled(!model.hasMetadataAddon)
    }
}
