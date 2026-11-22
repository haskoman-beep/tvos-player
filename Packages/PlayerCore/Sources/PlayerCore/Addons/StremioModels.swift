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
        // Wave W-a: one unreadable resource or catalog no longer empties the whole list.
        resources = c.lenientList(AddonResource.self, .resources)?.items ?? []
        types = (try? c.decode([String].self, forKey: .types)) ?? []
        catalogs = c.lenientList(CatalogDescriptor.self, .catalogs)?.items ?? []
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

extension CatalogDescriptor {
    /// Wave W-a: lenient; only `type` and `id` are needed, an unreadable extra entry is skipped.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let type = c.lenientNonEmpty(.type), let id = c.lenientNonEmpty(.id) else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "catalog without type or id"))
        }
        self.type = type; self.id = id
        name = c.lenientString(.name)
        extra = c.lenientList(CatalogExtra.self, .extra)?.items
    }
}

public struct CatalogExtra: Codable, Sendable, Equatable {
    public var name: String
    public var isRequired: Bool?
    public var options: [String]?
    /// Wave W-a: preselected value (`default`), e.g. the genre a discover-only catalog starts with.
    public var defaultValue: String?
    /// Wave W-a: how many options may be chosen at once (`optionsLimit`).
    public var optionsLimit: Int?

    public init(name: String, isRequired: Bool? = nil, options: [String]? = nil, defaultValue: String? = nil,
                optionsLimit: Int? = nil) {
        self.name = name; self.isRequired = isRequired; self.options = options
        self.defaultValue = defaultValue; self.optionsLimit = optionsLimit
    }

    enum CodingKeys: String, CodingKey { case name, isRequired, options, defaultValue = "default", optionsLimit }
}

extension CatalogExtra {
    /// Wave W-a: lenient; numbers as options become text, `isRequired: "true"` counts.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let name = c.lenientNonEmpty(.name) else {
            throw DecodingError.keyNotFound(CodingKeys.name, .init(codingPath: c.codingPath, debugDescription: "extra without name"))
        }
        self.name = name
        isRequired = c.lenientBool(.isRequired)
        options = c.lenientStrings(.options)
        defaultValue = c.lenientString(.defaultValue)
        optionsLimit = c.lenientInt(.optionsLimit)
    }
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
    /// Wave W-a: IMDb ID the addon names for a title with another ID (`imdb_id`, e.g. for `mal:` or `kitsu:` items).
    public var imdbID: String?
    /// Wave W-a: `behaviorHints` of the meta (`defaultVideoId`, `hasScheduledVideos`).
    public var behaviorHints: MetaBehaviorHints?

    /// Wave W-a: video the addon plays for this title (`behaviorHints.defaultVideoId`), e.g. `kitsu:123` or `tt…`.
    public var defaultVideoId: String? { behaviorHints?.defaultVideoId }
}

/// Wave W-a: `behaviorHints` of a meta object.
public struct MetaBehaviorHints: Codable, Sendable, Equatable {
    public var defaultVideoId: String?
    public var hasScheduledVideos: Bool?

    public init(defaultVideoId: String? = nil, hasScheduledVideos: Bool? = nil) {
        self.defaultVideoId = defaultVideoId; self.hasScheduledVideos = hasScheduledVideos
    }

    enum CodingKeys: String, CodingKey { case defaultVideoId, hasScheduledVideos }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultVideoId = c.lenientNonEmpty(.defaultVideoId)
        hasScheduledVideos = c.lenientBool(.hasScheduledVideos)
    }
}

/// Wave W-a: keys addons send besides the ones the app stores.
private enum AddonAltKeys: String, CodingKey {
    /// Year as its own field; used when `releaseInfo` is missing.
    case year
    /// IMDb ID of a title with another ID (`imdb_id`).
    case imdbID = "imdb_id"
    /// Episode text some addons send as `description` instead of `overview`.
    case description
}

private func missingKey(_ key: some CodingKey, _ c: some KeyedDecodingContainerProtocol, _ what: String) -> DecodingError {
    .keyNotFound(key, .init(codingPath: c.codingPath, debugDescription: what))
}

extension MetaPreview {
    /// Wave W-a: lenient. Only `id` is needed: numbers in `releaseInfo`/`imdbRating` become text (AIOMetadata sends
    /// `releaseInfo: 2019` in anime catalogs), a field with another type or `null` becomes nil. A missing `type` stays
    /// empty here and is filled in with the catalog's type by `AddonClient.catalogPage`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try decoder.container(keyedBy: AddonAltKeys.self)
        guard let id = c.lenientNonEmpty(.id) else { throw missingKey(CodingKeys.id, c, "catalog item without id") }
        self.id = id
        type = c.lenientNonEmpty(.type) ?? ""
        name = c.lenientString(.name) ?? ""
        poster = c.lenientNonEmpty(.poster)
        background = c.lenientNonEmpty(.background)
        logo = c.lenientNonEmpty(.logo)
        description = c.lenientString(.description)
        releaseInfo = c.lenientString(.releaseInfo) ?? alt.lenientString(.year)
        imdbRating = c.lenientString(.imdbRating)
    }
}

extension MetaVideo {
    /// Wave W-a: lenient. Only `id` is needed; `season`/`episode` may be text ("1"), `released` a number.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try decoder.container(keyedBy: AddonAltKeys.self)
        guard let id = c.lenientNonEmpty(.id) else { throw missingKey(CodingKeys.id, c, "video without id") }
        self.id = id
        title = c.lenientString(.title)
        name = c.lenientString(.name)
        season = c.lenientInt(.season)
        episode = c.lenientInt(.episode)
        released = c.lenientString(.released)
        thumbnail = c.lenientNonEmpty(.thumbnail)
        overview = c.lenientString(.overview) ?? alt.lenientString(.description)
    }
}

extension MetaDetail {
    /// Wave W-a: lenient. Every field may be missing, `null` or of another type without dropping the meta; numbers
    /// become text (`releaseInfo: 2019`, `runtime: 24`, `imdbRating: 6.3`). Unreadable videos are skipped, the rest
    /// stays. Only a meta with neither `id` nor `name` fails. A missing `id`/`type` is filled in by `AddonClient.meta`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try decoder.container(keyedBy: AddonAltKeys.self)
        id = c.lenientNonEmpty(.id) ?? ""
        name = c.lenientString(.name) ?? ""
        guard !id.isEmpty || !name.isEmpty else { throw missingKey(CodingKeys.id, c, "meta without id and name") }
        type = c.lenientNonEmpty(.type) ?? ""
        poster = c.lenientNonEmpty(.poster)
        background = c.lenientNonEmpty(.background)
        logo = c.lenientNonEmpty(.logo)
        description = c.lenientString(.description)
        releaseInfo = c.lenientString(.releaseInfo) ?? alt.lenientString(.year)
        runtime = c.lenientString(.runtime)
        genres = c.lenientStrings(.genres)
        videos = c.lenientList(MetaVideo.self, .videos)?.items
        imdbRating = c.lenientString(.imdbRating)
        // Stored as `imdbID` (own encoding), sent by addons as `imdb_id`.
        imdbID = c.lenientNonEmpty(.imdbID) ?? alt.lenientNonEmpty(.imdbID)
        behaviorHints = (try? c.decodeIfPresent(MetaBehaviorHints.self, forKey: .behaviorHints)) ?? nil
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
    /// Wave W-a: structured entry type some aggregators send (`streamData.type`, e.g. "error"); see `AddonStreamKind`.
    public var streamData: AddonStreamData?

    public init(name: String? = nil, title: String? = nil, description: String? = nil, url: String? = nil,
                infoHash: String? = nil, externalUrl: String? = nil, behaviorHints: StreamBehaviorHints? = nil,
                fileIdx: Int? = nil, streamData: AddonStreamData? = nil) {
        self.name = name; self.title = title; self.description = description; self.url = url
        self.infoHash = infoHash; self.externalUrl = externalUrl; self.behaviorHints = behaviorHints
        self.fileIdx = fileIdx; self.streamData = streamData
    }

    enum CodingKeys: String, CodingKey { case name, title, description, url, infoHash, externalUrl, behaviorHints, fileIdx, streamData }

    /// Wave W-a: lenient per field. A text field with another type (`"name": 1080`) becomes text or nil, unreadable
    /// `behaviorHints` become nil; the stream stays. Only an entry without any address (`url`, `infoHash`, `ytId`,
    /// `externalUrl`) that is no addon notice (`streamData`) is unreadable and skipped by the list.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.lenientString(.name)
        title = c.lenientString(.title)
        description = c.lenientString(.description)
        url = c.lenientNonEmpty(.url)
        infoHash = c.lenientNonEmpty(.infoHash)
        externalUrl = c.lenientNonEmpty(.externalUrl)
        behaviorHints = (try? c.decodeIfPresent(StreamBehaviorHints.self, forKey: .behaviorHints)) ?? nil
        fileIdx = c.lenientInt(.fileIdx)
        streamData = (try? c.decodeIfPresent(AddonStreamData.self, forKey: .streamData)) ?? nil
        let hasYouTube = (try? decoder.container(keyedBy: StreamAltKeys.self).lenientNonEmpty(.ytId)) != nil
        guard url != nil || infoHash != nil || externalUrl != nil || hasYouTube || streamData != nil else {
            throw DecodingError.keyNotFound(CodingKeys.url, .init(codingPath: c.codingPath, debugDescription: "stream without address"))
        }
    }

    /// Wave W-a: keys read only to judge an entry (YouTube streams are not played).
    private enum StreamAltKeys: String, CodingKey { case ytId }

    public var id: String { (url ?? infoHash ?? "") + "|" + (name ?? "") + "|" + label }
    /// Neuere Addons nutzen `description`, ältere `title`.
    public var label: String { description ?? title ?? "" }
    public var isPlayable: Bool { url.flatMap(URL.init(string:)) != nil }

    public func hash(into h: inout Hasher) { h.combine(id) }
}

/// Wave W-a: the part of `streamData` the app reads: only the entry type ("error", "info", …).
public struct AddonStreamData: Codable, Sendable, Equatable {
    public var type: String?
    public init(type: String? = nil) { self.type = type }

    enum CodingKeys: String, CodingKey { case type }

    public init(from decoder: Decoder) throws {
        type = try decoder.container(keyedBy: CodingKeys.self).lenientNonEmpty(.type)
    }
}

/// `{"streams":[…]}`; Wave W-a: an unreadable entry is skipped instead of failing the whole list.
struct StreamsResponse: Decodable {
    var streams: [StreamItem]
    var skipped = 0

    enum CodingKeys: String, CodingKey { case streams }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let list = c.lenientList(StreamItem.self, .streams) else {
            throw DecodingError.keyNotFound(CodingKeys.streams, .init(codingPath: c.codingPath, debugDescription: "no stream list"))
        }
        streams = list.items; skipped = list.skipped
    }
}

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
/// `{"metas":[…]}`; Wave W-a: an unreadable item is skipped and counted instead of failing the whole catalog.
/// Without a `metas` list the answer still counts as unreadable (failed row, retry).
struct MetasResponse: Decodable {
    var metas: [MetaPreview]
    var skipped = 0

    enum CodingKeys: String, CodingKey { case metas }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let list = c.lenientList(MetaPreview.self, .metas) else {
            throw DecodingError.keyNotFound(CodingKeys.metas, .init(codingPath: c.codingPath, debugDescription: "no metas list"))
        }
        metas = list.items; skipped = list.skipped
    }
}

struct MetaResponse: Decodable { var meta: MetaDetail }
