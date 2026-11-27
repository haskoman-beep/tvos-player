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
    public mutating func record(_ key: String, position: Double, duration: Double, now: Date = Date()) {
        guard duration.isFinite, duration > 0, position.isFinite, position >= 0 else { return }
        let done = position / duration >= ProgressBook.finishedAt
        entries[key] = Entry(position: done ? 0 : position, duration: duration, updated: now, finished: done)
        prune()
    }

    /// Wo weitermachen? nil = von vorn (nie gestartet, unter einer Minute oder gesehen).
    public func resumePosition(for key: String) -> Double? {
        guard let e = entries[key], !e.finished, e.position >= ProgressBook.minimumSeconds else { return nil }
        return e.position
    }

    public func isWatched(_ key: String) -> Bool { entries[key]?.finished == true }

    /// Anteil für den Balken auf der Kachel (nil = nicht angefangen).
    public func fraction(for key: String) -> Double? {
        guard let e = entries[key], !e.finished, e.duration > 0, e.position >= ProgressBook.minimumSeconds else { return nil }
        return min(1, e.position / e.duration)
    }

    mutating func prune() {
        guard entries.count > Self.limit else { return }
        let drop = entries.sorted { $0.value.updated < $1.value.updated }.prefix(entries.count - Self.limit)
        for (k, _) in drop { entries[k] = nil }
    }
}
