import Foundation

/// Welle D-b (M2): Sperre nach einem gescheiterten Abruf einer Adresse und genau ein erneuter Versuch danach.
/// Nach einem Fehler ist die Adresse `pause` lang gesperrt. Danach ist ein neuer Versuch fällig (`retryDue`).
/// Sobald er läuft (`begin`), ist er nicht mehr fällig: Weitere Aufrufe brechen ihn nicht ab und starten ihn nicht neu.
/// Wird der laufende Versuch abgebrochen (Wechsel auf eine andere Adresse), ist er beim Zurückwechseln sofort
/// wieder fällig, statt ewig gesperrt zu bleiben.
public struct FetchRetryGate: Sendable, Equatable {
    public static let defaultPause: TimeInterval = 300

    public private(set) var failedKey: String?
    public private(set) var blockedUntil: Date = .distantPast
    public private(set) var lastError: String?
    /// Ein erneuter Versuch für `failedKey` läuft gerade.
    public private(set) var retrying = false

    public init() {}

    /// Für `key` ist nach abgelaufener Sperre ein neuer Versuch fällig (und läuft noch keiner).
    public func retryDue(_ key: String?, now: Date = Date()) -> Bool {
        key != nil && key == failedKey && !retrying && now >= blockedUntil
    }

    /// `key` ist noch gesperrt: kein Abruf, der letzte Fehler bleibt sichtbar.
    public func isBlocked(_ key: String?, now: Date = Date()) -> Bool {
        key != nil && key == failedKey && !retrying && now < blockedUntil
    }

    /// Ein Abruf für `key` beginnt. Ist es die gescheiterte Adresse, gilt er als laufender erneuter Versuch.
    public mutating func begin(_ key: String) {
        retrying = key == failedKey
    }

    /// Der laufende Abruf wurde abgebrochen, ohne Ergebnis: die Sperre ist vorbei, der nächste Versuch sofort fällig.
    public mutating func cancelled(now: Date = Date()) {
        guard retrying else { return }
        retrying = false
        blockedUntil = min(blockedUntil, now)
    }

    public mutating func failed(_ key: String, error: String, now: Date = Date(), pause: TimeInterval = defaultPause) {
        failedKey = key
        blockedUntil = now.addingTimeInterval(pause)
        lastError = error
        retrying = false
    }

    public mutating func succeeded(_ key: String) {
        retrying = false
        if failedKey == key { failedKey = nil; lastError = nil; blockedUntil = .distantPast }
    }
}
