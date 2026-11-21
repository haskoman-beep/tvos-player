import Foundation

/// Plattenstand der Startseiten-Kataloge (Inhalt von `TimedCache<[MetaPreview]>`), je Profil eine Datei.
/// Liegt unter Caches: tvOS darf ihn jederzeit löschen. Fehlt die Datei oder ist sie unlesbar,
/// startet die Startseite wie bisher ohne Vorab-Stand.
public struct CatalogSnapshot: Codable, Sendable, Equatable {
    public static let currentVersion = 1
    /// Je Reihe höchstens so viele Einträge (eine Startseiten-Reihe zeigt selten mehr).
    public static let maxItemsPerRow = 100
    /// Höchstens so viele Reihen; die jüngsten bleiben.
    public static let maxRows = 60
    /// Ältere Reihen werden beim Lesen verworfen (zu alt, um sie noch zu zeigen).
    public static let maxAge: TimeInterval = 14 * 24 * 3600
    /// Größere Dateien werden nicht geschrieben (Einträge je Reihe werden vorher gekürzt).
    public static let maxBytes = 4 << 20

    public struct Row: Codable, Sendable, Equatable {
        public var items: [MetaPreview]
        public var storedAt: Date
        public init(items: [MetaPreview], storedAt: Date) { self.items = items; self.storedAt = storedAt }
    }

    public var version: Int
    public var rows: [String: Row]

    public init(rows: [String: Row]) {
        version = Self.currentVersion
        self.rows = rows
    }

    /// Aus den Cache-Einträgen: leere Reihen weglassen, Einträge kürzen, höchstens `maxRows` (jüngste zuerst).
    public init(entries: [String: TimedCache<[MetaPreview]>.Entry], itemsPerRow: Int = maxItemsPerRow) {
        let kept = entries.filter { !$0.value.value.isEmpty }
            .sorted { $0.value.storedAt == $1.value.storedAt ? $0.key < $1.key : $0.value.storedAt > $1.value.storedAt }
            .prefix(Self.maxRows)
        var rows: [String: Row] = [:]
        for (k, e) in kept { rows[k] = Row(items: Array(e.value.prefix(itemsPerRow)), storedAt: e.storedAt) }
        self.init(rows: rows)
    }

    public static func fileName(profile: UUID) -> String { "catalog-\(profile.uuidString).json" }

    /// JSON-Daten; ist das Ergebnis zu groß, werden die Reihen schrittweise gekürzt. nil = nichts zu schreiben.
    public static func encode(entries: [String: TimedCache<[MetaPreview]>.Entry], maxBytes: Int = maxBytes) -> Data? {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        var perRow = maxItemsPerRow
        while perRow >= 10 {
            let snap = CatalogSnapshot(entries: entries, itemsPerRow: perRow)
            guard !snap.rows.isEmpty else { return nil }
            if let d = try? enc.encode(snap), d.count <= maxBytes { return d }
            perRow /= 2
        }
        return nil
    }

    /// Lesen: falsche Version oder kaputte Daten → nil; zu alte Reihen fallen weg,
    /// Zeitpunkte in der Zukunft (Uhr verstellt) werden auf `now` gesetzt.
    public static func decode(_ data: Data, now: Date = Date()) -> CatalogSnapshot? {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        guard var snap = try? dec.decode(CatalogSnapshot.self, from: data), snap.version == currentVersion else { return nil }
        snap.rows = snap.rows.compactMapValues { r in
            guard !r.items.isEmpty, now.timeIntervalSince(r.storedAt) < maxAge else { return nil }
            return Row(items: r.items, storedAt: min(r.storedAt, now))
        }
        return snap
    }

    /// Alter der ältesten Reihe (für die Log-Zeile).
    public func oldestAge(now: Date = Date()) -> TimeInterval? {
        rows.values.map { now.timeIntervalSince($0.storedAt) }.max()
    }

    /// In den Cache übernehmen (nur fehlende Schlüssel, nur ohne Leeren seit `generation`). Gibt die Zahl zurück.
    @discardableResult
    public func restore(into cache: inout TimedCache<[MetaPreview]>, generation: Int) -> Int {
        var n = 0
        for (k, r) in rows.sorted(by: { $0.key < $1.key }) where cache.restore(r.items, for: k, storedAt: r.storedAt, generation: generation) {
            n += 1
        }
        return n
    }
}
