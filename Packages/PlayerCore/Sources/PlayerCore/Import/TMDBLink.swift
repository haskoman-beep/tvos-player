import Foundation

/// Macht aus einem eingefügten TMDB-Link (oder "list:123") eine Liste für die Startseite.
public enum TMDBLink {
    public static func source(from text: String, title: String? = nil) -> CatalogSource? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = URL(string: t)?.host?.contains("themoviedb.org") == true ? (URL(string: t)?.path ?? "") : "/" + t.replacingOccurrences(of: ":", with: "/")
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        // "/list/8123-name" → id 8123
        let id = String(parts[1].prefix { $0.isNumber })
        guard !id.isEmpty else { return nil }
        let name = title ?? parts[1].drop { $0.isNumber || $0 == "-" }.replacingOccurrences(of: "-", with: " ").capitalized
        switch parts[0] {
        case "list": return CatalogSource(id: "tmdb.list.\(id)", title: name.isEmpty ? "TMDB-Liste \(id)" : name, kind: .tmdbList(id: id), mediaType: .both)
        case "collection": return CatalogSource(id: "tmdb.collection.\(id)", title: name.isEmpty ? "Filmreihe \(id)" : name, kind: .tmdbCollection(id: id), mediaType: .movie)
        case "company": return CatalogSource(id: "tmdb.company.\(id)", title: name.isEmpty ? "Studio \(id)" : name, kind: .tmdbCompany(id: id), mediaType: .movie, sortBy: "popularity.desc")
        default: return nil
        }
    }
}
