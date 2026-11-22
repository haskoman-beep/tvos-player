import Foundation

public enum MediaType: String, Codable, Sendable, Hashable, CaseIterable {
    case movie, series, both
}

/// Woher eine Titelliste kommt.
public enum SourceKind: Codable, Sendable, Hashable {
    case tmdbDiscover(filters: [String: String])
    case tmdbList(id: String)
    case tmdbCompany(id: String)
    case tmdbCollection(id: String)
    case trakt(user: String?, list: String)
    case addon(addonId: String, catalogId: String, type: String)
    case continueWatching
    case watchlist
    /// Heute neu erschienene Folgen (Kalender).
    case upcoming
}

/// Eine Titelliste (eine Startseiten-Reihe vom Typ "Liste").
public struct CatalogSource: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var kind: SourceKind
    public var mediaType: MediaType
    /// TMDB-Sortierung (z. B. `popularity.desc`); nil = Reihenfolge der Quelle.
    public var sortBy: String?
    /// Höchstens so viele Einträge zeigen (Fusion `limit`); nil = alle.
    public var limit: Int?

    public init(id: String, title: String, kind: SourceKind, mediaType: MediaType, sortBy: String? = nil, limit: Int? = nil) {
        self.id = id; self.title = title; self.kind = kind; self.mediaType = mediaType; self.sortBy = sortBy
        self.limit = limit.flatMap { $0 > 0 ? $0 : nil }
    }

    /// Liste auf `limit` gekürzt.
    public func applyingLimit<T>(_ items: [T]) -> [T] {
        guard let limit, limit > 0, items.count > limit else { return items }
        return Array(items.prefix(limit))
    }

    public static let continueWatching = CatalogSource(id: "builtin.continue", title: "Weiterschauen", kind: .continueWatching, mediaType: .both)
    public static let watchlist = CatalogSource(id: "builtin.watchlist", title: "Merkliste", kind: .watchlist, mediaType: .both)
    public static let upcoming = CatalogSource(id: "builtin.upcoming", title: "Heute neu", kind: .upcoming, mediaType: .series)
    /// Trakt-Empfehlungen des angemeldeten Nutzers (ohne Merkliste), je 20.
    public static let traktRecommendedMovies = CatalogSource(id: "builtin.trakt.recommended.movies", title: "Trakt-Empfehlungen · Filme",
                                                             kind: .trakt(user: nil, list: "recommendations/movies"), mediaType: .movie)
    public static let traktRecommendedShows = CatalogSource(id: "builtin.trakt.recommended.shows", title: "Trakt-Empfehlungen · Serien",
                                                            kind: .trakt(user: nil, list: "recommendations/shows"), mediaType: .series)
}

public struct Folder: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var coverImage: String?
    public var logo: String?
    public var backdrop: String?
    public var sources: [CatalogSource]
    /// Titel auf der Kachel ausblenden (Fusion `hideTitle`). nil = wie bisher: Titel nur ohne Bild.
    public var hideTitle: Bool?
    /// Welle F-g: bewegtes Bild (GIF), das auf der fokussierten Kachel statt des Standbilds spielt. nil = keins.
    /// Optional, also beim Lesen alter Profile `decodeIfPresent` (synthetisiert).
    public var focusGif: String?
    /// Wave F-o: short focus video (mp4/HLS, field `focusVideoUrl` of the collection export) that plays on the focused
    /// tile in place of the still and the GIF. nil = none. Optional, so old profiles decode it with `decodeIfPresent`.
    public var focusVideo: String?
    /// Wave F-o: video for the large hero area (`heroVideoUrl`), kept from imports; not played yet.
    public var heroVideo: String?

    public init(id: String, title: String, coverImage: String? = nil, logo: String? = nil, backdrop: String? = nil,
                sources: [CatalogSource], hideTitle: Bool? = nil, focusGif: String? = nil,
                focusVideo: String? = nil, heroVideo: String? = nil) {
        self.id = id; self.title = title; self.coverImage = coverImage; self.logo = logo; self.backdrop = backdrop; self.sources = sources
        self.hideTitle = hideTitle; self.focusGif = focusGif; self.focusVideo = focusVideo; self.heroVideo = heroVideo
    }

    /// Titel über dem Kachelbild zeigen: ohne Bild immer, mit Bild nur bei `hideTitle == false`.
    public var showsTitleOverImage: Bool { hideTitle == false }
}

public struct MediaCollection: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var folders: [Folder]

    public init(id: String, title: String, folders: [Folder]) {
        self.id = id; self.title = title; self.folders = folders
    }
}
