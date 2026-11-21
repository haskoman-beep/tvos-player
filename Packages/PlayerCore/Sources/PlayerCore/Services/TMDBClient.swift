import Foundation

public enum TMDBError: Error, Equatable { case missingKey, unsupported, badURL }

/// TMDB v3 mit API-Key (Laufzeit-Eingabe, nicht im Repo).
public struct TMDBClient: Sendable {
    public let apiKey: String
    public let language: String
    let http: HTTPFetching
    static let base = "https://api.themoviedb.org/3"
    public static let posterBase = "https://image.tmdb.org/t/p/w500"
    public static let backdropBase = "https://image.tmdb.org/t/p/w1280"

    public init(apiKey: String, language: String = "de-DE", http: HTTPFetching = URLSessionFetcher()) {
        self.apiKey = apiKey; self.language = language; self.http = http
    }

    public func url(_ path: String, _ query: [String: String] = [:]) throws -> URL {
        guard !apiKey.isEmpty else { throw TMDBError.missingKey }
        guard var c = URLComponents(string: Self.base + path) else { throw TMDBError.badURL }
        var q = query; q["api_key"] = apiKey; q["language"] = language
        c.queryItems = q.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        // "|" und "," in Filtern sicher kodieren.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "|", with: "%7C")
        guard let u = c.url else { throw TMDBError.badURL }
        return u
    }

    public func items(for source: CatalogSource, page: Int = 1) async throws -> [MetaPreview] {
        switch source.kind {
        case .tmdbDiscover(let filters):
            let types: [MediaType] = source.mediaType == .both ? [.movie, .series] : [source.mediaType]
            var out: [MetaPreview] = []
            for t in types {
                var q = filters; q["page"] = String(page)
                out += try await results(url("/discover/\(t == .movie ? "movie" : "tv")", q), defaultType: t)
            }
            return out
        case .tmdbList(let id):
            return try await results(url("/list/\(id)", ["page": String(page)]), defaultType: source.mediaType, key: "items")
        case .tmdbCompany(let id):
            var q = ["with_companies": id, "page": String(page)]
            if let s = source.sortBy { q["sort_by"] = s }
            let t: MediaType = source.mediaType == .series ? .series : .movie
            return try await results(url("/discover/\(t == .movie ? "movie" : "tv")", q), defaultType: t)
        case .tmdbCollection(let id):
            guard page == 1 else { return [] }
            return try await results(url("/collection/\(id)"), defaultType: .movie, key: "parts")
        default:
            throw TMDBError.unsupported
        }
    }

    /// Suche über Filme und Serien (Personen werden ausgelassen).
    public func search(_ query: String, page: Int = 1) async throws -> [MetaPreview] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return try await results(url("/search/multi", ["query": q, "page": String(page), "include_adult": "false"]),
                                 defaultType: .movie, skipPeople: true)
    }

    public func imdbID(tmdbID: Int, type: MediaType) async throws -> String? {
        let u = try url("/\(type == .series ? "tv" : "movie")/\(tmdbID)/external_ids")
        let r = try JSONDecoder().decode(ExternalIDs.self, from: try await http.data(from: u))
        return r.imdb_id
    }

    func results(_ u: URL, defaultType: MediaType, key: String = "results", skipPeople: Bool = false) async throws -> [MetaPreview] {
        let data = try await http.data(from: u)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let arr = obj?[key] as? [[String: Any]] ?? []
        return arr.compactMap { r in
            guard let id = r["id"] as? Int else { return nil }
            if skipPeople, let t = r["media_type"] as? String, t != "movie" && t != "tv" { return nil }
            let mt: MediaType = switch r["media_type"] as? String {
            case "tv": .series
            case "movie": .movie
            default: defaultType == .series ? .series : .movie
            }
            guard let name = (r["title"] ?? r["name"]) as? String else { return nil }
            let date = (r["release_date"] ?? r["first_air_date"]) as? String
            return MetaPreview(id: "tmdb:\(id)", type: mt == .series ? "series" : "movie", name: name,
                               poster: (r["poster_path"] as? String).map { Self.posterBase + $0 },
                               background: (r["backdrop_path"] as? String).map { Self.backdropBase + $0 },
                               description: r["overview"] as? String,
                               releaseInfo: date.map { String($0.prefix(4)) },
                               imdbRating: (r["vote_average"] as? Double).map { String(format: "%.1f", $0) })
        }
    }

    struct ExternalIDs: Decodable { var imdb_id: String? }
}
