import Foundation

/// Player-Einstellungen aus Welle D-a (Bild und Ton). Alle Felder mit Standardwert, alte Profile laden.
public struct PlayerComfortSettings: Codable, Sendable, Equatable {
    /// „Spur-Wahl je Serie merken“: Tonsprache, Untertitel und Versatz je Serie bzw. Film (Standard an).
    public var rememberTracks: Bool
    /// Bildschirmschoner in der Pause so viele Minuten sperren (0 = in der Pause nicht sperren, Standard 30).
    public var screensaverPauseMinutes: Int
    /// Welle G-b: Sprungweite der Systembefehle (iPhone-Fernbedienung, Kontrollzentrum), 10 oder 30 s (Standard 10).
    public var remoteSkipSeconds: Int
    /// Welle F-h3: „Ton & Untertitel öffnen“ (Standard Leiste oben).
    public var trackPanelStyle: TrackPanelStyle
    /// Wave F-n: show the „Sofort abspielen“ card (best source, wave G-a) on the movie detail page. Default off:
    /// „Abspielen“ is the main button and no best choice is built.
    public var instantPlay: Bool

    public init(rememberTracks: Bool = true, screensaverPauseMinutes: Int = IdleTimerPolicy.defaultPauseMinutes,
                remoteSkipSeconds: Int = RemoteTransport.defaultSkipSeconds, trackPanelStyle: TrackPanelStyle = .topBar,
                instantPlay: Bool = false) {
        self.rememberTracks = rememberTracks
        self.screensaverPauseMinutes = screensaverPauseMinutes
        self.remoteSkipSeconds = remoteSkipSeconds
        self.trackPanelStyle = trackPanelStyle
        self.instantPlay = instantPlay
    }

    enum CodingKeys: String, CodingKey { case rememberTracks, screensaverPauseMinutes, remoteSkipSeconds, trackPanelStyle, instantPlay }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PlayerComfortSettings()
        rememberTracks = (try? c.decodeIfPresent(Bool.self, forKey: .rememberTracks)) ?? nil ?? d.rememberTracks
        screensaverPauseMinutes = (try? c.decodeIfPresent(Int.self, forKey: .screensaverPauseMinutes)) ?? nil ?? d.screensaverPauseMinutes
        remoteSkipSeconds = (try? c.decodeIfPresent(Int.self, forKey: .remoteSkipSeconds)) ?? nil ?? d.remoteSkipSeconds
        // Unbekannter Wert (neuere App) fällt auf den Standard zurück.
        trackPanelStyle = (try? c.decodeIfPresent(TrackPanelStyle.self, forKey: .trackPanelStyle)) ?? nil ?? d.trackPanelStyle
        instantPlay = (try? c.decodeIfPresent(Bool.self, forKey: .instantPlay)) ?? nil ?? d.instantPlay
    }
}
