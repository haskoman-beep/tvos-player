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

    public init(id: String, item: MetaPreview, season: Int? = nil, episode: Int? = nil,
                position: Double, duration: Double, updated: Date = Date(), finished: Bool = false) {
        self.id = id; self.item = item; self.season = season; self.episode = episode
        self.position = position; self.duration = duration; self.updated = updated; self.finished = finished
    }

    public var fraction: Double { duration > 0 ? position / duration : 0 }
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

    /// Wo weitermachen? nil = von vorn (nie gestartet, < 1 min oder gesehen).
    public func resumePosition(for id: String) -> Double? {
        guard let e = entries[id], !e.finished, e.position >= Self.minimumSeconds else { return nil }
        return e.position
    }

    /// Weiterschauen: angefangene Titel, neueste zuerst, eine Kachel pro Serie.
    public func continueWatching(limit: Int = 30) -> [WatchProgress] {
        var seen = Set<String>()
        return entries.values
            .filter { !$0.finished && $0.position >= Self.minimumSeconds }
            .sorted { $0.updated > $1.updated }
            .filter { seen.insert($0.item.id).inserted }
            .prefix(limit).map { $0 }
    }

    public func isWatched(_ id: String) -> Bool { entries[id]?.finished == true }
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
