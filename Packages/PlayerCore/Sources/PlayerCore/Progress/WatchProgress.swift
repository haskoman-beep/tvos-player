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

    /// Fixed UTC calendar for the cutoff (built once, not on every save).
    static let pruneCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? cal.timeZone
        return cal
    }()

    /// Series marker ("whole series watched"): `id == item.id`, no season, not a film. Never pruned, because
    /// `merge(remote:)` relies on it to keep old paused episodes out of Weiterschauen.
    static func isSeriesMarker(_ e: WatchProgress) -> Bool {
        e.season == nil && e.id == e.item.id && e.item.type != "movie"
    }

    /// Task 2.6 (S-10): keeps the book small. Only finished entries are pruned (plan: "nur fertige, älter als
    /// 18 Monate"): of them the newest `keepFinished` stay, and one beyond that quota is dropped only when it is
    /// older than `pruneMonths`. Open entries and series markers are never pruned; sources and schema stay.
    /// The stored format does not change.
    public func pruned(now: Date = Date(), keepFinished: Int = 1500) -> ProgressBook {
        guard entries.count > keepFinished else { return self }
        let finished = entries.values.filter { $0.finished && !Self.isSeriesMarker($0) }
        guard finished.count > keepFinished else { return self }
        let cutoff = Self.pruneCalendar.date(byAdding: .month, value: -Self.pruneMonths, to: now) ?? now
        let gone = finished.sorted { $0.updated != $1.updated ? $0.updated > $1.updated : $0.id < $1.id }
            .dropFirst(max(0, keepFinished)).filter { $0.updated < cutoff }.map(\.id)
        guard !gone.isEmpty else { return self }
        var out = self
        for id in gone { out.entries[id] = nil }
        return out
    }

    /// Task 2.1 (W-B-1): a watched entry loses its checkmark only after the new session ran past both limits.
    public static let unfinishFraction = 0.05
    /// Task 2.1 (W-B-1): seconds a session must run before it clears "watched" or the next-episode hint.
    public static let markerSeconds = 120.0

    /// Speichert eine Position. Ab 92 % gilt der Titel als gesehen.
    /// `finishedAt`: watched threshold (80 % while a sync service is connected, as there; else 92 %).
    public mutating func record(id: String, item: MetaPreview, season: Int? = nil, episode: Int? = nil,
                                position: Double, duration: Double, now: Date = Date(), finishedAt: Double = ProgressBook.finishedAt) {
        record(WatchProgress(id: id, item: item, season: season, episode: episode,
                             position: position, duration: duration, updated: now), now: now, finishedAt: finishedAt)
    }

    /// Merges a new position into the existing entry instead of replacing it (Task 2.1, W-B-1):
    /// - a watched entry stays watched unless the new session ran more than 5 % and more than 120 s;
    /// - the next-episode hint stays until the episode itself ran more than 120 s;
    /// - `remoteFraction`, title and artwork of the old entry stay when the new one does not bring them.
    public mutating func record(_ new: WatchProgress, now: Date = Date(), finishedAt: Double = ProgressBook.finishedAt) {
        guard new.duration > 0, new.position.isFinite else { return }
        let old = entries[new.id]
        let done = new.position / new.duration >= finishedAt
        let ranLong = new.position > Self.markerSeconds
        if let old, old.finished, !done, !(ranLong && new.position > Self.unfinishFraction * new.duration) { return }
        clearSeriesMarker(itemID: new.item.id, episodeID: new.id, updated: now)
        var e = new
        e.item = Self.filled(new.item, from: old?.item)
        e.position = done ? 0 : new.position
        e.updated = now
        e.finished = done
        e.nextUp = !done && (new.nextUp == true || (old?.nextUp == true && !ranLong)) ? true : nil
        e.remoteFraction = new.remoteFraction ?? old?.remoteFraction
        entries[new.id] = e
    }

    /// Fills empty title and missing artwork/text of `item` from `fallback` (same id only).
    static func filled(_ item: MetaPreview, from fallback: MetaPreview?) -> MetaPreview {
        guard let f = fallback, f.id == item.id else { return item }
        func pick(_ a: String?, _ b: String?) -> String? {
            if let a, !a.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return a }
            return b
        }
        var r = item
        r.name = pick(item.name, f.name) ?? item.name
        r.poster = pick(item.poster, f.poster)
        r.background = pick(item.background, f.background)
        r.logo = pick(item.logo, f.logo)
        r.description = pick(item.description, f.description)
        r.releaseInfo = pick(item.releaseInfo, f.releaseInfo)
        r.imdbRating = pick(item.imdbRating, f.imdbRating)
        return r
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
            let dur = entries[r.id]?.duration ?? 0
            let done = r.fraction >= Self.finishedAt
            // Task 2.1 fix round 1 (W-B-1 via sync): the same rules as `record`. A short remote session
            // (the service echoes our own scrobble) neither reopens a watched entry nor drops the next-episode hint.
            let seconds: Double? = dur > 0 ? r.fraction * dur : nil
            if let l = entries[r.id], l.finished, !done,
               !(r.fraction > Self.unfinishFraction && (seconds ?? .infinity) > Self.markerSeconds) { continue }
            let keepNextUp = !done && entries[r.id]?.nextUp == true && (seconds ?? 0) <= Self.markerSeconds
            clearSeriesMarker(itemID: r.item.id, episodeID: r.id, updated: r.updated)
            // Task 2.1 (S-13): take position and time from the service, keep the local title and artwork;
            // the service only fills what is missing locally.
            let item = entries[r.id].map { Self.filled($0.item, from: r.item) } ?? r.item
            entries[r.id] = WatchProgress(id: r.id, item: item, season: r.season, episode: r.episode,
                                          position: dur > 0 ? r.fraction * dur : 0, duration: dur, updated: r.updated,
                                          finished: done, nextUp: keepNextUp ? true : nil,
                                          remoteFraction: dur > 0 ? nil : r.fraction)
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

    /// Task 2.6: the one pruning step (`ProgressBook.pruned`); reports the number dropped through `onPruned`.
    /// Callers keep the result as their book, so the same entries are never pruned or reported twice.
    public func prune(_ book: ProgressBook, now: Date = Date()) -> ProgressBook {
        let small = book.pruned(now: now)
        let dropped = book.entries.count - small.entries.count
        if dropped > 0 { onPruned?(dropped) }
        return small
    }

    /// Task 2.6: prunes the book before every save and returns what was written.
    @discardableResult
    public func save(_ book: ProgressBook, profile: UUID, now: Date = Date()) throws -> ProgressBook {
        let small = prune(book, now: now)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try storage.write(name(profile), try enc.encode(small))
        return small
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
