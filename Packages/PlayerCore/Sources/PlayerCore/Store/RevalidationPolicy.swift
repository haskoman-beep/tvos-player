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
}
