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
    public var cast: [CastMember] = []
    /// Regie (Film) bzw. Idee (Serie).
    public var creators: [String] = []
    public var writers: [String] = []
    public var studios: [String] = []
    public var countries: [String] = []
    public var originalTitle: String?
    public var releaseDate: String?
    public var budget: Int?
    public var revenue: Int?
    public var status: String?
    public var seasons: Int?
    public var episodes: Int?
    public var tagline: String?
    /// YouTube-Schlüssel des besten Trailers (Profilsprache zuerst).
    public var trailerYouTube: String?
    /// Sprache (`iso_639_1`) dieses Trailers, falls TMDB sie angibt.
    public var trailerYouTubeLanguage: String?
    public var recommendations: [MetaPreview] = []
}

public struct CastMember: Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String
    public var role: String?
    public var photo: String?
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
        let extra = (series ? "images,content_ratings,aggregate_credits" : "images,release_dates,credits") + ",videos,recommendations"
        let u = try url("/\(series ? "tv" : "movie")/\(tmdbID)",
                        ["append_to_response": extra, "include_image_language": "\(languageCode),en,null",
                         "include_video_language": "\(languageCode),en,null"])
        return Self.parseLocalized(try await http.data(from: u), lang: languageCode, region: regionCode, series: series)
    }

    public func season(tmdbID: Int, season: Int) async throws -> [Int: LocalizedEpisode] {
        let data = try await http.data(from: url("/tv/\(tmdbID)/season/\(season)"))
        return Self.parseSeason(data)
    }

    static let logoBase = "https://image.tmdb.org/t/p/w500"
    static let stillBase = "https://image.tmdb.org/t/p/w500"
    static let profileBase = "https://image.tmdb.org/t/p/w185"

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

        let credits = (o[series ? "aggregate_credits" : "credits"] as? [String: Any]) ?? [:]
        m.cast = ((credits["cast"] as? [[String: Any]]) ?? []).prefix(20).compactMap { c in
            guard let id = c["id"] as? Int, let name = nonEmpty(c["name"]) else { return nil }
            let role = nonEmpty(c["character"]) ?? ((c["roles"] as? [[String: Any]])?.first.flatMap { nonEmpty($0["character"]) })
            return CastMember(id: id, name: name, role: role, photo: nonEmpty(c["profile_path"]).map { profileBase + $0 })
        }
        let crew = (credits["crew"] as? [[String: Any]]) ?? []
        if series {
            m.creators = ((o["created_by"] as? [[String: Any]]) ?? []).compactMap { nonEmpty($0["name"]) }
            m.studios = ((o["networks"] as? [[String: Any]]) ?? []).compactMap { nonEmpty($0["name"]) }
                + ((o["production_companies"] as? [[String: Any]]) ?? []).prefix(2).compactMap { nonEmpty($0["name"]) }
            m.seasons = o["number_of_seasons"] as? Int
            m.episodes = o["number_of_episodes"] as? Int
            m.releaseDate = nonEmpty(o["first_air_date"])
            m.originalTitle = nonEmpty(o["original_name"])
        } else {
            m.creators = crew.filter { ($0["job"] as? String) == "Director" }.compactMap { nonEmpty($0["name"]) }
            m.writers = Array(Set(crew.filter { ["Screenplay", "Writer"].contains($0["job"] as? String ?? "") }.compactMap { nonEmpty($0["name"]) })).sorted()
            m.studios = ((o["production_companies"] as? [[String: Any]]) ?? []).prefix(3).compactMap { nonEmpty($0["name"]) }
            m.budget = (o["budget"] as? Int).flatMap { $0 > 0 ? $0 : nil }
            m.revenue = (o["revenue"] as? Int).flatMap { $0 > 0 ? $0 : nil }
            m.releaseDate = nonEmpty(o["release_date"])
            m.originalTitle = nonEmpty(o["original_title"])
        }
        m.countries = ((o["production_countries"] as? [[String: Any]]) ?? []).compactMap { nonEmpty($0["name"]) }
        m.status = nonEmpty(o["status"])
        m.tagline = nonEmpty(o["tagline"])
        if m.originalTitle == m.name { m.originalTitle = nil }

        let videos = (((o["videos"] as? [String: Any])?["results"] as? [[String: Any]]) ?? [])
            .filter { ($0["site"] as? String) == "YouTube" && nonEmpty($0["key"]) != nil }
        let ordered = videos.sorted { a, b in
            func score(_ v: [String: Any]) -> Int {
                let type = v["type"] as? String ?? ""
                return (type == "Trailer" ? 0 : type == "Teaser" ? 10 : 20) + ((v["iso_639_1"] as? String) == lang ? 0 : 3)
                    + ((v["official"] as? Bool) == true ? 0 : 1)
            }
            return score(a) < score(b)
        }
        m.trailerYouTube = ordered.first.flatMap { nonEmpty($0["key"]) }
        m.trailerYouTubeLanguage = ordered.first.flatMap { nonEmpty($0["iso_639_1"]) }

        let recs = (((o["recommendations"] as? [String: Any])?["results"] as? [[String: Any]]) ?? [])
        m.recommendations = recs.prefix(20).compactMap { preview($0, defaultType: series ? .series : .movie) }
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

// MARK: Kalender (Task 5)

extension TMDBClient {
    /// Kommende Folgen einer Serie: letzte und nächste Folge aus `/tv/{id}`, dazu die Folgen der laufenden Staffel.
    /// Die Staffel wird nur abgerufen, wenn die nächste Folge bis `through` erscheint – oder, ohne nächste Folge,
    /// wenn die letzte ab `from` lief (Daten YYYY-MM-DD).
    /// `seriesID` ist "tmdb:{id}"; die App ersetzt sie durch die ID aus Weiterschauen/Merkliste.
    public func nextEpisodes(tmdbID: Int, from: String? = nil, through: String? = nil) async throws -> [UpcomingEpisode] {
        let base = Self.parseNextEpisodes(try await http.data(from: url("/tv/\(tmdbID)")))
        let episodes = base.map(\.episode)
        let anchor: UpcomingEpisode?
        if let next = base.first(where: { $0.isNext })?.episode {
            anchor = next.airDate <= (through ?? next.airDate) ? next : nil
        } else if let last = base.first(where: { !$0.isNext })?.episode {
            anchor = from.map { last.airDate >= $0 } == true ? last : nil
        } else { anchor = nil }
        guard let anchor else { return episodes }
        let data = try await http.data(from: url("/tv/\(tmdbID)/season/\(anchor.season)"))
        let season = Self.parseSeasonEpisodes(data, like: anchor)
        var seen = Set<String>(), out: [UpcomingEpisode] = []
        for e in episodes + season where seen.insert(e.id).inserted { out.append(e) }
        return out
    }

    /// `last_episode_to_air` und `next_episode_to_air` einer Serie (`isNext` markiert die nächste).
    static func parseNextEpisodes(_ data: Data) -> [(episode: UpcomingEpisode, isNext: Bool)] {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let id = o["id"] as? Int,
              let name = (o["name"] ?? o["title"]) as? String else { return [] }
        let template = UpcomingEpisode(seriesID: "tmdb:\(id)", seriesName: name,
                                       poster: (o["poster_path"] as? String).map { posterBase + $0 },
                                       season: 0, episode: 0, airDate: "",
                                       background: (o["backdrop_path"] as? String).map { backdropBase + $0 })
        return [("last_episode_to_air", false), ("next_episode_to_air", true)].compactMap { key, isNext in
            guard let e = o[key] as? [String: Any], let ep = episode(e, like: template) else { return nil }
            return (ep, isNext)
        }
    }

    /// Folgen einer Staffel (`/tv/{id}/season/{n}`) mit Ausstrahlungsdatum.
    static func parseSeasonEpisodes(_ data: Data, like template: UpcomingEpisode) -> [UpcomingEpisode] {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let eps = o["episodes"] as? [[String: Any]] else { return [] }
        return eps.compactMap { episode($0, like: template) }
    }

    private static func episode(_ e: [String: Any], like t: UpcomingEpisode) -> UpcomingEpisode? {
        guard let s = e["season_number"] as? Int, let n = e["episode_number"] as? Int,
              let date = e["air_date"] as? String, date.count >= 10 else { return nil }
        // Ohne Übersetzung liefert TMDB "Episode 3" / "Folge 3" – dann ohne Titel.
        let title = (e["name"] as? String).flatMap { s in
            s.isEmpty || s.range(of: #"^(Episode|Folge) \d+$"#, options: .regularExpression) != nil ? nil : s
        }
        var x = t
        x.season = s; x.episode = n; x.title = title; x.airDate = String(date.prefix(10))
        x.still = (e["still_path"] as? String).map { stillBase + $0 }
        return x
    }
}
