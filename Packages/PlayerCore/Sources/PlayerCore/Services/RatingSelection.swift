import Foundation

/// Welle E-a: welche Bewertungen die Detailseite (und der Hero) zeigt und woher sie kommen.
/// Erst die Werte aus den Metadaten (Addon-`imdbRating` usw.), MDBList ergänzt nur fehlende Quellen.
public enum RatingSelection {
    /// Standard: IMDb, Rotten Tomatoes, Trakt.
    public static let defaultSources = ["imdb", "tomatoes", "trakt"]

    /// Wählbare Quellen in Anzeige-Reihenfolge (Schlüssel wie bei MDBList) mit Namen für die Einstellungen.
    public static let sources: [(source: String, name: String)] = [
        ("imdb", "IMDb"),
        ("tomatoes", "Rotten Tomatoes"),
        ("popcorn", "Popcorn (Publikum)"),
        ("metacritic", "Metacritic"),
        ("letterboxd", "Letterboxd"),
        ("trakt", "Trakt"),
        ("tmdb", "TMDB"),
        ("myanimelist", "MyAnimeList"),
    ]

    /// Bewertungen aus den Metadaten eines Addons. Heute nur `imdbRating` (0–10); Unlesbares oder 0 zählt nicht.
    public static func metaValues(imdbRating: String?) -> [String: Double] {
        guard let raw = imdbRating?.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."),
              let v = Double(raw), v > 0, v <= 10 else { return [:] }
        return ["imdb": v]
    }

    /// Metadaten-Werte zuerst, MDBList ergänzt fehlende Quellen; die Freigabe kommt von MDBList.
    /// nil, wenn keine Seite etwas liefert.
    public static func merge(meta: [String: Double], mdblist: ExternalRatings?) -> ExternalRatings? {
        guard !meta.isEmpty || mdblist != nil else { return nil }
        var values = mdblist?.values ?? [:]
        for (k, v) in meta { values[k] = v }
        return ExternalRatings(values: values, certification: mdblist?.certification)
    }

    /// Plaketten der gewählten Quellen in fester Reihenfolge.
    public static func badges(_ r: ExternalRatings?, selected: [String]) -> [RatingBadge] {
        guard let r else { return [] }
        let chosen = Set(selected)
        return MDBList.badges(r).filter { chosen.contains($0.source) }
    }
}
