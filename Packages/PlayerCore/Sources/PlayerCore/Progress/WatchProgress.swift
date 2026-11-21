import Foundation

/// Lokaler Fortschritt eines Titels (Film oder Folge). Spec §6 Weiterschauen, P4 ergänzt Trakt/Simkl.
public struct WatchProgress: Codable, Sendable, Hashable, Identifiable {
    /// "tt123" (Film) oder "tt123:1:2" (Folge).
    public var id: String
    /// Eintrag, der in der Weiterschauen-Reihe gezeigt wird (bei Folgen die Serie).
    public var item: MetaPreview
    public var season: Int?
    public var episode: Int?
    public var position: Double
    public var duration: Double
    public var updated: Date
    public var finished: Bool
    /// Nächste Folge nach einer gesehenen: erscheint in Weiterschauen, obwohl noch nicht gestartet.
    public var nextUp: Bool?
    /// Stand aus Trakt/Simkl (0…1), solange die Laufzeit lokal noch unbekannt ist.
    public var remoteFraction: Double?

    public init(id: String, item: MetaPreview, season: Int? = nil, episode: Int? = nil,
                position: Double, duration: Double, updated: Date = Date(), finished: Bool = false, nextUp: Bool? = nil,
                remoteFraction: Double? = nil) {
        self.id = id; self.item = item; self.season = season; self.episode = episode
        self.position = position; self.duration = duration; self.updated = updated; self.finished = finished
        self.nextUp = nextUp; self.remoteFraction = remoteFraction
    }

    public var fraction: Double { duration > 0 ? position / duration : (remoteFraction ?? 0) }
}

public struct ProgressBook: Codable, Sendable, Equatable {
    public static let finishedAt = 0.92
    public static let minimumSeconds = 60.0
    public var schemaVersion = 1
    public var entries: [String: WatchProgress] = [:]
    /// Zuletzt gespielte Quelle je Film bzw. Serie (Schlüssel: IMDb-ID ohne Staffel/Folge). Optional für alte Dateien.
    public var sources: [String: LastSource]?

    public init() {}

    /// Schlüssel für `sources`: "tt123:1:2" → "tt123".
    public static func sourceKey(_ id: String) -> String { String(id.split(separator: ":").first ?? Substring(id)) }

    public mutating func rememberSource(_ stream: StreamItem, addon: String, for id: String, now: Date = Date()) {
        var all = sources ?? [:]
        all[Self.sourceKey(id)] = LastSource(stream: stream, addon: addon, contentID: id, savedAt: now)
        sources = all
    }

    public func lastSource(for id: String) -> LastSource? { sources?[Self.sourceKey(id)] }

    /// Speichert eine Position. Ab 92 % gilt der Titel als gesehen.
    public mutating func record(id: String, item: MetaPreview, season: Int? = nil, episode: Int? = nil,
                                position: Double, duration: Double, now: Date = Date()) {
        guard duration > 0, position.isFinite else { return }
        let done = position / duration >= Self.finishedAt
        entries[id] = WatchProgress(id: id, item: item, season: season, episode: episode,
                                    position: done ? 0 : position, duration: duration, updated: now, finished: done)
    }

    /// Merkt die nächste Folge vor (überschreibt keinen echten Fortschritt).
    public mutating func recordNextUp(id: String, item: MetaPreview, season: Int, episode: Int, now: Date = Date()) {
        if let e = entries[id], e.finished || e.position >= Self.minimumSeconds { return }
        entries[id] = WatchProgress(id: id, item: item, season: season, episode: episode,
                                    position: 0, duration: 0, updated: now, finished: false, nextUp: true)
    }

    /// Wo weitermachen? nil = von vorn (nie gestartet, < 1 min oder gesehen).
    public func resumePosition(for id: String) -> Double? {
        guard let e = entries[id], !e.finished, e.position >= Self.minimumSeconds else { return nil }
        return e.position
    }

    /// Weiterschauen: angefangene Titel, neueste zuerst, eine Kachel pro Serie.
    public func continueWatching(limit: Int = 30) -> [WatchProgress] {
        var seen = Set<String>()
        return entries.values
            .filter { !$0.finished && ($0.position >= Self.minimumSeconds || $0.nextUp == true || ($0.remoteFraction ?? 0) > 0) }
            .sorted { $0.updated > $1.updated }
            .filter { seen.insert($0.item.id).inserted }
            .prefix(limit).map { $0 }
    }

    /// Neuester Eintrag einer Serie (für die Staffelauswahl auf der Detailseite).
    public func latest(forItem itemID: String) -> WatchProgress? {
        entries.values.filter { $0.item.id == itemID }.max { $0.updated < $1.updated }
    }

    public func isWatched(_ id: String) -> Bool { entries[id]?.finished == true }

    /// Nur Anteil bekannt (aus Trakt/Simkl): Player springt nach dem Laden dorthin.
    public func resumeFraction(for id: String) -> Double? {
        guard let e = entries[id], !e.finished, e.duration == 0, let f = e.remoteFraction, f > 0.01, f < Self.finishedAt else { return nil }
        return f
    }

    /// Angefangenes aus dem Sync-Dienst übernehmen; neuerer lokaler Stand gewinnt.
    public mutating func merge(remote: [RemoteProgress]) {
        for r in remote {
            if let l = entries[r.id], l.updated >= r.updated { continue }
            let dur = entries[r.id]?.duration ?? 0
            entries[r.id] = WatchProgress(id: r.id, item: r.item, season: r.season, episode: r.episode,
                                          position: dur > 0 ? r.fraction * dur : 0, duration: dur, updated: r.updated,
                                          finished: r.fraction >= Self.finishedAt, remoteFraction: dur > 0 ? nil : r.fraction)
        }
    }
}

/// Eine Datei pro Profil: progress-<id>.json (atomar).
public struct ProgressStore: Sendable {
    public let storage: BlobStorage
    public init(storage: BlobStorage) { self.storage = storage }
    public init(directory: URL) { self.init(storage: FileBlobStorage(directory: directory)) }
    func name(_ profile: UUID) -> String { "progress-\(profile.uuidString).json" }

    public func load(profile: UUID) -> ProgressBook {
        guard let d = storage.read(name(profile)) else { return ProgressBook() }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(ProgressBook.self, from: d)) ?? ProgressBook()
    }

    public func save(_ book: ProgressBook, profile: UUID) throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try storage.write(name(profile), try enc.encode(book))
    }
}

/// Merkmale der zuletzt gewählten Quelle, um sie in einer frischen Quellenliste wiederzufinden
/// (Debrid-Links laufen ab, darum wird nicht die alte URL gespielt).
public struct LastSource: Codable, Sendable, Hashable {
    public var addon: String
    public var name: String?
    /// Dateiname bzw. Beschreibung – erkennt genau dieselbe Datei.
    public var fingerprint: String
    public var bingeGroup: String?
    /// Inhalt, für den sie gewählt wurde ("tt123" oder "tt123:1:2").
    public var contentID: String
    public var savedAt: Date

    public init(stream: StreamItem, addon: String, contentID: String, savedAt: Date = Date()) {
        self.addon = addon; self.name = stream.name
        self.fingerprint = stream.behaviorHints?.filename ?? stream.label
        self.bingeGroup = stream.behaviorHints?.bingeGroup
        self.contentID = contentID; self.savedAt = savedAt
    }

    /// Passende Quelle in einer neuen Liste: gleiche Datei (gleicher Inhalt), sonst gleiche bingeGroup,
    /// sonst gleicher Addon + gleicher Quellenname mit gleicher Auflösung. Nicht gecachte nur als letzte Wahl.
    public func match(in streams: [(addon: String, stream: StreamItem)]) -> StreamItem? {
        let list = streams.filter { $0.stream.url != nil }
        func fp(_ s: StreamItem) -> String { s.behaviorHints?.filename ?? s.label }
        if let e = list.first(where: { fp($0.stream) == fingerprint }) { return e.stream }
        let ready = list.filter { StreamTraits.parse($0.stream).cached != false }
        if let g = bingeGroup, let e = ready.first(where: { $0.stream.behaviorHints?.bingeGroup == g }) { return e.stream }
        let res = StreamTraits.parse(StreamItem(name: name, title: fingerprint)).resolution
        if let e = ready.first(where: { $0.addon == addon && $0.stream.name == name
                                        && StreamTraits.parse($0.stream).resolution == res }) { return e.stream }
        return nil
    }
}
