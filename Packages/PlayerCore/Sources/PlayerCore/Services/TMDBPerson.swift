import Foundation

/// Personenseite: Stammdaten und Filmografie aus TMDB.
public struct PersonCredits: Sendable, Equatable {
    public var id: Int
    public var name: String
    public var photo: String?
    public var biography: String?
    /// z. B. "Acting", "Directing".
    public var knownFor: String?
    /// Filme und Serien, nach Beliebtheit absteigend, ohne Duplikate, höchstens 60.
    public var credits: [MetaPreview]
}

extension TMDBClient {
    /// `/person/{id}` mit `combined_credits`. Fehlt die Biografie in der Profilsprache, wird die englische nachgeholt.
    public func personCredits(id: Int) async throws -> PersonCredits {
        let data = try await http.data(from: url("/person/\(id)", ["append_to_response": "combined_credits"]))
        guard var p = Self.parsePerson(data) else { throw TMDBError.unsupported }
        if p.biography == nil, languageCode != "en" {
            let en = TMDBClient(apiKey: apiKey, language: "en-US", http: http)
            if let d = try? await http.data(from: en.url("/person/\(id)")), let e = Self.parsePerson(d) {
                p.biography = e.biography
            }
        }
        return p
    }

    static let maxPersonCredits = 60

    static func parsePerson(_ data: Data) -> PersonCredits? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = obj["id"] as? Int, let name = obj["name"] as? String else { return nil }
        func nonEmpty(_ s: Any?) -> String? {
            (s as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        }
        let cc = obj["combined_credits"] as? [String: Any]
        let entries = (cc?["cast"] as? [[String: Any]] ?? []) + (cc?["crew"] as? [[String: Any]] ?? [])
        let sorted = entries
            .filter { ($0["media_type"] as? String).map { $0 == "movie" || $0 == "tv" } ?? true }
            .enumerated()
            .sorted { a, b in
                let pa = a.element["popularity"] as? Double ?? 0, pb = b.element["popularity"] as? Double ?? 0
                return pa != pb ? pa > pb : a.offset < b.offset
            }
        var seen = Set<String>()
        var credits: [MetaPreview] = []
        for (_, r) in sorted {
            guard let m = preview(r, defaultType: .movie) else { continue }
            // Film und Serie haben bei TMDB getrennte Nummernkreise: Typ gehört zum Schlüssel.
            guard seen.insert("\(m.type):\(m.id)").inserted else { continue }
            credits.append(m)
            if credits.count == maxPersonCredits { break }
        }
        return PersonCredits(id: id, name: name, photo: nonEmpty(obj["profile_path"]).map { profileBase + $0 },
                             biography: nonEmpty(obj["biography"]), knownFor: nonEmpty(obj["known_for_department"]),
                             credits: credits)
    }
}
