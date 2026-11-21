import Foundation

/// Bildmodus-Einstellungen des Profils für die Engine (Welle C-c, #13). Standard = bisheriges Verhalten,
/// außer `keepModeBetweenEpisodes` (spart beim Dolby-Vision-Fernseher das mehrere Sekunden lange Umschalten
/// zwischen zwei Folgen).
public struct DisplayModeSettings: Codable, Sendable, Equatable {
    /// Fernseher zeigt Dolby Vision: die App behauptet es gegenüber der Engine (statt nur die Erkennung
    /// von tvOS). Standard aus, tvOS meldet einen Dolby-Vision-Fernseher selbst.
    public var panelPresentsDolbyVision: Bool
    /// Dolby Vision mit Erweiterungsschicht (FEL) einrechnen. Standard an (Engine-Standard); wirkt erst mit
    /// der FEL-Erweiterung der Engine, ohne sie bleibt der Schalter ohne Wirkung.
    public var foldsDolbyVisionFEL: Bool
    /// Nächste Folge: HDMI-Modus nicht zurücksetzen. Hat die Folge dasselbe Format, schaltet der Fernseher
    /// nicht um; sonst schaltet er wie sonst auch.
    public var keepModeBetweenEpisodes: Bool

    /// Startet nach dem Halten keine Wiedergabe, wird der Modus nach so vielen Sekunden doch zurückgesetzt.
    public static let keepTimeout: Double = 20

    public init(panelPresentsDolbyVision: Bool = false, foldsDolbyVisionFEL: Bool = true,
                keepModeBetweenEpisodes: Bool = true) {
        self.panelPresentsDolbyVision = panelPresentsDolbyVision
        self.foldsDolbyVisionFEL = foldsDolbyVisionFEL
        self.keepModeBetweenEpisodes = keepModeBetweenEpisodes
    }

    enum CodingKeys: String, CodingKey { case panelPresentsDolbyVision, foldsDolbyVisionFEL, keepModeBetweenEpisodes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DisplayModeSettings()
        panelPresentsDolbyVision = try c.decodeIfPresent(Bool.self, forKey: .panelPresentsDolbyVision) ?? d.panelPresentsDolbyVision
        foldsDolbyVisionFEL = try c.decodeIfPresent(Bool.self, forKey: .foldsDolbyVisionFEL) ?? d.foldsDolbyVisionFEL
        keepModeBetweenEpisodes = try c.decodeIfPresent(Bool.self, forKey: .keepModeBetweenEpisodes) ?? d.keepModeBetweenEpisodes
    }

    /// HDMI-Modus beim Stopp halten? Nur wenn die Einstellung an ist, die Wiedergabe gleich weitergeht
    /// (`nextStarts`: nicht abgebrochen) und es überhaupt eine automatisch startende nächste Folge gibt
    /// (`hasNext`). Film, letzte Folge, „Noch da?“ und Autoplay aus → normal zurücksetzen.
    public func keepsMode(nextStarts: Bool, hasNext: Bool) -> Bool {
        keepModeBetweenEpisodes && nextStarts && hasNext
    }

    /// Kurztext fürs Log (nur Abweichungen vom Engine-Standard).
    public var logText: String {
        var parts: [String] = []
        if panelPresentsDolbyVision { parts.append("DV behauptet") }
        if !foldsDolbyVisionFEL { parts.append("FEL aus") }
        return parts.isEmpty ? "Standard" : parts.joined(separator: ", ")
    }
}
