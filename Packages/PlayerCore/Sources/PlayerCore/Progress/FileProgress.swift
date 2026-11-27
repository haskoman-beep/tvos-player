import Foundation

/// Fortschritt für Dateien ohne IMDb-ID (Welle D-a, M-T2: TorBox „Meine Dateien“). Eigene Ablage, getrennt von
/// `ProgressBook`: diese Einträge erscheinen nicht in Weiterschauen und gehen nie an Trakt/Simkl.
/// Schlüssel ist die Datei-ID des Dienstes (z. B. "torbox:123:4"). Höchstens `limit` Einträge.
public struct FileProgressBook: Codable, Sendable, Equatable {
    public static let limit = 200

    public struct Entry: Codable, Sendable, Equatable {
        public var position: Double
        public var duration: Double
        public var updated: Date
        public var finished: Bool
    }

    public var entries: [String: Entry]

    public init(entries: [String: Entry] = [:]) { self.entries = entries }

    /// Gleiche Regeln wie `ProgressBook.record`: ab 92 % gesehen (Position 0).
    /// Phase 0a.1: the same number rules too (`ProgressNumbers`): NaN/±infinity, a length ≤ 0 or a negative position
    /// → the report is ignored and the existing entry stays; a position beyond the length counts as the length.
    public mutating func record(_ key: String, position: Double, duration: Double, now: Date = Date()) {
        guard ProgressNumbers.isUsableReport(position: position, duration: duration) else { return }
        let p = min(position, duration)
        let done = p / duration >= ProgressBook.finishedAt
        entries[key] = Entry(position: done ? 0 : p, duration: duration, updated: ProgressNumbers.date(now), finished: done)
        prune()
    }

    /// Wo weitermachen? nil = von vorn (nie gestartet, unter einer Minute oder gesehen).
    /// Phase 0a.1: from the repaired entry, so always finite and inside 0…duration (when the length is known).
    public func resumePosition(for key: String) -> Double? {
        guard let e = entries[key]?.normalized(), !e.finished, e.position >= ProgressBook.minimumSeconds else { return nil }
        return e.position
    }

    public func isWatched(_ key: String) -> Bool { entries[key]?.finished == true }

    /// Anteil für den Balken auf der Kachel (nil = nicht angefangen).
    /// Phase 0a.1: from the repaired entry, so always in 0…1.
    public func fraction(for key: String) -> Double? {
        guard let e = entries[key]?.normalized(), !e.finished, e.duration > 0, e.position >= ProgressBook.minimumSeconds else { return nil }
        return min(1, e.position / e.duration)
    }

    mutating func prune() {
        guard entries.count > Self.limit else { return }
        let drop = entries.sorted { ProgressNumbers.date($0.value.updated) < ProgressNumbers.date($1.value.updated) }.prefix(entries.count - Self.limit)
        for (k, _) in drop { entries[k] = nil }
    }
}

extension FileProgressBook.Entry {
    /// Phase 0a.1: the entry with its numbers repaired like a `ProgressBook` entry (negative or non-finite position
    /// → 0, negative or non-finite length → 0 = unknown, position beyond the length → the length, date into
    /// `.distantPast`…`.distantFuture`); `finished` stays. A good entry comes back unchanged.
    func normalized() -> FileProgressBook.Entry {
        let d = ProgressNumbers.storedDuration(duration)
        return FileProgressBook.Entry(position: ProgressNumbers.storedPosition(position, duration: d), duration: d,
                                      updated: ProgressNumbers.date(updated), finished: finished)
    }

    private enum Keys: String, CodingKey { case position, duration, updated, finished }

    /// Phase 0a.1: same keys as the synthesized form; bad numbers are repaired instead of failing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(position: try c.decode(Double.self, forKey: .position),
                  duration: try c.decode(Double.self, forKey: .duration),
                  updated: try c.decode(Date.self, forKey: .updated),
                  finished: try c.decode(Bool.self, forKey: .finished))
        self = normalized()
    }

    /// Phase 0a.1: writes the repaired entry, so JSONEncoder never sees a non-finite number.
    public func encode(to encoder: Encoder) throws {
        let e = normalized()
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(e.position, forKey: .position)
        try c.encode(e.duration, forKey: .duration)
        try c.encode(e.updated, forKey: .updated)
        try c.encode(e.finished, forKey: .finished)
    }
}

extension FileProgressBook {
    private enum Keys: String, CodingKey { case entries }

    /// Phase 0a.1: read entry by entry: an entry that cannot be read at all (a number JSONDecoder refuses, a wrong
    /// type) is dropped and noted in the `DecodeReport`, the other entries stay. A missing `entries` key still fails.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(entries: try c.decode([String: FailableDecodable<Entry>].self, forKey: .entries).compactMapValues(\.value))
    }
}
