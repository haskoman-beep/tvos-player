import Foundation

// Wave X2: on-device cache for the X-Ray gallery. Nothing here ever leaves the device.
//
// Two kinds of records:
// - per title (film, or one episode): the cast list used as candidates. Key: `XRayTitleKey`.
// - per person and model: the face embeddings of their TMDB portraits. Actors come back across titles and
//   episodes, so their embeddings are shared; a model change makes them invalid (model ID in the key).
// Every record lives 30 days from when it was computed (user decision 22.11.), then it is recomputed.
// Each file is wrapped in a versioned envelope; a different format version reads as "missing".

/// Which title a cast list belongs to.
public enum XRayTitleKey: Hashable, Sendable, Codable {
    case movie(tmdbID: Int)
    case episode(tvID: Int, season: Int, episode: Int)

    /// Stable name for file names and logs, e.g. "m603" or "e1399-s1e2".
    public var name: String {
        switch self {
        case .movie(let id): "m\(id)"
        case .episode(let tv, let s, let e): "e\(tv)-s\(s)e\(e)"
        }
    }
}

/// One candidate of a title.
public struct XRayCastEntry: Sendable, Equatable, Codable, Identifiable {
    public var personID: Int
    public var name: String
    public var role: String?
    /// TMDB `profile_path` (e.g. "/abc.jpg"), without size prefix.
    public var profilePath: String?
    /// Billing order in the credits (0 = top).
    public var order: Int
    /// Episode guest star.
    public var guest: Bool

    public var id: Int { personID }

    public init(personID: Int, name: String, role: String? = nil, profilePath: String? = nil, order: Int = 0, guest: Bool = false) {
        self.personID = personID; self.name = name; self.role = role; self.profilePath = profilePath
        self.order = order; self.guest = guest
    }
}

public struct XRayTitleRecord: Sendable, Equatable, Codable {
    public var key: XRayTitleKey
    public var cast: [XRayCastEntry]
    public init(key: XRayTitleKey, cast: [XRayCastEntry]) { self.key = key; self.cast = cast }
}

/// The embedding of one gallery picture.
public struct XRayFaceRecord: Sendable, Equatable, Codable {
    /// TMDB `file_path` of the portrait the embedding comes from.
    public var filePath: String
    public var embedding: FaceEmbedding

    public init(filePath: String, embedding: FaceEmbedding) { self.filePath = filePath; self.embedding = embedding }

    enum CodingKeys: String, CodingKey { case filePath = "f", embedding = "e" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filePath = try c.decode(String.self, forKey: .filePath)
        guard let e = FaceEmbedding(data: try c.decode(Data.self, forKey: .embedding)) else {
            throw DecodingError.dataCorruptedError(forKey: .embedding, in: c, debugDescription: "bad embedding")
        }
        embedding = e
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(filePath, forKey: .filePath)
        try c.encode(embedding.data, forKey: .embedding)
    }
}

public struct XRayPersonRecord: Sendable, Equatable, Codable {
    public var personID: Int
    public var modelID: String
    public var faces: [XRayFaceRecord]

    public init(personID: Int, modelID: String, faces: [XRayFaceRecord]) {
        self.personID = personID; self.modelID = modelID; self.faces = faces
    }

    public var gallery: GalleryPerson { GalleryPerson(personID: personID, embeddings: faces.map(\.embedding)) }
}

/// Only the version, read first so another layout is never decoded.
struct XRayEnvelopeHead: Decodable { var v: Int }

/// The versioned wrapper around every cache file.
struct XRayEnvelope<Body: Codable>: Codable {
    var v: Int
    var savedAt: Date
    var body: Body
}

public enum XRayCacheFormat {
    /// Bump when a record's layout changes; older files are then ignored and recomputed.
    public static let version = 1
    /// User decision 22.11.: 30 days.
    public static let lifetime: TimeInterval = 30 * 24 * 3600
    /// A person without any usable portrait is asked again sooner (TMDB may get a new photo).
    public static let emptyLifetime: TimeInterval = 7 * 24 * 3600
    /// Upper bound for all X-Ray files together; least recently used go first.
    public static let maxBytes = 20 * 1024 * 1024

    static let indexName = "xray-index.json"

    static func titleName(_ k: XRayTitleKey) -> String { "xray-t-\(k.name).json" }

    static func personName(_ id: Int, model: String) -> String { "xray-p-\(id)-\(slug(model)).json" }

    /// File-name-safe model ID.
    static func slug(_ s: String) -> String {
        let ok = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._")
        let t = String(s.map { ok.contains($0) ? $0 : "_" })
        return t.isEmpty ? "_" : String(t.prefix(48))
    }

    static func encode<B: Codable>(_ body: B, savedAt: Date) throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = .sortedKeys
        return try e.encode(XRayEnvelope(v: version, savedAt: savedAt, body: body))
    }

    /// Nil for unreadable files and for any other format version.
    static func decode<B: Codable>(_ type: B.Type, _ data: Data) -> (body: B, savedAt: Date)? {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        guard let h = try? d.decode(XRayEnvelopeHead.self, from: data), h.v == version,
              let env = try? d.decode(XRayEnvelope<B>.self, from: data) else { return nil }
        return (env.body, env.savedAt)
    }
}

/// Size and use times of the cache files, for expiry and the LRU limit.
struct XRayIndex: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var bytes: Int
        var savedAt: Date
        var usedAt: Date
        var lifetime: TimeInterval
    }
    var entries: [String: Entry] = [:]
    var totalBytes: Int { entries.values.reduce(0) { $0 + $1.bytes } }
}

/// The cache on top of a `BlobStorage` (in the app: a folder under Caches; tvOS may purge it, which only means
/// recomputing). All access goes through this actor.
public actor XRayStore {
    let storage: BlobStorage
    public let maxBytes: Int
    let now: @Sendable () -> Date
    private var index = XRayIndex()
    private var loaded = false
    private var dirty = false

    public init(storage: BlobStorage, maxBytes: Int = XRayCacheFormat.maxBytes, now: @escaping @Sendable () -> Date = { Date() }) {
        self.storage = storage; self.maxBytes = maxBytes; self.now = now
    }

    // MARK: Titles

    /// The cast list of a title, if stored and younger than 30 days.
    public func title(_ key: XRayTitleKey) -> XRayTitleRecord? {
        read(XRayTitleRecord.self, XRayCacheFormat.titleName(key)).flatMap { $0.key == key ? $0 : nil }
    }

    public func store(_ r: XRayTitleRecord) {
        write(r, XRayCacheFormat.titleName(r.key), lifetime: XRayCacheFormat.lifetime)
    }

    // MARK: People

    /// The embeddings of a person for this model, if fresh.
    public func person(_ id: Int, model: String) -> XRayPersonRecord? {
        read(XRayPersonRecord.self, XRayCacheFormat.personName(id, model: model))
            .flatMap { $0.personID == id && $0.modelID == model ? $0 : nil }
    }

    public func store(_ r: XRayPersonRecord) {
        write(r, XRayCacheFormat.personName(r.personID, model: r.modelID),
              lifetime: r.faces.isEmpty ? XRayCacheFormat.emptyLifetime : XRayCacheFormat.lifetime)
    }

    /// The gallery of a title for matching: every cast member with at least one embedding, in cast order.
    public func gallery(_ key: XRayTitleKey, model: String) -> [GalleryPerson] {
        guard let t = title(key) else { return [] }
        return t.cast.compactMap { c in person(c.personID, model: model).flatMap { $0.faces.isEmpty ? nil : $0.gallery } }
    }

    // MARK: Housekeeping

    /// Bytes currently accounted for (after expiry and eviction).
    public var totalBytes: Int { loadIndex(); return index.totalBytes }

    /// Writes the use times (reads only mark them).
    public func flush() {
        loadIndex()
        guard dirty else { return }
        saveIndex()
    }

    /// Removes every X-Ray file (e.g. a "clear cache" button).
    public func removeAll() {
        loadIndex()
        for name in index.entries.keys { storage.remove(name) }
        index = XRayIndex()
        saveIndex()
    }

    private func read<B: Codable>(_ type: B.Type, _ name: String) -> B? {
        loadIndex()
        let t = now()
        guard let data = storage.read(name), let decoded = XRayCacheFormat.decode(type, data) else {
            if index.entries.removeValue(forKey: name) != nil { dirty = true }
            return nil
        }
        let (body, savedAt) = decoded
        let lifetime = index.entries[name]?.lifetime ?? XRayCacheFormat.lifetime
        guard t.timeIntervalSince(savedAt) < lifetime, savedAt <= t.addingTimeInterval(60) else {
            storage.remove(name)
            index.entries.removeValue(forKey: name)
            dirty = true
            return nil
        }
        if index.entries[name] == nil {
            index.entries[name] = .init(bytes: data.count, savedAt: savedAt, usedAt: t, lifetime: lifetime)
        } else {
            index.entries[name]?.usedAt = t
        }
        dirty = true
        return body
    }

    private func write<B: Codable>(_ body: B, _ name: String, lifetime: TimeInterval) {
        loadIndex()
        let t = now()
        guard let data = try? XRayCacheFormat.encode(body, savedAt: t), (try? storage.write(name, data)) != nil else { return }
        index.entries[name] = .init(bytes: data.count, savedAt: t, usedAt: t, lifetime: lifetime)
        prune(keeping: name)
        saveIndex()
    }

    /// Drops expired entries, then the least recently used until the total fits `maxBytes`.
    /// The file just written stays even if it alone is larger.
    private func prune(keeping keep: String? = nil) {
        let t = now()
        for (name, e) in index.entries where name != keep && t.timeIntervalSince(e.savedAt) >= e.lifetime {
            storage.remove(name); index.entries.removeValue(forKey: name)
        }
        var total = index.totalBytes
        guard total > maxBytes else { return }
        let lru = index.entries.filter { $0.key != keep }
            .sorted { $0.value.usedAt != $1.value.usedAt ? $0.value.usedAt < $1.value.usedAt : $0.key < $1.key }
        for (name, e) in lru where total > maxBytes {
            storage.remove(name); index.entries.removeValue(forKey: name); total -= e.bytes
        }
    }

    private func loadIndex() {
        guard !loaded else { return }
        loaded = true
        if let d = storage.read(XRayCacheFormat.indexName), let decoded = XRayCacheFormat.decode(XRayIndex.self, d) {
            index = decoded.body
        }
        let before = index.entries.count
        prune()
        if index.entries.count != before { dirty = true }
    }

    private func saveIndex() {
        if let d = try? XRayCacheFormat.encode(index, savedAt: now()) { try? storage.write(XRayCacheFormat.indexName, d) }
        dirty = false
    }
}
