import Foundation

/// Welle E-a: wo die Qualitäts-Plaketten am Poster sitzen. Standard aus: viele Poster (z. B. Bewertungs-Poster eines
/// Metadaten-Addons) tragen unten schon eine Genre-/Bewertungszeile, die nie verdeckt werden soll.
public enum PosterBadgePlacement: String, Codable, Sendable, CaseIterable {
    /// Keine Plaketten auf Postern.
    case off
    /// Oben rechts auf dem Bild.
    case topTrailing
    /// In einem eigenen Streifen unter dem Bild (nie auf dem Bild).
    case bottom
}

/// Welle E-a: Anzeige von Postern und Detailseite (Teil von `Appearance`). Fehlende Felder: Standardwerte.
public struct TitleDisplaySettings: Codable, Sendable, Hashable {
    /// „Qualität auf Postern“.
    public var posterBadges: PosterBadgePlacement
    /// Gezeigte Bewertungsquellen (MDBList-Schlüssel wie "imdb", "tomatoes"); Anzeige in fester Reihenfolge.
    public var ratingSources: [String]
    /// „Bilder vom Metadaten-Addon“: Poster/Hintergrund/Logo des Metadaten-Addons vor den TMDB-Bildern.
    /// Wirkt nur, wenn ein Addon mit Metadaten installiert ist.
    public var addonImages: Bool

    public init(posterBadges: PosterBadgePlacement = .off, ratingSources: [String] = RatingSelection.defaultSources,
                addonImages: Bool = true) {
        self.posterBadges = posterBadges; self.ratingSources = ratingSources; self.addonImages = addonImages
    }

    enum CodingKeys: String, CodingKey { case posterBadges, ratingSources, addonImages }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TitleDisplaySettings()
        posterBadges = (try? c.decodeIfPresent(PosterBadgePlacement.self, forKey: .posterBadges)) ?? d.posterBadges
        ratingSources = try c.decodeIfPresent([String].self, forKey: .ratingSources) ?? d.ratingSources
        addonImages = try c.decodeIfPresent(Bool.self, forKey: .addonImages) ?? d.addonImages
    }

    /// Ob eine Bewertungsquelle gezeigt wird.
    public func shows(rating source: String) -> Bool { ratingSources.contains(source) }

    /// Quelle ein-/ausschalten (Reihenfolge der Liste ist egal, die Anzeige folgt `RatingSelection.sources`).
    public mutating func set(rating source: String, _ on: Bool) {
        ratingSources.removeAll { $0 == source }
        if on { ratingSources.append(source) }
    }
}
