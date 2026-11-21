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
    /// Welle E-a: IMDb-Wertung, die das Metadaten-Addon mitliefert ("7.1"; als Zahl gesendet wird sie zum Text).
    public var imdbRating: String?
}

extension MetaDetail {
    /// Wie die automatische Dekodierung; nur `imdbRating` darf Text oder Zahl sein und bricht bei anderem Inhalt nichts.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(String.self, forKey: .type)
        name = try c.decode(String.self, forKey: .name)
        poster = try c.decodeIfPresent(String.self, forKey: .poster)
        background = try c.decodeIfPresent(String.self, forKey: .background)
        logo = try c.decodeIfPresent(String.self, forKey: .logo)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        releaseInfo = try c.decodeIfPresent(String.self, forKey: .releaseInfo)
        runtime = try c.decodeIfPresent(String.self, forKey: .runtime)
        genres = try c.decodeIfPresent([String].self, forKey: .genres)
        videos = try c.decodeIfPresent([MetaVideo].self, forKey: .videos)
        if let s = try? c.decodeIfPresent(String.self, forKey: .imdbRating) { imdbRating = s }
        else if let d = try? c.decodeIfPresent(Double.self, forKey: .imdbRating) { imdbRating = String(d) }
        else { imdbRating = nil }
    }
}

public struct StreamBehaviorHints: Codable, Sendable, Equatable {
    public var bingeGroup: String?
    public var notWebReady: Bool?
    public var filename: String?
    public var videoSize: Int64?
    public var proxyHeaders: ProxyHeaders?
    /// AIOStreams-Zusatzfelder (optional; fehlen bei anderen Addons). Dienst-ID wie "torbox", "realdebrid".
    public var service: String?
    /// Datei liegt beim Dienst bereit (sofort abspielbar); gilt auch ohne `service` (z. B. Usenet-/P2P-Einträge).
    public var cached: Bool?
    /// Laufzeit in Sekunden.
    public var duration: Double?
    public var seeders: Int?
    public var indexer: String?
    /// ISO-8601-Datum der Veröffentlichung.
    public var publishDate: String?
    public var folderName: String?
    public var folderSize: Int64?

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
    /// Welle E-b: Datei im Torrent (mit `infoHash` Teil des Dubletten-Schlüssels); nicht Teil von `id`.
    public var fileIdx: Int?

    public init(name: String? = nil, title: String? = nil, description: String? = nil, url: String? = nil,
                infoHash: String? = nil, externalUrl: String? = nil, behaviorHints: StreamBehaviorHints? = nil,
                fileIdx: Int? = nil) {
        self.name = name; self.title = title; self.description = description; self.url = url
        self.infoHash = infoHash; self.externalUrl = externalUrl; self.behaviorHints = behaviorHints
        self.fileIdx = fileIdx
    }

    enum CodingKeys: String, CodingKey { case name, title, description, url, infoHash, externalUrl, behaviorHints, fileIdx }

    /// Wie die synthetisierte Form; nur `fileIdx` nachsichtig (Zahl oder Text, sonst nil statt Fehler der ganzen Liste).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        infoHash = try c.decodeIfPresent(String.self, forKey: .infoHash)
        externalUrl = try c.decodeIfPresent(String.self, forKey: .externalUrl)
        behaviorHints = try c.decodeIfPresent(StreamBehaviorHints.self, forKey: .behaviorHints)
        fileIdx = ((try? c.decodeIfPresent(Int.self, forKey: .fileIdx)) ?? nil)
            ?? ((try? c.decodeIfPresent(String.self, forKey: .fileIdx)) ?? nil).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    public var id: String { (url ?? infoHash ?? "") + "|" + (name ?? "") + "|" + label }
    /// Neuere Addons nutzen `description`, ältere `title`.
    public var label: String { description ?? title ?? "" }
    public var isPlayable: Bool { url.flatMap(URL.init(string:)) != nil }

    public func hash(into h: inout Hasher) { h.combine(id) }
}

struct StreamsResponse: Codable { var streams: [StreamItem] }

extension StreamBehaviorHints {
    enum CodingKeys: String, CodingKey {
        case bingeGroup, notWebReady, filename, videoSize, proxyHeaders
        case service, cached, duration, seeders, indexer, publishDate, folderName, folderSize
    }

    /// Nachsichtig: ein Feld mit unerwartetem Typ wird übersprungen, statt die ganze Quelle zu verwerfen.
    /// Zahlen dürfen auch als Text kommen, Wahrheitswerte auch als "true"/"false".
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func str(_ k: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil }
        func num(_ k: CodingKeys) -> Double? {
            if let d = (try? c.decodeIfPresent(Double.self, forKey: k)) ?? nil { return d }
            return str(k).flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        }
        func bool(_ k: CodingKeys) -> Bool? {
            if let b = (try? c.decodeIfPresent(Bool.self, forKey: k)) ?? nil { return b }
            switch str(k)?.lowercased() { case "true", "1": return true; case "false", "0": return false; default: return nil }
        }
        bingeGroup = str(.bingeGroup)
        notWebReady = bool(.notWebReady)
        filename = str(.filename)
        videoSize = num(.videoSize).flatMap { $0.isFinite && $0 >= 0 && $0 < 9e18 ? Int64($0) : nil }
        proxyHeaders = (try? c.decodeIfPresent(ProxyHeaders.self, forKey: .proxyHeaders)) ?? nil
        service = str(.service).flatMap { $0.isEmpty ? nil : $0 }
        cached = bool(.cached)
        duration = num(.duration).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        seeders = num(.seeders).flatMap { $0.isFinite && $0 >= 0 && $0 < 1e9 ? Int($0) : nil }
        indexer = str(.indexer)
        publishDate = str(.publishDate)
        folderName = str(.folderName)
        folderSize = num(.folderSize).flatMap { $0.isFinite && $0 >= 0 && $0 < 9e18 ? Int64($0) : nil }
    }
}
struct MetasResponse: Codable { var metas: [MetaPreview] }
struct MetaResponse: Codable { var meta: MetaDetail }
