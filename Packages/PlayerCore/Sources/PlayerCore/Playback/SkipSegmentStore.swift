import Foundation

/// IntroDB-Antworten auf dem Gerät (über `BlobStorage`), mit Laufzeit der Datei, sobald sie gespielt wurde.
/// Antworten mit Marken gelten `maxAge`, „keine Marken“ (der Dienst antwortete, kennt aber nichts) nur
/// `emptyMaxAge`, damit neu eingetragene Marken bald ankommen. Fehler werden nie gemerkt.
public struct SkipSegmentStore: Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var segments: [SkipSegment]
        /// Laufzeit der gespielten Datei (für den Abspann der Staffel-Schätzung); nil = unbekannt.
        public var duration: Double?
        public var savedAt: Date

        public init(segments: [SkipSegment], duration: Double? = nil, savedAt: Date) {
            self.segments = segments; self.duration = duration; self.savedAt = savedAt
        }
    }

    public static let fileName = "introdb-cache.json"
    /// Höchstens so viele Folgen/Filme; die ältesten fallen zuerst heraus.
    public static let maxEntries = 400
    /// Einträge gelten so lange (danach erneut abfragen).
    public static let maxAge: TimeInterval = 60 * 24 * 3600
    /// „Keine Marken“ gilt so lange (5 Tage).
    public static let emptyMaxAge: TimeInterval = 5 * 24 * 3600

    public private(set) var entries: [String: Entry] = [:]

    public init(entries: [String: Entry] = [:]) { self.entries = entries }

    /// Schlüssel: Serien-/Film-ID, bei Folgen Staffel und Folge.
    public static func key(_ q: IntroDBQuery) -> String {
        let id = q.imdb.split(separator: ":").first.map(String.init) ?? q.imdb
        if q.isMovie { return "\(id)|m" }
        return "\(id)|\(q.season ?? 0)|\(q.episode ?? 0)"
    }

    /// Gültigkeit eines Eintrags (leer = „keine Marken“, kürzer).
    static func isValid(_ e: Entry, now: Date) -> Bool {
        now.timeIntervalSince(e.savedAt) < (e.segments.isEmpty ? emptyMaxAge : maxAge)
    }

    /// Gültiger Eintrag (nicht zu alt) oder nil. Ein Eintrag mit leerer Liste heißt „keine Marken, nicht erneut fragen“.
    public func entry(_ q: IntroDBQuery, now: Date = Date()) -> Entry? {
        guard let e = entries[Self.key(q)], Self.isValid(e, now: now) else { return nil }
        return e
    }

    /// Antwort merken (leere Liste = „keine Marken“, kurze Gültigkeit). Eine schon bekannte Laufzeit bleibt erhalten.
    /// Ein gültiger Eintrag mit Marken wird nicht durch „keine Marken“ ersetzt.
    public mutating func store(_ segments: [SkipSegment], for q: IntroDBQuery, now: Date = Date()) {
        let k = Self.key(q)
        if segments.isEmpty, let old = entries[k], !old.segments.isEmpty, Self.isValid(old, now: now) { return }
        entries[k] = Entry(segments: segments, duration: entries[k]?.duration, savedAt: now)
        trim(now: now)
    }

    /// Laufzeit der gespielten Datei nachtragen (nur für bekannte Einträge). true = geändert.
    @discardableResult
    public mutating func noteDuration(_ duration: Double, for q: IntroDBQuery) -> Bool {
        let k = Self.key(q)
        guard duration.isFinite, duration > 60, var e = entries[k] else { return false }
        if let old = e.duration, abs(old - duration) < 1 { return false }
        e.duration = duration
        entries[k] = e
        return true
    }

    /// Andere Folgen derselben Staffel (gültige Einträge).
    public func seasonNeighbors(of q: IntroDBQuery, now: Date = Date()) -> [Entry] {
        guard !q.isMovie, let s = q.season, let ep = q.episode else { return [] }
        let id = q.imdb.split(separator: ":").first.map(String.init) ?? q.imdb
        let prefix = "\(id)|\(s)|"
        return entries.compactMap { k, e in
            guard k.hasPrefix(prefix), k != "\(prefix)\(ep)", Self.isValid(e, now: now) else { return nil }
            return e
        }
    }

    /// Folgen, die für die Schätzung abgefragt werden (Nachbarn zuerst), ohne die eigene und ohne Folge < 1.
    public static func neighborEpisodes(of episode: Int, count: Int = 4) -> [Int] {
        var out: [Int] = []
        var d = 1
        while out.count < count, d <= count + 1 {
            for e in [episode - d, episode + d] where e >= 1 && out.count < count { out.append(e) }
            d += 1
        }
        return out
    }

    // MARK: Ablage

    public static func load(from storage: BlobStorage) -> SkipSegmentStore {
        guard let data = storage.read(fileName),
              let e = try? JSONDecoder().decode([String: Entry].self, from: data) else { return SkipSegmentStore() }
        return SkipSegmentStore(entries: e)
    }

    public func save(to storage: BlobStorage) throws {
        try storage.write(Self.fileName, try JSONEncoder().encode(entries))
    }

    private mutating func trim(now: Date) {
        entries = entries.filter { Self.isValid($0.value, now: now) }
        guard entries.count > Self.maxEntries else { return }
        let keep = entries.sorted { $0.value.savedAt > $1.value.savedAt }.prefix(Self.maxEntries)
        entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }
}

/// Schätzung für eine Folge ohne Marken aus anderen Folgen derselben Staffel („Konsens“).
/// - Intro/Rückblick: ab zwei Folgen mit dieser Art, Start und Länge als Median; liegen die Starts mehr als
///   `maxSpread` auseinander, gibt es keine Schätzung (Intro wandert).
/// - Abspann: Abstand zum Dateiende als Median (nur Folgen mit bekannter Laufzeit), Ende = Dateiende.
/// Kein Auto-Sprung: das Ergebnis steuert nur Knopf, Zeitleiste und Nächste-Folge-Karte.
public enum SeasonSkipEstimate {
    public static let minEpisodes = 2
    public static let maxSpread: Double = 30

    public static func estimate(from neighbors: [SkipSegmentStore.Entry], duration: Double) -> [SkipSegment] {
        var out: [SkipSegment] = []
        for kind in [SkipSegment.Kind.intro, .recap] {
            let found = neighbors.compactMap { $0.segments.first { $0.kind == kind && $0.source != .seasonEstimate } }
            guard found.count >= minEpisodes else { continue }
            let starts = found.map(\.start)
            guard let lo = starts.min(), let hi = starts.max(), hi - lo <= maxSpread else { continue }
            let start = median(starts), length = median(found.map(\.length))
            guard length >= 1 else { continue }
            var seg = SkipSegment(kind: kind, start: start, end: start + length, source: .seasonEstimate)
            if duration > 0 { guard seg.start < duration else { continue }; seg.end = min(seg.end, duration) }
            out.append(seg)
        }
        if duration > 0 {
            let offsets: [Double] = neighbors.compactMap { e in
                guard let d = e.duration, let c = e.segments.first(where: { $0.kind == .credits }), c.start < d else { return nil }
                return d - c.start
            }
            if offsets.count >= minEpisodes, let lo = offsets.min(), let hi = offsets.max(), hi - lo <= maxSpread {
                let start = duration - median(offsets)
                if start > 0, start >= SkipSegments.creditsMinFraction * duration {
                    out.append(SkipSegment(kind: .credits, start: start, end: duration, source: .seasonEstimate))
                }
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    static func median(_ v: [Double]) -> Double {
        let s = v.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}

/// Marke auf der Zeitleiste (Anteile 0…1 der Laufzeit).
public struct TimelineMark: Sendable, Equatable, Hashable {
    public var kind: SkipSegment.Kind
    public var from: Double
    public var to: Double
    public init(kind: SkipSegment.Kind, from: Double, to: Double) { self.kind = kind; self.from = from; self.to = to }
}

extension SkipSegments {
    /// Bereiche als Anteile der Laufzeit (für farbige Abschnitte auf der Zeitleiste). Ohne Laufzeit: keine.
    public static func timelineMarks(_ segments: [SkipSegment], duration: Double) -> [TimelineMark] {
        guard duration.isFinite, duration > 0 else { return [] }
        return segments.compactMap { s in
            let from = min(max(s.start / duration, 0), 1), to = min(max(s.end / duration, 0), 1)
            return to - from > 0 ? TimelineMark(kind: s.kind, from: from, to: to) : nil
        }
    }

    /// Rastkanten fürs Spulen: Anfang und Ende jedes Bereichs.
    public static func snapEdges(_ segments: [SkipSegment]) -> [Double] {
        segments.flatMap { [$0.start, $0.end] }
    }
}
