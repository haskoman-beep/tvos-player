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
}

/// Eine Titelliste (eine Startseiten-Reihe vom Typ "Liste").
public struct CatalogSource: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var kind: SourceKind
    public var mediaType: MediaType
    /// TMDB-Sortierung (z. B. `popularity.desc`); nil = Reihenfolge der Quelle.
    public var sortBy: String?

    public init(id: String, title: String, kind: SourceKind, mediaType: MediaType, sortBy: String? = nil) {
        self.id = id; self.title = title; self.kind = kind; self.mediaType = mediaType; self.sortBy = sortBy
    }

    public static let continueWatching = CatalogSource(id: "builtin.continue", title: "Weiterschauen", kind: .continueWatching, mediaType: .both)
    public static let watchlist = CatalogSource(id: "builtin.watchlist", title: "Merkliste", kind: .watchlist, mediaType: .both)
}

public struct Folder: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var coverImage: String?
    public var logo: String?
    public var backdrop: String?
    public var sources: [CatalogSource]

    public init(id: String, title: String, coverImage: String? = nil, logo: String? = nil, backdrop: String? = nil, sources: [CatalogSource]) {
        self.id = id; self.title = title; self.coverImage = coverImage; self.logo = logo; self.backdrop = backdrop; self.sources = sources
    }
}

public struct Collection: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var folders: [Folder]

    public init(id: String, title: String, folders: [Folder]) {
        self.id = id; self.title = title; self.folders = folders
    }
}
