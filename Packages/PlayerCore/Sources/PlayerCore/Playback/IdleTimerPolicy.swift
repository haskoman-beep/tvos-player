import Foundation

/// Bildschirmschoner im Player (Welle D-a): gesperrt beim Spielen, Laden und Nachpuffern; in der Pause
/// höchstens `pauseLimitMinutes` lang (0 = in der Pause gar nicht sperren). Beim Verlassen immer frei.
public struct IdleTimerPolicy: Sendable, Equatable {
    /// Wählbare Pausen-Grenzen in Minuten (0 = nicht sperren).
    public static let pauseChoices = [0, 10, 30, 60, 120]
    public static let defaultPauseMinutes = 30

    public var pauseLimitMinutes: Int
    /// Beginn der laufenden Pause (nil = spielt oder lädt).
    public private(set) var pausedSince: Date?

    public init(pauseLimitMinutes: Int = IdleTimerPolicy.defaultPauseMinutes) {
        self.pauseLimitMinutes = max(0, pauseLimitMinutes)
    }

    /// Ein Takt: liefert, ob der Bildschirmschoner gerade gesperrt sein soll.
    /// `busy` = spielt, lädt, springt oder puffert nach.
    public mutating func update(busy: Bool, now: Date = Date()) -> Bool {
        if busy { pausedSince = nil; return true }
        let since = pausedSince ?? now
        pausedSince = since
        guard pauseLimitMinutes > 0 else { return false }
        return now.timeIntervalSince(since) < Double(pauseLimitMinutes) * 60
    }

    /// Player verlassen: Pause vergessen; der Aufrufer gibt den Bildschirmschoner frei.
    public mutating func reset() { pausedSince = nil }

    public static func choiceLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: "Nicht sperren"
        case 60: "1 Stunde"
        case 120: "2 Stunden"
        default: "\(minutes) Minuten"
        }
    }
}
