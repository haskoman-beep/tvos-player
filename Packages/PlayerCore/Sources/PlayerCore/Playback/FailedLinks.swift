import Foundation

/// Was der Player über die laufende Quelle weiß.
public enum SourceVerdict: Equatable, Sendable {
    /// Fehlerleiter schaltet weiter (mit der Fehlerklasse; ob gemerkt wird, entscheidet `FailedLinkBook.remembers`).
    case failed(PlaybackErrorClass)
    /// Platzhalter-Video statt Film.
    case placeholder
    /// `FailedLinkBook.healthySeconds` fehlerfrei gespielt.
    case healthy
}

/// Kürzlich fehlgeschlagene Quellen je Titel (8 h). Automatische Wahl und Rückfall überspringen sie,
/// die Quellenliste markiert sie, von Hand bleiben sie wählbar.
///
/// Schlüssel ist nie der Link (Debrid-Links werden jedes Mal neu signiert und enthalten Zugangsdaten),
/// sondern ein Prüfwert aus Info-Hash + Dateiname, sonst Dateiname, sonst Name + Beschreibung.
/// Grenzen: `perTitle` Quellen je Titel, `maxTitles` Titel, Verfall nach `lifetime`; aufgeräumt wird beim Schreiben
/// und beim Laden.
public struct FailedLinkBook: Codable, Sendable, Equatable {
    public static let lifetime: TimeInterval = 8 * 3600
    public static let perTitle = 6
    public static let maxTitles = 60
    /// So lange fehlerfrei gespielt: der Eintrag war ein Ausrutscher und wird gelöscht.
    public static let healthySeconds: Double = 300
    public static let storageName = "failed_links.json"

    /// Titel-ID → (Quellen-Schlüssel → Zeitpunkt des Fehlers).
    public private(set) var entries: [String: [String: Date]] = [:]

    public init() {}

    /// Stabiler Schlüssel einer Quelle (FNV-1a, 64 bit, hex).
    public static func key(for s: StreamItem) -> String {
        let basis: String
        if let h = s.infoHash?.lowercased(), !h.isEmpty {
            basis = "h:" + h + ":" + (s.behaviorHints?.filename ?? "")
        } else if let f = s.behaviorHints?.filename, !f.isEmpty {
            basis = "f:" + f
        } else {
            basis = "n:" + (s.name ?? "") + "|" + s.label
        }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in basis.utf8 { hash ^= UInt64(b); hash = hash &* 0x0000_0100_0000_01b3 }
        return String(hash, radix: 16)
    }

    /// Welche Fehler gemerkt werden: nur solche, die an der Quelle selbst liegen (Link tot, Debrid, Format,
    /// Dekoder, Platzhalter). Nicht: Netz, offline, Zeitüberschreitung („langsam ist kein Beweis für tot“),
    /// Server kurz nicht erreichbar, Drosselung, Zertifikat, Speicher, Routenwechsel.
    public static func remembers(_ cls: PlaybackErrorClass) -> Bool {
        switch cls {
        case .linkExpired, .debrid, .unsupported, .unknown: true
        case .network, .offline, .timeout, .hostUnreachable, .rateLimited, .certificate, .storage, .routeChange: false
        }
    }

    public func isRecentlyFailed(_ s: StreamItem, title: String, now: Date = Date()) -> Bool {
        guard let at = entries[title]?[Self.key(for: s)] else { return false }
        return now.timeIntervalSince(at) < Self.lifetime
    }

    /// Fehler merken (neuester gewinnt; über der Grenze fallen die ältesten heraus).
    public mutating func noteFailure(_ s: StreamItem, title: String, now: Date = Date()) {
        prune(now: now)
        var t = entries[title] ?? [:]
        t[Self.key(for: s)] = now
        if t.count > Self.perTitle {
            for (k, _) in t.sorted(by: { $0.value < $1.value }).prefix(t.count - Self.perTitle) { t[k] = nil }
        }
        entries[title] = t
        if entries.count > Self.maxTitles {
            let byNewest = entries.mapValues { $0.values.max() ?? .distantPast }
            for (k, _) in byNewest.sorted(by: { $0.value < $1.value }).prefix(entries.count - Self.maxTitles) { entries[k] = nil }
        }
    }

    /// Quelle hat lange genug gespielt: Eintrag löschen. Liefert true, wenn sich etwas geändert hat.
    @discardableResult
    public mutating func noteHealthy(_ s: StreamItem, title: String) -> Bool {
        guard entries[title]?.removeValue(forKey: Self.key(for: s)) != nil else { return false }
        if entries[title]?.isEmpty == true { entries[title] = nil }
        return true
    }

    /// Abgelaufene Einträge entfernen.
    public mutating func prune(now: Date = Date()) {
        entries = entries.compactMapValues { t in
            let kept = t.filter { now.timeIntervalSince($0.value) < Self.lifetime }
            return kept.isEmpty ? nil : kept
        }
    }

    /// Für automatische Wahlen: Liste ohne kürzlich fehlgeschlagene Quellen.
    public func excludingFailed(_ list: [StreamItem], title: String, now: Date = Date()) -> [StreamItem] {
        list.filter { !isRecentlyFailed($0, title: title, now: now) }
    }

    /// Urteil des Players über die laufende Quelle anwenden. Liefert true, wenn sich das Buch geändert hat.
    @discardableResult
    public mutating func apply(_ verdict: SourceVerdict, stream s: StreamItem, title: String, now: Date = Date()) -> Bool {
        switch verdict {
        case .failed(let cls):
            guard Self.remembers(cls) else { return false }
            noteFailure(s, title: title, now: now); return true
        case .placeholder:
            noteFailure(s, title: title, now: now); return true
        case .healthy:
            return noteHealthy(s, title: title)
        }
    }

    // MARK: Ablage

    public static func load(from storage: BlobStorage, now: Date = Date()) -> FailedLinkBook {
        guard let d = storage.read(storageName), var b = try? JSONDecoder().decode(FailedLinkBook.self, from: d) else {
            return FailedLinkBook()
        }
        b.prune(now: now)
        return b
    }

    public func save(to storage: BlobStorage) throws {
        try storage.write(Self.storageName, try JSONEncoder().encode(self))
    }
}
