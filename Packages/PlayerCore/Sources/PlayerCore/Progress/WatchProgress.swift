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

    /// Phase 0a.1: always in 0…1, also for an entry with bad numbers (see `ProgressNumbers`).
    public var fraction: Double {
        let d = ProgressNumbers.storedDuration(duration)
        if d > 0 { return ProgressNumbers.unit(ProgressNumbers.storedPosition(position, duration: d) / d) }
        return ProgressNumbers.storedFraction(remoteFraction) ?? 0
    }

    /// Phase 0a.1: the entry with every number repaired by the stored rules of `ProgressNumbers` (negative or
    /// non-finite position → 0, negative or non-finite length → 0 = unknown, position beyond the length → the length,
    /// `remoteFraction` clamped to 0…1 or nil when non-finite, date into `.distantPast`…`.distantFuture`). All other
    /// fields stay. A good entry comes back unchanged.
    func normalized() -> WatchProgress {
        var e = self
        e.duration = ProgressNumbers.storedDuration(duration)
        e.position = ProgressNumbers.storedPosition(position, duration: e.duration)
        e.remoteFraction = ProgressNumbers.storedFraction(remoteFraction)
        e.updated = ProgressNumbers.date(updated)
        return e
    }
}

/// Phase 0a.1: same keys as the synthesized form (optional fields left out when nil). Decoding repairs bad numbers
/// field by field instead of failing; encoding writes the repaired entry, so a bad number put into `entries`
/// directly can never make JSONEncoder fail.
extension WatchProgress {
    private enum Keys: String, CodingKey {
        case id, item, season, episode, position, duration, updated, finished, nextUp, remoteFraction
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  item: try c.decode(MetaPreview.self, forKey: .item),
                  season: try c.decodeIfPresent(Int.self, forKey: .season),
                  episode: try c.decodeIfPresent(Int.self, forKey: .episode),
                  position: try c.decode(Double.self, forKey: .position),
                  duration: try c.decode(Double.self, forKey: .duration),
                  updated: try c.decode(Date.self, forKey: .updated),
                  finished: try c.decode(Bool.self, forKey: .finished),
                  nextUp: try c.decodeIfPresent(Bool.self, forKey: .nextUp),
                  remoteFraction: try c.decodeIfPresent(Double.self, forKey: .remoteFraction))
        self = normalized()
    }

    public func encode(to encoder: Encoder) throws {
        let e = normalized()
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(e.id, forKey: .id)
        try c.encode(e.item, forKey: .item)
        try c.encodeIfPresent(e.season, forKey: .season)
        try c.encodeIfPresent(e.episode, forKey: .episode)
        try c.encode(e.position, forKey: .position)
        try c.encode(e.duration, forKey: .duration)
        try c.encode(e.updated, forKey: .updated)
        try c.encode(e.finished, forKey: .finished)
        try c.encodeIfPresent(e.nextUp, forKey: .nextUp)
        try c.encodeIfPresent(e.remoteFraction, forKey: .remoteFraction)
    }
}

public struct ProgressBook: Codable, Sendable, Equatable {
    public static let finishedAt = 0.92
    public static let minimumSeconds = 60.0
    public var schemaVersion = 1
    public var entries: [String: WatchProgress] = [:] {
        // Build 4 follow-up S4: every change of the entries (also direct writes from outside) drops the
        // `latest(forItem:)` index; the next lookup builds it once. `oldValue` is not used, so subscript writes stay
        // in place (SE-0268). A box shared with a copy is never touched: that copy keeps its own, still valid index.
        didSet {
            if isKnownUniquelyReferenced(&latestIndex) { latestIndex.reset() } else { latestIndex = LatestIndex() }
        }
    }
    /// Zuletzt gespielte Quelle je Film bzw. Serie (Schlüssel: IMDb-ID ohne Staffel/Folge). Optional für alte Dateien.
    public var sources: [String: LastSource]?
    /// Build 4 follow-up S4: item id → newest entry, built lazily from `entries`. Not stored (see `CodingKeys`) and
    /// not part of `==`.
    private var latestIndex = LatestIndex()

    /// The stored format of Build 3: these three keys, in this order; the index stays out.
    private enum CodingKeys: String, CodingKey { case schemaVersion, entries, sources }

    public init() {}

    public static func == (a: ProgressBook, b: ProgressBook) -> Bool {
        a.schemaVersion == b.schemaVersion && a.entries == b.entries && a.sources == b.sources
    }

    /// Tests: how often this book's index was built (a lookup without a change in between builds nothing).
    var latestIndexBuilds: Int { latestIndex.builds }

    /// Schlüssel für `sources`: "tt123:1:2" → "tt123".
    public static func sourceKey(_ id: String) -> String { String(id.split(separator: ":").first ?? Substring(id)) }

    public mutating func rememberSource(_ stream: StreamItem, addon: String, for id: String, now: Date = Date()) {
        var all = sources ?? [:]
        all[Self.sourceKey(id)] = LastSource(stream: stream, addon: addon, contentID: id, savedAt: ProgressNumbers.date(now))
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
        // Phase 0a (finding 7): a stream without a known length reports an infinite duration; JSON cannot encode it,
        // so every later save of the book would fail.
        // Phase 0a.1: NaN/±infinity, a length ≤ 0 or a negative position → the report is ignored, the existing entry
        // stays as it was (no clamp to 0, that would erase real progress on a player glitch).
        guard ProgressNumbers.isUsableReport(position: new.position, duration: new.duration) else { return }
        var new = new
        new.position = min(new.position, new.duration)   // beyond the end (player overshoot): the end, then the 92 % rule
        new.remoteFraction = ProgressNumbers.storedFraction(new.remoteFraction)
        let stamp = ProgressNumbers.date(now)
        let old = entries[new.id]
        let done = new.position / new.duration >= finishedAt
        let ranLong = new.position > Self.markerSeconds
        if let old, old.finished, !done, !(ranLong && new.position > Self.unfinishFraction * new.duration) { return }
        clearSeriesMarker(itemID: new.item.id, episodeID: new.id, updated: stamp)
        var e = new
        e.item = Self.filled(new.item, from: old?.item)
        e.position = done ? 0 : new.position
        e.updated = stamp
        e.finished = done
        e.nextUp = !done && (new.nextUp == true || (old?.nextUp == true && !ranLong)) ? true : nil
        e.remoteFraction = new.remoteFraction ?? ProgressNumbers.storedFraction(old?.remoteFraction)
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
                                    position: 0, duration: 0, updated: ProgressNumbers.date(now), finished: false, nextUp: true)
    }

    /// Wo weitermachen? nil = von vorn (nie gestartet, < 1 min oder gesehen).
    /// Phase 0a.1: from the repaired entry, so always finite and inside 0…duration (when the length is known).
    public func resumePosition(for id: String) -> Double? {
        guard let e = entries[id]?.normalized(), !e.finished, e.position >= Self.minimumSeconds else { return nil }
        return e.position
    }

    /// Weiterschauen: angefangene Titel, neueste zuerst, eine Kachel pro Serie.
    /// Phase 0a.1: the entries come out repaired (`WatchProgress.normalized`).
    public func continueWatching(limit: Int = 30) -> [WatchProgress] {
        var seen = Set<String>()
        // Split into typed steps: as one chain the compiler gave up type-checking it (CI run 46083510692).
        let repaired: [WatchProgress] = entries.values.map { (e: WatchProgress) -> WatchProgress in e.normalized() }
        let open: [WatchProgress] = repaired.filter { (e: WatchProgress) -> Bool in
            if e.finished { return false }
            return e.position >= Self.minimumSeconds || e.nextUp == true || (e.remoteFraction ?? 0) > 0
        }
        let newestFirst: [WatchProgress] = open.sorted { (a: WatchProgress, b: WatchProgress) -> Bool in a.updated > b.updated }
        let onePerItem: [WatchProgress] = newestFirst.filter { (e: WatchProgress) -> Bool in seen.insert(e.item.id).inserted }
        return Array(onePerItem.prefix(limit))
    }

    /// Task 3.8 ([04 §6.5]): play targets of the continue row in one pass: item id → its entry in
    /// `continueWatching()`, only entries with a remembered source (those start right away, the rest opens the
    /// detail page). The row builds this once, not once per card on every focus step.
    public func resumeTargets(limit: Int = 30) -> [String: WatchProgress] {
        var out: [String: WatchProgress] = [:]
        for e in continueWatching(limit: limit) where lastSource(for: e.id) != nil { out[e.item.id] = e }
        return out
    }

    /// Neuester Eintrag einer Serie (für die Staffelauswahl auf der Detailseite).
    /// Build 4 follow-up S4: answered from the per-item index (three calls per new card on the home page used to
    /// filter all entries each). Same result as the former scan, ties included (see `LatestIndex.build`).
    public func latest(forItem itemID: String) -> WatchProgress? {
        latestIndex.latest(forItem: itemID, in: entries)?.normalized()   // Phase 0a.1: repaired, like every way out
    }

    public func isWatched(_ id: String) -> Bool { entries[id]?.finished == true }

    /// Zustand für eine Kachel: Fortschritt, Restzeit, gesehen, Folge.
    public func cardState(itemID: String) -> CardState? {
        // Phase 0a.1: from the repaired entry: fraction in 0…1, remaining time ≥ 0 and finite.
        if let e = entries[itemID]?.normalized(), e.season == nil {
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
        guard let e = entries[id]?.normalized(), !e.finished, e.duration == 0, let f = e.remoteFraction, f > 0.01, f < Self.finishedAt else { return nil }
        return f
    }

    /// Angefangenes aus dem Sync-Dienst übernehmen; neuerer lokaler Stand gewinnt.
    /// Phase 0a.1: a remote fraction that is non-finite or negative is ignored (the local entry stays); above 1 it
    /// counts as 1 (watched). A non-finite or absurd remote date is repaired like a stored one (`ProgressNumbers.date`).
    public mutating func merge(remote: [RemoteProgress]) {
        for var r in remote {
            guard ProgressNumbers.isUsableRemoteFraction(r.fraction) else { continue }
            r.fraction = min(1, r.fraction)
            r.updated = ProgressNumbers.date(r.updated)
            if let l = entries[r.id], ProgressNumbers.date(l.updated) >= r.updated { continue }
            // Wave L: an episode paused before the series was marked as watched stays out.
            if r.id != r.item.id, let m = entries[r.item.id], m.season == nil, m.finished, ProgressNumbers.date(m.updated) >= r.updated { continue }
            let dur = ProgressNumbers.storedDuration(entries[r.id]?.duration ?? 0)
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

extension ProgressBook {
    /// Phase 0a.1: the stored format of Build 3 (`schemaVersion`, `entries`, optional `sources`), read entry by
    /// entry: an entry that cannot be read at all (a number JSONDecoder refuses such as `1e400`, a wrong type) is
    /// dropped and noted in the `DecodeReport`, the other entries stay. Bad but readable numbers are repaired by
    /// `WatchProgress.init(from:)`. A missing `schemaVersion` or `entries` key still fails, as before.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        entries = try c.decode([String: FailableDecodable<WatchProgress>].self, forKey: .entries).compactMapValues(\.value)
        sources = try c.decodeIfPresent([String: FailableDecodable<LastSource>].self, forKey: .sources)?
            .compactMapValues(\.value)
    }
}

/// Build 4 follow-up S4: the `latest(forItem:)` index of one `ProgressBook` value. Built on the first lookup after
/// a change, from the entries handed in; the book resets or replaces it on every change of its entries, so a built
/// index always belongs to the entries of the values that share it. Locked, because a book is `Sendable` and
/// copies may be read from several threads.
final class LatestIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var byItem: [String: WatchProgress]?
    private var buildCount = 0

    var builds: Int {
        lock.lock(); defer { lock.unlock() }
        return buildCount
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        byItem = nil
    }

    func latest(forItem itemID: String, in entries: [String: WatchProgress]) -> WatchProgress? {
        lock.lock(); defer { lock.unlock() }
        if let byItem { return byItem[itemID] }
        let built = Self.build(entries)
        byItem = built; buildCount += 1
        return built[itemID]
    }

    /// The former rule in one pass: per item, the entry with the latest `updated`; on equal dates the first one in
    /// the dictionary's iteration order stays (like `max(by:)`, which replaces only on a strictly later date).
    static func build(_ entries: [String: WatchProgress]) -> [String: WatchProgress] {
        var out: [String: WatchProgress] = [:]
        out.reserveCapacity(entries.count)
        for e in entries.values {
            if let have = out[e.item.id], !(have.updated < e.updated) { continue }
            out[e.item.id] = e
        }
        return out
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
        if let r = try? dec.decodeReporting(ProgressBook.self, from: d) {
            // Phase 0a.1: an entry that could not be read is left out of the book; the file as it was stays as .bak.
            if !r.report.isEmpty { try? storage.write(name(profile) + ".bak", d) }
            return r.value
        }
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
    /// Task 3.8: the rules live in `match(in: [RankedStream])`; the same file is found without parsing anything.
    public func match(in streams: [(addon: String, stream: StreamItem)]) -> StreamItem? {
        let list = streams.filter { $0.stream.url != nil }
        if let e = list.first(where: { Self.fileKey($0.stream) == fingerprint }) { return e.stream }
        return match(in: RankedStream.rank(list))
    }
}

extension LastSource {
    /// Same keys as the synthesized form (decoding stays synthesized).
    private enum EncodeKeys: String, CodingKey { case addon, name, fingerprint, bingeGroup, contentID, savedAt }

    /// Phase 0a.1: the date goes out repaired (`ProgressNumbers.date`), so a bad `savedAt` cannot make the default
    /// JSONEncoder of the backup fail on a NaN time or the ISO 8601 form of `ProgressStore` become unreadable.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: EncodeKeys.self)
        try c.encode(addon, forKey: .addon)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encode(fingerprint, forKey: .fingerprint)
        try c.encodeIfPresent(bingeGroup, forKey: .bingeGroup)
        try c.encode(contentID, forKey: .contentID)
        try c.encode(ProgressNumbers.date(savedAt), forKey: .savedAt)
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
        return entries.values.map { $0.normalized() }   // Phase 0a.1: repaired, sorted by sane dates
            .filter { $0.finished }
            .sorted { $0.updated > $1.updated }
            .filter { seen.insert($0.item.id).inserted }
            .prefix(limit).map { $0 }
    }
}
