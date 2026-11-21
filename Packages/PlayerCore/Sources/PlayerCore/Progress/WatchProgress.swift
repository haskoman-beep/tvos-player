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

    public init() {}

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
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func fileURL(profile: UUID) -> URL { directory.appendingPathComponent("progress-\(profile.uuidString).json") }

    public func load(profile: UUID) -> ProgressBook {
        guard let d = try? Data(contentsOf: fileURL(profile: profile)) else { return ProgressBook() }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(ProgressBook.self, from: d)) ?? ProgressBook()
    }

    public func save(_ book: ProgressBook, profile: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try enc.encode(book).write(to: fileURL(profile: profile), options: .atomic)
    }
}
