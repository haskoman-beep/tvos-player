import SwiftUI
import PlayerCore

/// Kategorie „Aussehen“ (§2.2). Task 4.5: on top „Mein Look“ (`LookHeaderRow`), below all configurator options in
/// four areas (`LookOptionRows`). The old rows for Navigation, Akzentfarbe, Postergröße and Poster aufklappen are
/// gone: the catalog rows `navigation`, `accent`, `cardSize` and `expandPosters` replace them fully and write the
/// old fields through `Profile.setLook`. What the catalog does not have stays below: Sprache der App, poster
/// images, ratings and badges („Titelbild oben“ stays under Startseite; badge style stays until `badgeStyle`
/// takes effect in Build 5b).
struct AppearanceSettings: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var icons = RatingIconStore.shared

    private let tint = SettingsCategory.appearance.tint

    var body: some View {
        let a = model.profile.appearance
        CategoryPage(.appearance, summary: SettingsSummary.look(model.profile)) {
            LookHeaderRow()
            LookOptionRows()
            SettingsSection("Sprache") {
                SettingsChoiceRow(symbol: "globe", tint: tint, title: "Sprache der App",
                                  detail: "Sprache von Titeln, Beschreibungen und Katalogen.",
                                  options: AppLanguage.allCases, selection: model.binding(\.language),
                                  alwaysList: true, label: SettingsSummary.languageName)
            }
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
                SettingsChoiceRow(symbol: "seal", tint: tint, title: "Plaketten-Stil",
                                  detail: "Logos oder schlichter Text für Auflösung, HDR und Ton.",
                                  options: [BadgeStyle.logo, .text], selection: model.binding(\.appearance.badges.style),
                                  label: { $0 == .logo ? "Logo" : "Text" })
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
    @EnvironmentObject var model: AppModel

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
