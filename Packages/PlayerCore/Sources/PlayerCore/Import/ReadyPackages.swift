import Foundation

/// Fertige Pakete für die Plus-Auswahl (Spec §7 P2). Inhalte kommen live aus TMDB-Discover (Region DE).
public enum ReadyPackages {
    public struct Provider: Sendable { public let name: String; public let tmdbID: Int }

    /// TMDB-Watch-Provider-IDs (Region DE).
    public static let providersDE: [Provider] = [
        .init(name: "Netflix", tmdbID: 8), .init(name: "Prime Video", tmdbID: 9),
        .init(name: "Disney+", tmdbID: 337), .init(name: "Apple TV+", tmdbID: 350),
        .init(name: "WOW", tmdbID: 30), .init(name: "Paramount+", tmdbID: 531),
        .init(name: "RTL+", tmdbID: 298), .init(name: "Joyn", tmdbID: 304),
    ]

    /// (Name, Film-Genre-ID, Serien-Genre-ID) – TMDB nutzt für Filme und Serien teils andere IDs.
    public static let genres: [(name: String, movie: Int?, tv: Int?)] = [
        ("Action", 28, 10759), ("Komödie", 35, 35), ("Krimi", 80, 80), ("Drama", 18, 18),
        ("Science-Fiction", 878, 10765), ("Horror", 27, nil), ("Thriller", 53, nil),
        ("Animation", 16, 16), ("Dokumentation", 99, 99), ("Familie", 10751, 10751),
    ]

    public static var all: [MediaCollection] { [streamingDE, genreCollection] }

    public static var streamingDE: MediaCollection {
        MediaCollection(id: "pkg.streaming-de", title: "Streaming-Dienste", folders: providersDE.map { p in
            let base = ["with_watch_providers": String(p.tmdbID), "watch_region": "DE",
                        "with_watch_monetization_types": "flatrate"]
            func src(_ suffix: String, _ title: String, _ t: MediaType, _ extra: [String: String]) -> CatalogSource {
                CatalogSource(id: "pkg.streaming-de.\(p.tmdbID).\(suffix)", title: "\(p.name) · \(title)",
                              kind: .tmdbDiscover(filters: base.merging(extra) { $1 }), mediaType: t)
            }
            return Folder(id: "pkg.streaming-de.\(p.tmdbID)", title: p.name, sources: [
                src("popular-movies", "Beliebte Filme", .movie, ["sort_by": "popularity.desc"]),
                src("popular-series", "Beliebte Serien", .series, ["sort_by": "popularity.desc"]),
                src("new-movies", "Neue Filme", .movie, ["sort_by": "primary_release_date.desc", "vote_count.gte": "20"]),
                src("new-series", "Neue Serien", .series, ["sort_by": "first_air_date.desc", "vote_count.gte": "10"]),
            ])
        })
    }

    public static var genreCollection: MediaCollection {
        MediaCollection(id: "pkg.genres", title: "Genres", folders: genres.map { g in
            var sources: [CatalogSource] = []
            if let m = g.movie {
                sources.append(CatalogSource(id: "pkg.genres.\(g.name).movie", title: "\(g.name) · Filme",
                    kind: .tmdbDiscover(filters: ["with_genres": String(m), "sort_by": "popularity.desc", "vote_count.gte": "100"]), mediaType: .movie))
            }
            if let t = g.tv {
                sources.append(CatalogSource(id: "pkg.genres.\(g.name).series", title: "\(g.name) · Serien",
                    kind: .tmdbDiscover(filters: ["with_genres": String(t), "sort_by": "popularity.desc", "vote_count.gte": "50"]), mediaType: .series))
            }
            return Folder(id: "pkg.genres.\(g.name)", title: g.name, sources: sources)
        })
    }
}

// MARK: Kacheln der Pakete (Welle F-g Runde 1)

/// Eigene Gestaltung einer Paket-Kachel ohne Bild aus dem Netz: SF Symbol, Farbverlauf (Index in die Design-Tokens
/// `Theme.Tile.packageGradients`) und der deutsche Titel. Ersatz, solange kein Bild zur Laufzeit vorliegt
/// (Welle F-l, `PackageArt.swift`); im Repo liegen keine Fremdlogos.
public struct PackageTileStyle: Sendable, Equatable {
    public var symbol: String
    public var tone: Int
}

extension ReadyPackages {
    /// Anzahl der Farbverläufe in den Design-Tokens (die App hält genau so viele vor).
    public static let toneCount = 6

    /// SF Symbol je Genre (Name wie in `genres`).
    static let genreSymbols: [String: String] = [
        "Action": "flame.fill", "Komödie": "face.smiling", "Krimi": "touchid", "Drama": "theatermasks",
        "Science-Fiction": "sparkles", "Horror": "moon.stars", "Thriller": "bolt.fill", "Animation": "paintpalette",
        "Dokumentation": "book", "Familie": "figure.2.and.child.holdinghands",
    ]

    /// Gestaltung einer Paket-Kachel nach ihrer ID (`pkg.streaming-de.<tmdb>` bzw. `pkg.genres.<name>`), sonst nil.
    /// Streaming-Dienste: neutrales Symbol, der Name steht als Text darunter.
    public static func tileStyle(forFolderID id: String) -> PackageTileStyle? {
        let streaming = "pkg.streaming-de.", genres = "pkg.genres."
        if id.hasPrefix(streaming), let n = Int(id.dropFirst(streaming.count)),
           let i = providersDE.firstIndex(where: { $0.tmdbID == n }) {
            return PackageTileStyle(symbol: "play.tv", tone: i % toneCount)
        }
        if id.hasPrefix(genres) {
            let name = String(id.dropFirst(genres.count))
            guard let i = self.genres.firstIndex(where: { $0.name == name }), let sym = genreSymbols[name] else { return nil }
            return PackageTileStyle(symbol: sym, tone: i % toneCount)
        }
        return nil
    }

    /// Ist das eine Kachel eines fertigen Pakets?
    public static func isPackageFolder(_ id: String) -> Bool { id.hasPrefix("pkg.streaming-de.") || id.hasPrefix("pkg.genres.") }
}
