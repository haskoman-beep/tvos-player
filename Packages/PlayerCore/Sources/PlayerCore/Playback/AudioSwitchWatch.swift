import Foundation

/// Welle F-h2 R1: verfolgt ein Ton-Neuladen aus dem Spur-Panel, bis die Engine die neue Spur spielt.
/// Die Engine meldet den Wechsel nicht öffentlich: fertig ist er, wenn die Zielspur aktiv ist und nichts mehr lädt.
/// Lädt nach `ignoreAfter` nichts und ist die Spur nicht aktiv, hat die Engine die Wahl verworfen;
/// `giveUpAfter` ist die harte Grenze, damit die Sperre nie hängen bleibt.
public struct AudioSwitchWatch: Equatable, Sendable {
    public static let ignoreAfter: TimeInterval = 3
    public static let giveUpAfter: TimeInterval = 30

    public enum Outcome: Equatable, Sendable {
        /// Zielspur aktiv, Laden vorbei.
        case done
        /// Engine-Fehler während des Wechsels.
        case failed
        /// Kein Laden begonnen, Spur nicht aktiv: Wahl verworfen.
        case ignored
        /// Harte Grenze erreicht.
        case timedOut

        public var logText: String {
            switch self {
            case .done: "fertig"
            case .failed: "Engine-Fehler"
            case .ignored: "von der Engine verworfen"
            case .timedOut: "Zeitgrenze"
            }
        }
    }

    public private(set) var target: Int?
    private var started: Date?
    private var sawLoading = false

    public init() {}

    public var isActive: Bool { target != nil }

    /// Neuer Wechsel (auch eine zweite Wahl während des ersten: die Engine ersetzt die wartende Wahl).
    public mutating func begin(_ id: Int, now: Date) {
        target = id; started = now; sawLoading = false
    }

    /// Stand prüfen. Rückgabe: das Ende (einmal), sonst nil (läuft weiter oder kein Wechsel).
    public mutating func update(activeID: Int?, isLoading: Bool, failed: Bool, now: Date) -> Outcome? {
        guard let target, let started else { return nil }
        if isLoading { sawLoading = true }
        let elapsed = now.timeIntervalSince(started)
        let outcome: Outcome?
        if failed { outcome = .failed }
        else if activeID == target && !isLoading { outcome = .done }
        else if !sawLoading && activeID != target && elapsed >= Self.ignoreAfter { outcome = .ignored }
        else if elapsed >= Self.giveUpAfter { outcome = .timedOut }
        else { outcome = nil }
        if outcome != nil { self.target = nil; self.started = nil; sawLoading = false }
        return outcome
    }
}
