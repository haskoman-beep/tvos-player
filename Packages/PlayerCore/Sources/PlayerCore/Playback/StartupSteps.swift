import Foundation

/// Arbeitsschritt beim Start einer Wiedergabe. Spiegelt `StartupStage` der AetherEngine (7.71.2, #361) mit
/// gleichen Rohwerten, damit PlayerCore die Engine nicht kennen muss.
public enum StartupStep: String, Sendable, CaseIterable {
    case connecting, openingContainer, analyzingStreams, preparingDisplay, selectingRoute,
         buildingSession, preparingPlayback, awaitingFirstFrame, presenting
}

/// Startstand, wie ihn das Backend meldet (nil = kein Start läuft).
public struct StartupStatus: Sendable, Equatable {
    /// Was gerade läuft; nil = unbekannter Engine-Wert.
    public var step: StartupStep?
    /// Erledigte Schritte / alle Schritte, 0…1 (läuft nie auf Zeit, nur echte Schritte).
    public var fraction: Double
    /// Der Fernseher stellt den Bildmodus um (Bild kann schon da sein, Start wartet).
    public var awaitingDisplaySwitch: Bool

    public init(step: StartupStep?, fraction: Double, awaitingDisplaySwitch: Bool = false) {
        self.step = step; self.fraction = fraction; self.awaitingDisplaySwitch = awaitingDisplaySwitch
    }
}

/// Eine sichtbare Ladezeile: Text plus Anteil in Prozent (nil = ohne Zahl).
public struct StartupStepLine: Sendable, Equatable {
    public var text: String
    public var percent: Int?
}

/// Texte für die Lade-Schritte im Player.
public enum StartupSteps {
    /// Zeile für den aktuellen Stand; nil = nichts anzeigen (kein Start läuft oder Bild ist da und nichts wartet).
    /// `dynamicRange`: Quellformat ("dolbyVision", "hdr10", "hdr10Plus", "hlg", "sdr"), nil = unbekannt.
    public static func line(_ status: StartupStatus?, dynamicRange: String?) -> StartupStepLine? {
        guard let status else { return nil }
        let range = rangeName(dynamicRange)
        if status.awaitingDisplaySwitch {
            return StartupStepLine(text: range.map { "Fernseher schaltet auf \($0)" } ?? "Bildmodus wird angepasst", percent: nil)
        }
        guard let step = status.step, step != .presenting else { return nil }
        let text: String
        switch step {
        case .connecting: text = "Verbinde mit der Quelle"
        case .openingContainer: text = "Datei wird geöffnet"
        case .analyzingStreams: text = "Spuren werden gelesen"
        case .preparingDisplay: text = range.map { "\($0) wird vorbereitet" } ?? "Bildmodus wird vorbereitet"
        case .selectingRoute: text = "Wiedergabeweg wird gewählt"
        case .buildingSession: text = "Wiedergabe wird aufgebaut"
        case .preparingPlayback, .awaitingFirstFrame: text = "Puffern"
        case .presenting: return nil
        }
        let f = min(max(status.fraction, 0), 1)
        return StartupStepLine(text: text, percent: f > 0 ? Int((f * 100).rounded()) : nil)
    }

    /// Anzeigename für HDR-Formate; SDR/unbekannt = nil.
    static func rangeName(_ s: String?) -> String? {
        switch s?.lowercased() {
        case "dolbyvision": return "Dolby Vision"
        case "hdr10plus": return "HDR10+"
        case "hdr10": return "HDR10"
        case "hlg": return "HLG"
        default: return nil
        }
    }
}
