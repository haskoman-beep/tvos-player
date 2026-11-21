import Foundation

/// Geordneter Ausstieg aus dem Player, wenn der Fernseher beim Schließen den Bildmodus zurückschalten muss
/// (z. B. Dolby Vision → SDR-Menü). Ablauf: schwarze Abdeckung → `coverDelay` → Wiedergabe stoppen (die Engine
/// gibt dabei die Anzeige-Kriterien frei) → auf den Moduswechsel warten → `settle` → schließen.
/// Testbar ohne UIKit: der Aufrufer meldet in kurzen Abständen, ob tvOS gerade umschaltet.
public struct ModeSwitchExit: Sendable {
    /// Abdeckung steht, bevor die Bildfläche abgebaut wird.
    public static let coverDelay: Double = 0.25
    /// So lange auf den Beginn eines Wechsels warten; kommt keiner, sofort schließen.
    public static let startGrace: Double = 0.5
    /// Nach dem Ende des Wechsels noch so lange Ruhe.
    public static let settle: Double = 0.3
    /// Höchstens so lange warten (tvOS meldet ein Ende manchmal nie).
    public static let maxWait: Double = 6
    /// Abfrage-Abstand.
    public static let pollInterval: Double = 0.1
    /// Schwarze Abdeckung nach der Rückkehr aus dem Hintergrund (keine Bildreste).
    public static let backgroundReturnCover: Double = 0.6

    public enum Step: Equatable, Sendable {
        case wait
        /// Schließen; `reason` fürs Log.
        case close(reason: String)
    }

    private let stoppedAt: Double
    private var sawSwitch = false
    private var switchEndedAt: Double?

    /// `stoppedAt`: Zeitpunkt, zu dem die Wiedergabe gestoppt wurde (monotone Sekunden).
    public init(stoppedAt: Double) { self.stoppedAt = stoppedAt }

    /// Neuer Stand: `switching` = tvOS meldet einen laufenden Moduswechsel.
    public mutating func observe(switching: Bool, now: Double) -> Step {
        let waited = now - stoppedAt
        if waited >= Self.maxWait { return .close(reason: "Zeitgrenze \(Int(Self.maxWait)) s") }
        if switching {
            sawSwitch = true; switchEndedAt = nil
            return .wait
        }
        if sawSwitch {
            let ended = switchEndedAt ?? now
            switchEndedAt = ended
            return now - ended >= Self.settle ? .close(reason: "Moduswechsel fertig") : .wait
        }
        return waited >= Self.startGrace ? .close(reason: "kein Moduswechsel") : .wait
    }
}
