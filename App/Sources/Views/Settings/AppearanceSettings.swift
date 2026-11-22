import SwiftUI
import PlayerCore

/// Kategorie 4 „Aussehen“ (§2.2): Navigation, Akzentfarbe, Sprache, Karten, Detailseite, Plaketten.
/// „Titelbild oben“ (früher Hero) steht jetzt unter Startseite.
struct AppearanceSettings: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var icons = RatingIconStore.shared

    private let tint = SettingsCategory.appearance.tint

    /// Kachelfarbe für eine Akzentfarbe; Weiß wird zu Grau, damit das (weiße) Symbol sichtbar bleibt.
    static func visibleTint(_ a: AccentChoice) -> Color { a == .white ? Color(white: 0.45) : a.color }

    var body: some View {
        let a = model.profile.appearance
        CategoryPage(.appearance, summary: SettingsSummary.appearance(navigation: a.navigation, accent: a.accent, cardSize: a.cardSize)) {
            SettingsSection {
                SettingsChoiceRow(symbol: "sidebar.left", tint: tint, title: "Navigation",
                                  detail: "Bereiche als Seitenleiste links oder als Leiste oben.",
                                  options: NavigationStyle.allCases, selection: model.binding(\.appearance.navigation),
                                  alwaysList: true, label: SettingsSummary.navigationName)
                // Review F-a M1: bei Weiß kein weißes Symbol auf weißer Kachel.
                SettingsChoiceRow(symbol: "paintbrush", tint: Self.visibleTint(a.accent), title: "Akzentfarbe",
                                  detail: "Markierungen und Fortschrittsbalken.",
                                  options: AccentChoice.allCases, selection: model.binding(\.appearance.accent),
                                  optionTint: Self.visibleTint, label: SettingsSummary.accentName)
                SettingsChoiceRow(symbol: "globe", tint: tint, title: "Sprache der App",
                                  detail: "Sprache von Titeln, Beschreibungen und Katalogen.",
                                  options: AppLanguage.allCases, selection: model.binding(\.language),
                                  alwaysList: true, label: SettingsSummary.languageName)
            }
            SettingsSection("Karten") {
                // Welle F-f: dieselbe Zeile wie unter Startseite › Kacheln (gleicher Wert, gleicher Text).
                PosterSizeSettingRow(tint: tint)
                SettingsToggleRow(symbol: "rectangle.expand.vertical", tint: tint, title: "Poster aufklappen",
                                  detail: "Die fokussierte Kachel klappt zum breiten Bild mit Titel auf.",
                                  reserveDetailSpace: false, isOn: model.binding(\.appearance.expandPosters))
                PosterQualitySettingRow()
                MetadataAddonImagesSettingRow()
                SpoilerSettingsRow()
            }
            SettingsSection("Detailseite") {
                SettingsLinkRow(symbol: "star", tint: tint, title: "Bewertungen",
                                detail: "Welche Bewertungen auf Detailseite und Startseite stehen.",
                                value: RatingChoiceSettingRow.summary(a.titles)) {
                    RatingsSettingsPage()
                }
            }
            SettingsSection("Plaketten") {
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
        ("Größe", \.size), ("Cache-Status (sofort / lädt erst)", \.cacheStatus),
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
