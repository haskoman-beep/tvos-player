import Foundation

/// Externe Bewertungen eines Titels (MDBList: ein Aufruf liefert IMDb, RT, Metacritic, Letterboxd, Trakt, TMDB …).
public struct ExternalRatings: Codable, Sendable, Equatable {
    /// Quelle → Wert in der Skala der Quelle (imdb 0–10, tomatoes 0–100, letterboxd 0–5 …).
    public var values: [String: Double]
    /// US-Freigabe laut MDBList, z. B. "PG-13".
    public var certification: String?
    public init(values: [String: Double] = [:], certification: String? = nil) {
        self.values = values; self.certification = certification
    }
}

/// Eine Plakette in der Infozeile.
public struct RatingBadge: Sendable, Equatable, Identifiable {
    public var source: String
    public var label: String
    public var text: String
    /// 0–100, für die Farbe (grün/gelb/rot).
    public var score: Double
    public var id: String { source }
}

public enum MDBList {
    public enum TitleResult: Equatable, Sendable { case ratings(ExternalRatings), notFound, limitReached, failed }

    /// Quelle → (Anzeigename, Skalenmaximum, Format).
    static let scales: [(source: String, label: String, max: Double, percent: Bool)] = [
        ("imdb", "IMDb", 10, false),
        ("tomatoes", "🍅", 100, true),
        ("popcorn", "🍿", 100, true),
        ("metacritic", "Metacritic", 100, false),
        ("letterboxd", "Letterboxd", 5, false),
        ("trakt", "Trakt", 100, true),
        ("tmdb", "TMDB", 100, true),
        ("myanimelist", "MAL", 10, false),
    ]

    public static func url(imdb: String, series: Bool, apiKey: String) -> URL? {
        var c = URLComponents(string: "https://api.mdblist.com/imdb/\(series ? "show" : "movie")/\(imdb)")
        c?.queryItems = [URLQueryItem(name: "apikey", value: apiKey)]
        return c?.url
    }

    public static func parse(status: Int, data: Data) -> TitleResult {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let err = (obj?["error"] as? String)?.lowercased() ?? ""
        if status == 429 || err.contains("limit") { return .limitReached }
        if status == 404 || err.contains("not found") { return .notFound }
        guard (200..<300).contains(status), let obj, err.isEmpty else { return .failed }
        var values: [String: Double] = [:]
        for r in obj["ratings"] as? [[String: Any]] ?? [] {
            guard let src = r["source"] as? String, values[src] == nil,
                  let scale = scales.first(where: { $0.source == src }),
                  let v = (r["value"] as? NSNumber)?.doubleValue, v > 0, v <= scale.max else { continue }
            values[src] = v
        }
        let cert = (obj["certification"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return .ratings(ExternalRatings(values: values, certification: cert))
    }

    /// Plaketten in fester Reihenfolge.
    public static func badges(_ r: ExternalRatings) -> [RatingBadge] {
        scales.compactMap { s in
            guard let v = r.values[s.source] else { return nil }
            let text = s.percent ? "\(Int(v.rounded()))%" : (s.max == 100 ? "\(Int(v.rounded()))" : String(format: "%.1f", v))
            return RatingBadge(source: s.source, label: s.label, text: text, score: v / s.max * 100)
        }
    }

    /// Gefunden 24 h, „nicht gefunden“ 6 h gültig.
    public static func isFresh(storedAt: Date, found: Bool, now: Date = Date()) -> Bool {
        now.timeIntervalSince(storedAt) < (found ? 24 : 6) * 3600
    }
}

/// Technik-Plaketten für die Detailseite: das Beste, was die verfügbaren (nicht sicher ungecachten) Quellen bieten.
public enum TechBadges {
    public static func summary(_ streams: [StreamItem]) -> [String] {
        let traits = streams.map(StreamTraits.parse)
        let usable = traits.filter { $0.cached != false }
        let t = usable.isEmpty ? traits : usable
        var out: [String] = []
        if t.contains(where: { $0.resolution == "2160p" }) { out.append("4K") }
        else if t.contains(where: { $0.resolution == "1080p" }) { out.append("HD") }
        if t.contains(where: { $0.hdr.contains("DV") }) { out.append("Dolby Vision") }
        if t.contains(where: { $0.hdr.contains("HDR10+") }) { out.append("HDR10+") }
        else if t.contains(where: { !$0.hdr.filter { $0 != "DV" }.isEmpty }) { out.append("HDR") }
        if t.contains(where: { $0.audio.contains("Atmos") }) { out.append("Dolby Atmos") }
        if t.contains(where: { $0.channels == "7.1" }) { out.append("7.1") }
        else if t.contains(where: { $0.channels == "5.1" }) { out.append("5.1") }
        return out
    }
}
