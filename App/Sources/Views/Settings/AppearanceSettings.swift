import SwiftUI
import PlayerCore

/// Kategorie „Aussehen“ (§2.2). Task 4.5: on top „Mein Look“ (`LookHeaderRow`), below all configurator options in
/// four areas (`LookOptionRows`). The old rows for Navigation, Akzentfarbe, Postergröße and Poster aufklappen are
/// gone: the catalog rows `navigation`, `accent`, `cardSize` and `expandPosters` replace them fully and write the
/// old fields through `Profile.setLook`. Sprache der App stays the first row under „Mein Look“. What the catalog
/// does not have otherwise stays below the areas: poster images, ratings and badges. Integration build 5 (user
/// decision 26.11.): the old row „Plaketten-Stil“ is gone too; the look row `badgeStyle` sets the style
/// (`Profile.adoptOldLookRows` moves an old value into the look once).
struct AppearanceSettings: View {
    @Environment(AppModel.self) var model
    @ObservedObject private var icons = RatingIconStore.shared

    private let tint = SettingsCategory.appearance.tint

    var body: some View {
        let a = model.profile.appearance
        CategoryPage(.appearance, summary: SettingsSummary.look(model.profile)) {
            LookHeaderRow()
            // Review I2: Sprache der App stays the first content row (since wave S), right under „Mein Look“.
            SettingsChoiceRow(symbol: "globe", tint: tint, title: "Sprache der App",
                              detail: "Sprache von Titeln, Beschreibungen und Katalogen.",
                              options: AppLanguage.allCases, selection: model.binding(\.language),
                              alwaysList: true, label: SettingsSummary.languageName)
            LookOptionRows()
            SettingsSection("Poster und Bilder") {
                PosterQualitySettingRow()
                MetadataAddonImagesSettingRow()
                SpoilerSettingsRow()
            }
            SettingsSection("Bewertungen und Plaketten") {
                SettingsLinkRow(symbol: "star", tint: tint, title: "Bewertungen",
                                detail: "Welche Bewertungen auf Detailseite und Startseite stehen.",
                                value: RatingChoiceSettingRow.summary(a.titles)) {
                    RatingsSettingsPage()
                }
                SettingsLinkRow(symbol: "list.bullet", tint: tint, title: "Plaketten im Detail",
                                detail: "Einzelne Plaketten-Arten ein- und ausschalten.",
                                value: "\(BadgeDetailPage.shownCount(a.badges)) von \(BadgeDetailPage.types.count)") {
                    BadgeDetailPage()
                }
                SettingsLinkRow(symbol: "photo.on.rectangle", tint: tint, title: "Eigener Bewertungs-Icon-Satz",
                                detail: "Eigene Bilder für Bewertungen. Adresse am Handy.",
                                value: RatingIconSettingsPage.value(model.profile.sources.ratingIconSetURL, status: icons.status)) {
                    RatingIconSettingsPage()
                }
            }
        }
        .task(id: model.profile.sources.ratingIconSetURL) { icons.ensure(model.profile.sources.ratingIconSetURL) }
    }
}

/// Unterseite „Plaketten im Detail“: die 9 Typ-Schalter (Quellenliste, Detailseite, Poster).
struct BadgeDetailPage: View {
    @Environment(AppModel.self) var model

    /// Einzeln abschaltbare Plaketten-Typen.
    static let types: [(String, WritableKeyPath<BadgeSettings, Bool>)] = [
        ("Auflösung", \.resolution), ("HDR / Dolby Vision", \.hdr), ("Quelle (REMUX, BluRay, WEB)", \.source),
        ("Videocodec", \.videoCodec), ("Tonformat", \.audio), ("Kanäle", \.channels), ("Sprachen", \.languages),
        ("Größe", \.size), ("Cache-Status (Sofort bereit / Nicht gecacht)", \.cacheStatus),
    ]

    static func shownCount(_ b: BadgeSettings) -> Int { types.filter { b[keyPath: $0.1] }.count }

    var body: some View {
        SettingsSubpage(title: "Plaketten im Detail", summary: "Quellenliste, Detailseite und Poster") {
            ForEach(Self.types.indices, id: \.self) { i in
                SettingsToggleRow(symbol: "seal", tint: SettingsCategory.appearance.tint, title: Self.types[i].0,
                                  reserveDetailSpace: false,
                                  isOn: model.binding((\Profile.appearance.badges).appending(path: Self.types[i].1)))
            }
        }
    }
}
