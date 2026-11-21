import Foundation

/// Player-Einstellungen aus Welle D-a (Bild und Ton). Alle Felder mit Standardwert, alte Profile laden.
public struct PlayerComfortSettings: Codable, Sendable, Equatable {
    /// „Spur-Wahl je Serie merken“: Tonsprache, Untertitel und Versatz je Serie bzw. Film (Standard an).
    public var rememberTracks: Bool
    /// Bildschirmschoner in der Pause so viele Minuten sperren (0 = in der Pause nicht sperren, Standard 30).
    public var screensaverPauseMinutes: Int

    public init(rememberTracks: Bool = true, screensaverPauseMinutes: Int = IdleTimerPolicy.defaultPauseMinutes) {
        self.rememberTracks = rememberTracks
        self.screensaverPauseMinutes = screensaverPauseMinutes
    }

    enum CodingKeys: String, CodingKey { case rememberTracks, screensaverPauseMinutes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PlayerComfortSettings()
        rememberTracks = (try? c.decodeIfPresent(Bool.self, forKey: .rememberTracks)) ?? nil ?? d.rememberTracks
        screensaverPauseMinutes = (try? c.decodeIfPresent(Int.self, forKey: .screensaverPauseMinutes)) ?? nil ?? d.screensaverPauseMinutes
    }
}
