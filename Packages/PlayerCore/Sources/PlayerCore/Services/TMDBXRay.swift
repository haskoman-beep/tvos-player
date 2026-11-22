import Foundation

// Wave X3: TMDB calls for the X-Ray gallery. Full cast lists (no 20-person cut as on the detail page),
// episode credits with guest stars, and several portraits per person. Uses the client's key like every other
// TMDB call; the key is entered at runtime and never part of the repo.

/// One portrait of `/person/{id}/images`.
public struct TMDBProfileImage: Sendable, Equatable {
    public var filePath: String
    public var width: Int?
    public var height: Int?
    public var voteAverage: Double
    public var voteCount: Int

    public init(filePath: String, width: Int? = nil, height: Int? = nil, voteAverage: Double = 0, voteCount: Int = 0) {
        self.filePath = filePath; self.width = width; self.height = height
        self.voteAverage = voteAverage; self.voteCount = voteCount
    }
}

extension TMDBClient {
    /// Portrait size for the gallery: w185 is too small for a 112-pixel crop after detection.
    public static let galleryProfileBase = "https://image.tmdb.org/t/p/h632"

    public static func galleryImageURL(_ filePath: String) -> URL? { URL(string: galleryProfileBase + filePath) }

    /// `/movie/{id}/credits`: the whole cast, in billing order.
    public func movieCast(tmdbID: Int) async throws -> [XRayCastEntry] {
        Self.parseCast(try await http.data(from: url("/movie/\(tmdbID)/credits")), keys: ["cast"])
    }

    /// `/tv/{id}/aggregate_credits`: everyone who played in the series, in billing order.
    public func seriesCast(tmdbID: Int) async throws -> [XRayCastEntry] {
        Self.parseCast(try await http.data(from: url("/tv/\(tmdbID)/aggregate_credits")), keys: ["cast"])
    }

    /// `/tv/{id}/season/{s}/episode/{e}/credits`: the episode's cast, then its `guest_stars`.
    public func episodeCast(tvID: Int, season: Int, episode: Int) async throws -> [XRayCastEntry] {
        let data = try await http.data(from: url("/tv/\(tvID)/season/\(season)/episode/\(episode)/credits"))
        return Self.parseCast(data, keys: ["cast", "guest_stars"])
    }

    /// The candidates of a title. Film: its cast. Episode: the episode cast and guests first, then the rest of
    /// the series cast (flashbacks, credits missing on the episode). If the episode credits fail (numbering
    /// differs, 404), the series cast alone is used. People appear once; `order` is renumbered 0…n−1.
    public func xrayCast(for key: XRayTitleKey) async throws -> [XRayCastEntry] {
        switch key {
        case .movie(let id):
            return Self.renumbered(try await movieCast(tmdbID: id))
        case .episode(let tv, let s, let e):
            let episode = (try? await episodeCast(tvID: tv, season: s, episode: e)) ?? []
            let series: [XRayCastEntry]
            do { series = try await seriesCast(tmdbID: tv) } catch {
                if episode.isEmpty { throw error }
                series = []
            }
            return Self.mergedCast(episode: episode, series: series)
        }
    }

    /// `/person/{id}/images`: the portraits (`profiles`), best rated first.
    public func personImages(id: Int) async throws -> [TMDBProfileImage] {
        Self.parseProfiles(try await http.data(from: url("/person/\(id)/images")))
    }

    static func parseCast(_ data: Data, keys: [String]) -> [XRayCastEntry] {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        func nonEmpty(_ s: Any?) -> String? { (s as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } }
        var out: [XRayCastEntry] = []
        var seen = Set<Int>()
        for key in keys {
            let guest = key == "guest_stars"
            let rows = ((o[key] as? [[String: Any]]) ?? []).enumerated().sorted { a, b in
                let oa = a.element["order"] as? Int ?? Int.max, ob = b.element["order"] as? Int ?? Int.max
                return oa != ob ? oa < ob : a.offset < b.offset
            }
            for (_, c) in rows {
                guard let id = c["id"] as? Int, let name = nonEmpty(c["name"]), seen.insert(id).inserted else { continue }
                let role = nonEmpty(c["character"]) ?? ((c["roles"] as? [[String: Any]])?.lazy.compactMap { nonEmpty($0["character"]) }.first)
                out.append(XRayCastEntry(personID: id, name: name, role: role, profilePath: nonEmpty(c["profile_path"]),
                                         order: out.count, guest: guest))
            }
        }
        return out
    }

    static func mergedCast(episode: [XRayCastEntry], series: [XRayCastEntry]) -> [XRayCastEntry] {
        var seen = Set<Int>()
        return renumbered((episode + series).filter { seen.insert($0.personID).inserted })
    }

    static func renumbered(_ cast: [XRayCastEntry]) -> [XRayCastEntry] {
        cast.enumerated().map { i, c in var x = c; x.order = i; return x }
    }

    static func parseProfiles(_ data: Data) -> [TMDBProfileImage] {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let rows = o["profiles"] as? [[String: Any]] else { return [] }
        let images = rows.compactMap { r -> TMDBProfileImage? in
            guard let p = r["file_path"] as? String, !p.isEmpty else { return nil }
            return TMDBProfileImage(filePath: p, width: r["width"] as? Int, height: r["height"] as? Int,
                                    voteAverage: (r["vote_average"] as? Double) ?? Double(r["vote_average"] as? Int ?? 0),
                                    voteCount: r["vote_count"] as? Int ?? 0)
        }
        return images.enumerated().sorted { a, b in
            let x = a.element, y = b.element
            if x.voteAverage != y.voteAverage { return x.voteAverage > y.voteAverage }
            if x.voteCount != y.voteCount { return x.voteCount > y.voteCount }
            return a.offset < b.offset
        }.map(\.element)
    }
}
