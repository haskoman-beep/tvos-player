import Foundation

/// Stremio-Addon-Protokoll: Manifest und Antworttypen.
/// Referenz: https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/api/responses

public struct AddonManifest: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var version: String
    public var description: String?
    public var resources: [AddonResource]
    public var types: [String]
    public var catalogs: [CatalogDescriptor]
    public var idPrefixes: [String]?
    public var logo: String?

    public init(id: String, name: String, version: String, description: String? = nil,
                resources: [AddonResource], types: [String], catalogs: [CatalogDescriptor] = [],
                idPrefixes: [String]? = nil, logo: String? = nil) {
        self.id = id; self.name = name; self.version = version; self.description = description
        self.resources = resources; self.types = types; self.catalogs = catalogs
        self.idPrefixes = idPrefixes; self.logo = logo
    }

    enum CodingKeys: String, CodingKey { case id, name, version, description, resources, types, catalogs, idPrefixes, logo }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        version = (try? c.decode(String.self, forKey: .version)) ?? "0"
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        resources = (try? c.decode([AddonResource].self, forKey: .resources)) ?? []
        types = (try? c.decode([String].self, forKey: .types)) ?? []
        catalogs = (try? c.decode([CatalogDescriptor].self, forKey: .catalogs)) ?? []
        idPrefixes = try? c.decodeIfPresent([String].self, forKey: .idPrefixes)
        logo = try? c.decodeIfPresent(String.self, forKey: .logo)
    }

    /// Ob das Addon eine Ressource für einen Typ und eine ID anbietet.
    public func supports(_ resource: String, type: String, id: String) -> Bool {
        for r in resources where r.name == resource {
            let rTypes = r.types ?? types
            let rPrefixes = r.idPrefixes ?? idPrefixes
            guard rTypes.contains(type) else { continue }
            if let p = rPrefixes, !p.isEmpty, !p.contains(where: { id.hasPrefix($0) }) { continue }
            return true
        }
        return false
    }
}

/// Eine Ressource darf als String ("stream") oder als Objekt kommen.
public struct AddonResource: Codable, Sendable, Equatable {
    public var name: String
    public var types: [String]?
    public var idPrefixes: [String]?

    public init(name: String, types: [String]? = nil, idPrefixes: [String]? = nil) {
        self.name = name; self.types = types; self.idPrefixes = idPrefixes
    }

    enum CodingKeys: String, CodingKey { case name, types, idPrefixes }

    public init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            name = s; types = nil; idPrefixes = nil; return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        types = try? c.decodeIfPresent([String].self, forKey: .types)
        idPrefixes = try? c.decodeIfPresent([String].self, forKey: .idPrefixes)
    }

    public func encode(to encoder: Encoder) throws {
        if types == nil && idPrefixes == nil {
            var c = encoder.singleValueContainer(); try c.encode(name); return
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(types, forKey: .types)
        try c.encodeIfPresent(idPrefixes, forKey: .idPrefixes)
    }
}

public struct CatalogDescriptor: Codable, Sendable, Equatable {
    public var type: String
    public var id: String
    public var name: String?
    public var extra: [CatalogExtra]?
    public init(type: String, id: String, name: String? = nil, extra: [CatalogExtra]? = nil) {
        self.type = type; self.id = id; self.name = name; self.extra = extra
    }
}

public struct CatalogExtra: Codable, Sendable, Equatable {
    public var name: String
    public var isRequired: Bool?
    public var options: [String]?
}

/// Kurzform eines Titels in Katalogen (`metas`).
public struct MetaPreview: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var type: String
    public var name: String
    public var poster: String?
    public var background: String?
    public var logo: String?
    public var description: String?
    public var releaseInfo: String?
    public var imdbRating: String?

    public init(id: String, type: String, name: String, poster: String? = nil, background: String? = nil,
                logo: String? = nil, description: String? = nil, releaseInfo: String? = nil, imdbRating: String? = nil) {
        self.id = id; self.type = type; self.name = name; self.poster = poster; self.background = background
        self.logo = logo; self.description = description; self.releaseInfo = releaseInfo; self.imdbRating = imdbRating
    }
}

public struct MetaVideo: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String?
    public var name: String?
    public var season: Int?
    public var episode: Int?
    public var released: String?
    public var thumbnail: String?
    public var overview: String?
}

public struct MetaDetail: Codable, Sendable, Equatable {
    public var id: String
    public var type: String
    public var name: String
    public var poster: String?
    public var background: String?
    public var logo: String?
    public var description: String?
    public var releaseInfo: String?
    public var runtime: String?
    public var genres: [String]?
    public var videos: [MetaVideo]?
}

public struct StreamBehaviorHints: Codable, Sendable, Equatable {
    public var bingeGroup: String?
    public var notWebReady: Bool?
    public var filename: String?
    public var videoSize: Int64?
    public var proxyHeaders: ProxyHeaders?

    public struct ProxyHeaders: Codable, Sendable, Equatable {
        public var request: [String: String]?
    }
}

/// Ein abspielbarer Stream. Wir nutzen nur `url`-Streams (Debrid/Usenet über AIOStreams);
/// `infoHash`/`ytId`/`externalUrl` werden gelesen, aber nicht abgespielt.
public struct StreamItem: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var name: String?
    public var title: String?
    public var description: String?
    public var url: String?
    public var infoHash: String?
    public var externalUrl: String?
    public var behaviorHints: StreamBehaviorHints?

    public init(name: String? = nil, title: String? = nil, description: String? = nil, url: String? = nil,
                infoHash: String? = nil, externalUrl: String? = nil, behaviorHints: StreamBehaviorHints? = nil) {
        self.name = name; self.title = title; self.description = description; self.url = url
        self.infoHash = infoHash; self.externalUrl = externalUrl; self.behaviorHints = behaviorHints
    }

    public var id: String { (url ?? infoHash ?? "") + "|" + (name ?? "") + "|" + label }
    /// Neuere Addons nutzen `description`, ältere `title`.
    public var label: String { description ?? title ?? "" }
    public var isPlayable: Bool { url.flatMap(URL.init(string:)) != nil }

    public func hash(into h: inout Hasher) { h.combine(id) }
}

struct StreamsResponse: Codable { var streams: [StreamItem] }
struct MetasResponse: Codable { var metas: [MetaPreview] }
struct MetaResponse: Codable { var meta: MetaDetail }
