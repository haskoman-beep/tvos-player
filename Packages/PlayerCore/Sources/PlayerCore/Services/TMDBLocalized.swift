import Foundation

/// Deutsche (bzw. Profilsprache) Texte und Bilder aus TMDB, um Cinemeta-Daten zu ersetzen.
public struct LocalizedMeta: Sendable, Equatable {
    public var tmdbID: Int
    public var name: String?
    public var overview: String?
    public var poster: String?
    public var background: String?
    public var logo: String?
    public var genres: [String]?
    /// z. B. "FSK 12".
    public var certification: String?
}

public struct LocalizedEpisode: Sendable, Equatable {
    public var name: String?
    public var overview: String?
    public var still: String?
}

extension TMDBClient {
    /// "de-DE" → "de" (TMDB erwartet bei include_image_language nur die Sprache; Nuvio-Fehler vermeiden).
    var languageCode: String { String(language.prefix(2)) }
    var regionCode: String { language.count >= 5 ? String(language.suffix(2)) : "DE" }

    public func tmdbID(imdb: String, series: Bool) async throws -> Int? {
        let data = try await http.data(from: url("/find/\(imdb)", ["external_source": "imdb_id"]))
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return ((obj?[series ? "tv_results" : "movie_results"] as? [[String: Any]])?.first?["id"] as? Int)
    }

    /// Ein Abruf: Details + Bilder + Freigaben (append_to_response).
    public func localized(tmdbID: Int, series: Bool) async throws -> LocalizedMeta? {
        let extra = series ? "images,content_ratings" : "images,release_dates"
        let u = try url("/\(series ? "tv" : "movie")/\(tmdbID)",
                        ["append_to_response": extra, "include_image_language": "\(languageCode),en,null"])
        return Self.parseLocalized(try await http.data(from: u), lang: languageCode, region: regionCode, series: series)
    }

    public func season(tmdbID: Int, season: Int) async throws -> [Int: LocalizedEpisode] {
        let data = try await http.data(from: url("/tv/\(tmdbID)/season/\(season)"))
        return Self.parseSeason(data)
    }

    static let logoBase = "https://image.tmdb.org/t/p/w500"
    static let stillBase = "https://image.tmdb.org/t/p/w500"

    static func parseLocalized(_ data: Data, lang: String, region: String, series: Bool) -> LocalizedMeta? {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let id = o["id"] as? Int else { return nil }
        func nonEmpty(_ s: Any?) -> String? { (s as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } }
        var m = LocalizedMeta(tmdbID: id)
        m.name = nonEmpty(o["title"] ?? o["name"])
        m.overview = nonEmpty(o["overview"])
        m.poster = nonEmpty(o["poster_path"]).map { posterBase + $0 }
        m.background = nonEmpty(o["backdrop_path"]).map { backdropBase + $0 }
        m.genres = (o["genres"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        let logos = ((o["images"] as? [String: Any])?["logos"] as? [[String: Any]]) ?? []
        for want in [lang, "en", nil] as [String?] {
            if let l = logos.first(where: { ($0["iso_639_1"] as? String) == want }), let p = nonEmpty(l["file_path"]) {
                m.logo = logoBase + p; break
            }
        }
        if series {
            let r = ((o["content_ratings"] as? [String: Any])?["results"] as? [[String: Any]]) ?? []
            m.certification = r.first { ($0["iso_3166_1"] as? String) == region }.flatMap { nonEmpty($0["rating"]) }
        } else {
            let r = ((o["release_dates"] as? [String: Any])?["results"] as? [[String: Any]]) ?? []
            let dates = r.first { ($0["iso_3166_1"] as? String) == region }?["release_dates"] as? [[String: Any]] ?? []
            m.certification = dates.lazy.compactMap { nonEmpty($0["certification"]) }.first
        }
        if region == "DE", let c = m.certification, Int(c) != nil { m.certification = "FSK \(c)" }
        return m
    }

    static func parseSeason(_ data: Data) -> [Int: LocalizedEpisode] {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let eps = o["episodes"] as? [[String: Any]] else { return [:] }
        var out: [Int: LocalizedEpisode] = [:]
        for e in eps {
            guard let n = e["episode_number"] as? Int else { continue }
            let name = (e["name"] as? String).flatMap { s in
                // TMDB liefert ohne Übersetzung "Episode 3" / "Folge 3" – dann lieber Cinemeta-Titel behalten.
                s.isEmpty || s.range(of: #"^(Episode|Folge) \d+$"#, options: .regularExpression) != nil ? nil : s
            }
            out[n] = LocalizedEpisode(name: name, overview: (e["overview"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                                      still: (e["still_path"] as? String).map { stillBase + $0 })
        }
        return out
    }
}

extension MetaDetail {
    /// Übersetzte Felder übernehmen, wo vorhanden; Cinemeta bleibt Rückfall.
    public func applying(_ l: LocalizedMeta) -> MetaDetail {
        var m = self
        m.name = l.name ?? name
        m.description = l.overview ?? description
        m.poster = l.poster ?? poster
        m.background = background ?? l.background
        m.logo = l.logo ?? logo
        if let g = l.genres, !g.isEmpty { m.genres = g }
        return m
    }

    public func applying(season: Int, episodes: [Int: LocalizedEpisode]) -> MetaDetail {
        var m = self
        m.videos = videos?.map { v in
            guard v.season == season, let e = v.episode, let l = episodes[e] else { return v }
            var x = v
            if let n = l.name { x.name = n; x.title = n }
            x.overview = l.overview ?? v.overview
            x.thumbnail = v.thumbnail ?? l.still
            return x
        }
        return m
    }
}
