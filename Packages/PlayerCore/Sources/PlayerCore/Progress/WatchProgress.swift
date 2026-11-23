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

    /// Task 2.6 (S-10): entries younger than this many months are never pruned.
    public static let pruneMonths = 18

    /// Task 2.6 (S-10): keeps the book small. Of the finished entries the newest `keepFinished` stay, of the open
    /// ones the newest `keepOpen`; an entry beyond its quota is dropped only when it is older than `pruneMonths`.
    /// Everything else (sources, schema) is kept as it is. The stored format does not change.
    public func pruned(now: Date = Date(), keepFinished: Int = 1500, keepOpen: Int = 500) -> ProgressBook {
        guard entries.count > min(keepFinished, keepOpen) else { return self }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? cal.timeZone
        let cutoff = cal.date(byAdding: .month, value: -Self.pruneMonths, to: now) ?? now
        func drops(_ list: [WatchProgress], keep: Int) -> [String] {
            guard list.count > keep else { return [] }
            return list.sorted { $0.updated != $1.updated ? $0.updated > $1.updated : $0.id < $1.id }
                .dropFirst(max(0, keep)).filter { $0.updated < cutoff }.map(\.id)
        }
        let all = Array(entries.values)
        let gone = drops(all.filter(\.finished), keep: keepFinished) + drops(all.filter { !$0.finished }, keep: keepOpen)
        guard !gone.isEmpty else { return self }
        var out = self
        for id in gone { out.entries[id] = nil }
        return out
    }

    /// Speichert eine Position. Ab 92 % gilt der Titel als gesehen.
    public mutating func record(id: String, item: MetaPreview, season: Int? = nil, episode: Int? = nil,
                                position: Double, duration: Double, now: Date = Date()) {
        guard duration > 0, position.isFinite else { return }
        let done = position / duration >= Self.finishedAt
        clearSeriesMarker(itemID: item.id, episodeID: id, updated: now)
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

    /// Zustand für eine Kachel: Fortschritt, Restzeit, gesehen, Folge.
    public func cardState(itemID: String) -> CardState? {
        if let e = entries[itemID], e.season == nil {
            if e.finished { return CardState(watched: true) }
            guard e.position >= Self.minimumSeconds || (e.remoteFraction ?? 0) > 0 else { return nil }
            return CardState(fraction: e.fraction, remainingSeconds: e.duration > 0 ? max(0, e.duration - e.position) : nil)
        }
        guard let e = latest(forItem: itemID), let s = e.season, let ep = e.episode else { return nil }
        let label = "S\(s) F\(ep)"
        if e.finished { return CardState(episode: label) }
        let started = e.position >= Self.minimumSeconds || (e.remoteFraction ?? 0) > 0
        return CardState(fraction: started ? e.fraction : nil,
                         remainingSeconds: started && e.duration > 0 ? max(0, e.duration - e.position) : nil, episode: label)
    }

    /// Nur Anteil bekannt (aus Trakt/Simkl): Player springt nach dem Laden dorthin.
    public func resumeFraction(for id: String) -> Double? {
        guard let e = entries[id], !e.finished, e.duration == 0, let f = e.remoteFraction, f > 0.01, f < Self.finishedAt else { return nil }
        return f
    }

    /// Angefangenes aus dem Sync-Dienst übernehmen; neuerer lokaler Stand gewinnt.
    public mutating func merge(remote: [RemoteProgress]) {
        for r in remote {
            if let l = entries[r.id], l.updated >= r.updated { continue }
            // Wave L: an episode paused before the series was marked as watched stays out.
            if r.id != r.item.id, let m = entries[r.item.id], m.season == nil, m.finished, m.updated >= r.updated { continue }
            clearSeriesMarker(itemID: r.item.id, episodeID: r.id, updated: r.updated)
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
    /// Task 2.6: called with the number of entries dropped by `ProgressBook.pruned` before a save (only when > 0).
    let onPruned: (@Sendable (Int) -> Void)?
    public init(storage: BlobStorage, onPruned: (@Sendable (Int) -> Void)? = nil) {
        self.storage = storage; self.onPruned = onPruned
    }
    public init(directory: URL) { self.init(storage: FileBlobStorage(directory: directory)) }
    func name(_ profile: UUID) -> String { "progress-\(profile.uuidString).json" }

    /// Missing file: empty book. Task 1.3 (S-11): an unreadable file gives nil and is kept as
    /// `progress-<Profil>.json.bak`; the caller starts with an empty book and saves only after the next progress.
    public func load(profile: UUID) -> ProgressBook? {
        guard let d = storage.read(name(profile)) else { return ProgressBook() }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let b = try? dec.decode(ProgressBook.self, from: d) { return b }
        try? storage.write(name(profile) + ".bak", d)
        return nil
    }

    /// Task 2.6: prunes the book before every save (`ProgressBook.pruned`).
    public func save(_ book: ProgressBook, profile: UUID, now: Date = Date()) throws {
        let small = book.pruned(now: now)
        let dropped = book.entries.count - small.entries.count
        if dropped > 0 { onPruned?(dropped) }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try storage.write(name(profile), try enc.encode(small))
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

public struct CardState: Sendable, Equatable {
    public var fraction: Double?
    public var remainingSeconds: Double?
    public var watched = false
    public var episode: String?
    public init(fraction: Double? = nil, remainingSeconds: Double? = nil, watched: Bool = false, episode: String? = nil) {
        self.fraction = fraction; self.remainingSeconds = remainingSeconds; self.watched = watched; self.episode = episode
    }
}

extension ProgressBook {
    /// Verlauf (Spec §7a.5): gesehene Einträge, neueste zuerst, eine Kachel pro Titel.
    public func history(limit: Int = 50) -> [WatchProgress] {
        var seen = Set<String>()
        return entries.values
            .filter { $0.finished }
            .sorted { $0.updated > $1.updated }
            .filter { seen.insert($0.item.id).inserted }
            .prefix(limit).map { $0 }
    }
}
