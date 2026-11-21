import Foundation

/// „Noch da?“: zählt automatisch gestartete Folgen ohne Tastendruck. Jeder Tastendruck setzt auf 0;
/// ab `limit` automatischen Starts wird vor der nächsten Folge gefragt (limit 0 = nie fragen).
public struct StillWatchingCounter: Equatable, Sendable {
    public private(set) var autoStarts = 0
    /// Wahlmöglichkeiten der Einstellung (0 = aus).
    public static let choices = [2, 3, 5, 0]
    public static let defaultLimit = 3
    /// Wartezeit auf eine Antwort; danach startet nichts.
    public static let answerTimeout: Double = 60

    public init() {}

    /// Vor dem automatischen Start der nächsten Folge: erst fragen?
    public func promptDue(limit: Int) -> Bool { limit > 0 && autoStarts >= limit }

    /// Eine Folge wurde automatisch gestartet (Up-next/Auto-Weiter ohne Eingabe).
    public mutating func autoStarted() { autoStarts += 1 }

    /// Tastendruck (Fernbedienung, Quellenliste, „Weiterschauen“). true = Zähler hat sich geändert.
    @discardableResult public mutating func userInput() -> Bool {
        guard autoStarts != 0 else { return false }
        autoStarts = 0
        return true
    }
}
