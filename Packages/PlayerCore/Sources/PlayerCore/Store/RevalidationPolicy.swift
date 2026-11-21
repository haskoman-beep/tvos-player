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
/// behalten ihre bisherigen Einträge, hinten in alter Reihenfolge. So ersetzt ein Teilausfall keine volle Liste
/// durch eine kleinere. Nur Addons, die noch eingerichtet sind; hat kein Addon geantwortet, bleibt das Ergebnis
/// unverändert (leer: der alte Stand bleibt ohnehin).
public enum StreamListMerge {
    public static func keepingFailed<T>(fresh: [(addon: String, stream: T)], previous: [(addon: String, stream: T)]?,
                                        answered: Set<String>, configured: Set<String>) -> [(addon: String, stream: T)] {
        guard let previous, !answered.isEmpty else { return fresh }
        let kept = previous.filter { configured.contains($0.addon) && !answered.contains($0.addon) }
        return kept.isEmpty ? fresh : fresh + kept
    }
}
