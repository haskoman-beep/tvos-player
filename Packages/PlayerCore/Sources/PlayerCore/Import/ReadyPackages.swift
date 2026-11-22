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
/// `Theme.Tile.packageGradients`) und der deutsche Titel. Keine Fremdlogos, keine fremden Bild-Server.
public struct PackageTileStyle: Sendable, Equatable {
    public var symbol: String
    public var tone: Int
}

extension ReadyPackages {
    /// Anzahl der Farbverläufe in den Design-Tokens (die App hält genau so viele vor).
    public static let toneCount = 6

    /// SF Symbol je Genre (Name wie in `genres`).
    static let genreSymbols: [String: String] = [
        "Action": "flame.fill", "Komödie": "face.smiling", "Krimi": "magnifyingglass", "Drama": "theatermasks",
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

    /// TMDB-Schlüssel, an dem eine importierte Kachel als „dieselbe“ erkannt wird: Anbieter-ID bzw. Genre-IDs.
    static func matchKeys(forFolderID id: String) -> (filter: String, values: Set<String>)? {
        let streaming = "pkg.streaming-de.", genres = "pkg.genres."
        if id.hasPrefix(streaming), let n = Int(id.dropFirst(streaming.count)) {
            return ("with_watch_providers", [String(n)])
        }
        if id.hasPrefix(genres), let g = self.genres.first(where: { $0.name == String(id.dropFirst(genres.count)) }) {
            return ("with_genres", Set([g.movie, g.tv].compactMap { $0.map(String.init) }))
        }
        return nil
    }

    /// Bilder aus einer vom Nutzer importierten Collection (Nuvio/Fusion), deren Kachel genau denselben Anbieter bzw.
    /// dasselbe Genre zeigt (einziger Wert im TMDB-Filter). Kommt nur aus Nutzerdaten, nie aus dem Repo.
    public static func importedArt(forFolderID id: String, imported: [MediaCollection]) -> Folder? {
        guard let (filter, values) = matchKeys(forFolderID: id) else { return nil }
        for c in imported where !c.id.hasPrefix("pkg.") {
            for f in c.folders where f.coverImage != nil {
                let hit = f.sources.contains { s in
                    guard case .tmdbDiscover(let filters) = s.kind, let v = filters[filter] else { return false }
                    let parts = v.split(whereSeparator: { $0 == "," || $0 == "|" }).map(String.init)
                    return parts.count == 1 && values.contains(parts[0])
                }
                if hit { return f }
            }
        }
        return nil
    }

    /// Paket-Kacheln ohne eigenes Bild übernehmen Standbild, Logo und Fokus-GIF einer passenden importierten Kachel –
    /// alle drei nur zusammen und nur, wenn die Kachel noch kein Standbild hat. Ohne Treffer: unverändert (Symbol-Kachel).
    public static func withImportedArt(_ c: MediaCollection, imported: [MediaCollection]) -> MediaCollection {
        guard c.folders.contains(where: { isPackageFolder($0.id) }) else { return c }
        var c = c
        c.folders = c.folders.map { f in
            guard f.coverImage == nil, isPackageFolder(f.id), let src = importedArt(forFolderID: f.id, imported: imported) else { return f }
            var f = f
            f.coverImage = src.coverImage; f.logo = src.logo; f.focusGif = src.focusGif
            return f
        }
        return c
    }
}

/// Welle F-g Runde 2: Ergebnis von `ReadyPackages.withImportedArt` je Collection merken, bis sich Profil oder
/// Kit-Stand ändern (`Stamp`). Die Suche über alle importierten Quellen läuft so nur nach einer Änderung,
/// nicht bei jedem Lesen der Startseite.
public struct PackageArtMemo {
    public struct Stamp: Equatable, Sendable {
        public var profile: Int
        public var kit: Int
        public init(profile: Int, kit: Int) { self.profile = profile; self.kit = kit }
    }

    private var stamp: Stamp?
    private var cache: [String: MediaCollection] = [:]

    public init() {}

    /// `imported` wird nur bei einem Fehlgriff ausgewertet.
    public mutating func collection(_ c: MediaCollection, stamp: Stamp, imported: () -> [MediaCollection]) -> MediaCollection {
        if stamp != self.stamp { cache.removeAll(); self.stamp = stamp }
        if let hit = cache[c.id] { return hit }
        let out = ReadyPackages.withImportedArt(c, imported: imported())
        cache[c.id] = out
        return out
    }
}
