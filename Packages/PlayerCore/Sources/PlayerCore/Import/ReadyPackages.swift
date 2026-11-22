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
            return withArtwork(Folder(id: "pkg.streaming-de.\(p.tmdbID)", title: p.name, sources: [
                src("popular-movies", "Beliebte Filme", .movie, ["sort_by": "popularity.desc"]),
                src("popular-series", "Beliebte Serien", .series, ["sort_by": "popularity.desc"]),
                src("new-movies", "Neue Filme", .movie, ["sort_by": "primary_release_date.desc", "vote_count.gte": "20"]),
                src("new-series", "Neue Serien", .series, ["sort_by": "first_air_date.desc", "vote_count.gte": "10"]),
            ]))
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
            return withArtwork(Folder(id: "pkg.genres.\(g.name)", title: g.name, sources: sources))
        })
    }
}

// MARK: Kachelbilder (Welle F-g)

/// Bilder einer Paket-Kachel: Standbild, Logo (Stil „Logos“) und bewegtes Fokusbild.
public struct ReadyPackageArt: Sendable, Equatable {
    public var cover: String
    public var logo: String?
    public var focusGif: String?
}

extension ReadyPackages {
    /// Öffentlicher Bild-Server der Kachelbilder (Standbild `.webp`, Fokus-GIF `.focus.gif`, Logo `.logo.webp`).
    static let artBase = "https://cdn.xperience-app.com/covers/"

    /// Kennung des Bildes je Anbieter (TMDB-ID); WOW, RTL+ und Joyn hat der Server nicht: dort bleibt der Titel.
    static let providerArt: [Int: String] = [
        8: "netflix", 9: "prime_video", 337: "disney_plus", 350: "apple_tv_plus", 531: "paramount_plus",
    ]

    /// Kennung des Bildes je Genre (Name wie in `genres`). Genre-Bilder haben kein Fokus-GIF.
    static let genreArt: [String: String] = [
        "Action": "action", "Komödie": "comedy", "Krimi": "crime", "Drama": "drama", "Science-Fiction": "sci_fi",
        "Horror": "horror", "Thriller": "thrillers", "Animation": "animated", "Dokumentation": "documentaries",
        "Familie": "family",
    ]

    /// Bilder einer Paket-Kachel nach ihrer ID (`pkg.streaming-de.<tmdb>` bzw. `pkg.genres.<name>`), sonst nil.
    public static func art(forFolderID id: String) -> ReadyPackageArt? {
        let streaming = "pkg.streaming-de.", genres = "pkg.genres."
        if id.hasPrefix(streaming), let n = Int(id.dropFirst(streaming.count)), let key = providerArt[n] {
            return ReadyPackageArt(cover: artBase + "default/streaming_services.\(key).webp?v=7",
                                   logo: artBase + "logomark/streaming_services.\(key).logo.webp?v=10",
                                   focusGif: artBase + "default/streaming_services.\(key).focus.gif?v=7")
        }
        if id.hasPrefix(genres), let key = genreArt[String(id.dropFirst(genres.count))] {
            return ReadyPackageArt(cover: artBase + "default/genres.\(key).webp?v=7")
        }
        return nil
    }

    /// Fehlende Bilder einer Paket-Kachel ergänzen; Eigenes (vom Nutzer oder Import) bleibt.
    /// Mit Bild steht der Name schon im Bild: Titel aus, solange der Nutzer nichts anderes gewählt hat.
    public static func withArtwork(_ f: Folder) -> Folder {
        guard let art = art(forFolderID: f.id) else { return f }
        var f = f
        if f.coverImage == nil { f.coverImage = art.cover; f.hideTitle = f.hideTitle ?? true }
        f.logo = f.logo ?? art.logo
        f.focusGif = f.focusGif ?? art.focusGif
        return f
    }

    /// Wie `withArtwork(_:)` für eine ganze Collection. Pakete, die vor Welle F-g als eigene Collection ins Profil
    /// kopiert wurden, haben keine Bilder gespeichert; sie bekommen sie hier beim Lesen.
    public static func withArtwork(_ c: MediaCollection) -> MediaCollection {
        guard c.folders.contains(where: { art(forFolderID: $0.id) != nil }) else { return c }
        var c = c
        c.folders = c.folders.map { withArtwork($0) }
        return c
    }
}
