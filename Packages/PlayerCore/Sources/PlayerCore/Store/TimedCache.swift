import Foundation

/// Speicher-Cache mit Ablaufzeit nach dem Muster „alten Stand zeigen, im Hintergrund erneuern“.
/// Abgelaufene Einträge bleiben lesbar; `needsRefresh` sagt, ob eine Erneuerung fällig ist.
/// Nach einem Fehlschlag wird frühestens nach `retryAfter` erneut versucht.
public struct TimedCache<Value: Sendable>: Sendable {
    public struct Entry: Sendable {
        public var value: Value
        public var storedAt: Date
        public var failedAt: Date?
        /// Aus dem Plattencache übernommen: beim ersten Zugriff einmal erneuern, auch wenn noch frisch.
        public var restored = false
    }

    public var lifetime: TimeInterval
    public var retryAfter: TimeInterval
    public private(set) var entries: [String: Entry] = [:]
    /// Steigt bei jedem `removeAll` (Profilwechsel, neues Addon …). Ein Abruf, der vorher begonnen hat,
    /// legt sein Ergebnis über `store(_:for:generation:)` dann nicht mehr ab.
    public private(set) var generation = 0

    public init(lifetime: TimeInterval = 24 * 3600, retryAfter: TimeInterval = 10 * 60) {
        self.lifetime = lifetime; self.retryAfter = retryAfter
    }

    public subscript(key: String) -> Value? { entries[key]?.value }

    public func storedAt(_ key: String) -> Date? { entries[key]?.storedAt }

    public func isStale(_ key: String, now: Date = Date()) -> Bool {
        guard let e = entries[key] else { return true }
        return now.timeIntervalSince(e.storedAt) >= lifetime
    }

    /// Abgelaufen und nicht gerade erst fehlgeschlagen.
    public func needsRefresh(_ key: String, now: Date = Date()) -> Bool {
        guard let e = entries[key], e.restored || isStale(key, now: now) else { return false }
        if let f = e.failedAt, now.timeIntervalSince(f) < retryAfter { return false }
        return true
    }

    /// Alle Schlüssel, deren Erneuerung fällig ist. `includingRestored: false` lässt Einträge aus dem
    /// Plattencache weg, die noch nie gezeigt wurden (die erneuern sich beim ersten Zeigen ohnehin).
    public func keysNeedingRefresh(now: Date = Date(), includingRestored: Bool = true) -> [String] {
        entries.keys.filter { (includingRestored || entries[$0]?.restored != true) && needsRefresh($0, now: now) }.sorted()
    }

    public mutating func store(_ value: Value, for key: String, now: Date = Date()) {
        entries[key] = Entry(value: value, storedAt: now, failedAt: nil)
    }

    /// Nur ablegen, wenn seit Beginn des Abrufs nicht geleert wurde. Gibt zurück, ob abgelegt wurde.
    @discardableResult
    public mutating func store(_ value: Value, for key: String, generation: Int, now: Date = Date()) -> Bool {
        guard generation == self.generation else { return false }
        store(value, for: key, now: now)
        return true
    }

    /// Erneuerung fehlgeschlagen: alten Wert behalten, später wieder versuchen.
    public mutating func markFailed(_ key: String, now: Date = Date()) {
        entries[key]?.failedAt = now
    }

    public mutating func removeAll() { entries.removeAll(); generation += 1 }

    /// Gespeicherten Stand übernehmen (Plattencache beim Start). Überschreibt keinen vorhandenen Eintrag
    /// und nichts nach einem Leeren seit `generation`. Der Eintrag gilt als erneuerungsbedürftig.
    @discardableResult
    public mutating func restore(_ value: Value, for key: String, storedAt: Date, generation: Int) -> Bool {
        guard generation == self.generation, entries[key] == nil else { return false }
        entries[key] = Entry(value: value, storedAt: storedAt, failedAt: nil, restored: true)
        return true
    }
}

public extension TimedCache where Value: Collection {
    /// Hintergrund-Erneuerung ablegen: wie `store(_:for:generation:)`, aber eine leere Antwort
    /// überschreibt keine gefüllte Liste (gedrosselte Addons liefern gern `[]`).
    @discardableResult
    mutating func storeRefreshed(_ value: Value, for key: String, generation: Int, now: Date = Date()) -> Bool {
        if value.isEmpty, let old = self[key], !old.isEmpty { return false }
        return store(value, for: key, generation: generation, now: now)
    }
}
