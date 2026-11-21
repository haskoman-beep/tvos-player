import Foundation

/// „Alten Stand sofort zeigen, im Hintergrund erneuern“ als reine Zeitregel.
/// - `fresh`: zurückgeben, nichts weiter.
/// - `stale`: zurückgeben und im Hintergrund neu abfragen (das Ergebnis ersetzt den Stand erst vollständig).
/// - `expired`: nicht mehr zeigen, neu abfragen und darauf warten.
public struct RevalidationPolicy: Sendable, Equatable {
    public enum State: Sendable, Equatable { case fresh, stale, expired }

    /// Bis zu diesem Alter gilt ein Stand als frisch.
    public var freshFor: TimeInterval
    /// Bis zu diesem Alter wird ein Stand noch gezeigt (mit Erneuerung im Hintergrund).
    public var usableFor: TimeInterval

    public init(freshFor: TimeInterval, usableFor: TimeInterval) {
        self.freshFor = freshFor
        self.usableFor = max(freshFor, usableFor)
    }

    public func state(age: TimeInterval) -> State {
        if age < 0 { return .stale }            // Uhr zurückgestellt: zeigen, aber erneuern
        if age < freshFor { return .fresh }
        if age < usableFor { return .stale }
        return .expired
    }

    public func state(storedAt: Date, now: Date = Date()) -> State { state(age: now.timeIntervalSince(storedAt)) }

    /// Noch zeigbar (frisch oder veraltet).
    public func isUsable(storedAt: Date, now: Date = Date()) -> Bool { state(storedAt: storedAt, now: now) != .expired }

    /// Quellenlisten: 90 s frisch (Detailseite → Quellenliste ohne neue Abfrage), bis 30 min sofort sichtbar
    /// und im Hintergrund erneuert (TorBox-Links und Cache-Status veralten), danach neu laden.
    public static let streams = RevalidationPolicy(freshFor: 90, usableFor: 30 * 60)

    /// Hintergrund-Erneuerung erlaubt? Nicht nach einer frisch leeren Antwort (`emptyUntil` liegt in der Zukunft)
    /// und nicht in der Pause nach „alle Addons leer“ (vermutlich Ratenbegrenzung): sonst verschärft jedes
    /// Öffnen die Begrenzung mit einer weiteren Vollabfrage. Der alte Stand wird weiter gezeigt.
    public static func revalidationAllowed(emptyUntil: Date?, allEmptyAt: Date?, pause: TimeInterval, now: Date = Date()) -> Bool {
        if let u = emptyUntil, u > now { return false }
        if let t = allEmptyAt, now.timeIntervalSince(t) < pause { return false }
        return true
    }
}

/// Quellenliste nach einer Erneuerung: Addons, die diesmal nicht geantwortet haben (Fehler, Zeitüberschreitung),
/// behalten ihre bisherigen Einträge, hinten in alter Reihenfolge, aber nur bis zu ihrem eigenen Abrufzeitpunkt
/// plus `maxAge` (sonst blieben Einträge eines dauerhaft ausfallenden Addons mit veraltetem Cache-Status und
/// toten Links ewig drin). Nur Addons, die noch eingerichtet sind. Ist das neue Ergebnis leer oder hat kein
/// Addon geantwortet, bleibt es unverändert: leer ersetzt keinen Stand (und hält die Pause nach leerer Antwort).
public enum StreamListMerge {
    public struct Result<T> {
        public var list: [(addon: String, stream: T)]
        /// Abrufzeitpunkt je Addon für den neuen Stand (geantwortet → `now`, behalten → alter Zeitpunkt).
        public var fetchedAt: [String: Date]
    }

    public static func keepingFailed<T>(fresh: [(addon: String, stream: T)], previous: [(addon: String, stream: T)]?,
                                        previousStoredAt: Date, previousFetchedAt: [String: Date],
                                        answered: Set<String>, configured: Set<String>,
                                        now: Date = Date(), maxAge: TimeInterval) -> Result<T> {
        var fetchedAt: [String: Date] = [:]
        for a in answered { fetchedAt[a] = now }
        guard let previous, !answered.isEmpty, !fresh.isEmpty else { return Result(list: fresh, fetchedAt: fetchedAt) }
        var kept: [(addon: String, stream: T)] = []
        for e in previous where configured.contains(e.addon) && !answered.contains(e.addon) {
            let at = previousFetchedAt[e.addon] ?? previousStoredAt
            let age = now.timeIntervalSince(at)
            guard age < maxAge, age > -maxAge else { continue }
            kept.append(e)
            fetchedAt[e.addon] = at
        }
        return Result(list: fresh + kept, fetchedAt: fetchedAt)
    }
}
