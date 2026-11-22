import SwiftUI
import MediaPlayer
import AetherFEL
import PlayerCore

/// Welle G-b: Now Playing (Kontrollzentrum, iPhone-Fernbedienung, Apple-TV-Übersicht) und Systembefehle.
///
/// Die Engine besitzt Karte und Befehlsziele (Opt-ins `ownsVideoNowPlayingSession`/`…Commands` für den nativen Weg,
/// `ownsSoftwareNowPlaying` für den Software-/FEL-Weg). Laut Engine-Doku darf die App auf dem nativen Videoweg unter
/// tvOS 26 nicht selbst in `MPNowPlayingInfoCenter` schreiben; die Karte kommt deshalb über `setNowPlayingInfo`
/// (Titel, Folge, Bild), Stelle, Rate und Dauer liefert die Engine bei Play, Pause, Sprung und Quellwechsel selbst.
///
/// Befehle laufen über `nowPlayingCommandInterceptor` und kehren immer mit „erledigt“ zurück: die Engine führt
/// keinen eigenen Sprung/Toggle aus. Was passiert, entscheidet PlayerCore `RemoteTransport`; ausgeführt wird über
/// die Funktionen der Steuerleiste (Play/Pause mit 350-ms-Doppelfilter, ±-Sammlung mit 450 ms) – kein zweiter Weg.
/// Die Siri-Remote selbst bleibt bei den SwiftUI-Befehlen von PlayerControls (Tasten, Halten, Wischen).
///
/// Ende: `detach` (aus `leave`) schluckt ab dann alle Befehle und leert die Karte; `stop()` der Engine meldet die
/// Befehlsziele ab und räumt die Karte vom Center.
@MainActor
enum NowPlayingBridge {
    struct Handlers {
        var context: @MainActor () -> RemoteTransportContext
        var toggle: @MainActor () -> Void
        var seekBy: @MainActor (Double) -> Void
    }

    private static var artworkTask: Task<Void, Never>?
    /// Größte Bildkante für die Karte (Pixel).
    private static let artworkPixels = 800

    /// Vor dem ersten `load()`: Opt-ins, Sprungweite, Karte. Bis die Steuerleiste steht, werden Befehle geschluckt.
    static func stage(_ backend: AetherBackend, request: PlayRequest, skipSeconds: Int) {
        let e = backend.engine
        e.ownsVideoNowPlayingSession = true
        e.ownsVideoNowPlayingCommands = true
        e.ownsSoftwareNowPlaying = true
        e.remoteSkipInterval = RemoteTransport.skipInterval(skipSeconds)
        e.nowPlayingCommandInterceptor = { command in
            RemoteLog.info("nowplaying", "Befehl \(transport(command).logName) vor dem Start ignoriert")
            return true
        }
        let heading = PlayerHeading(request)
        let card = NowPlayingCard.make(title: heading.title, episodeLine: heading.episodeLine,
                                       year: request.item.releaseInfo, poster: request.item.poster,
                                       background: request.item.background)
        e.setNowPlayingInfo(info(card, artwork: nil))
        RemoteLog.info("nowplaying", "Karte \(card.logText) · Sprungweite \(Int(e.remoteSkipInterval)) s")
        artworkTask?.cancel()
        artworkTask = nil
        guard let url = card.artworkURL else { return }
        artworkTask = Task { @MainActor [weak e] in
            let image = await ImagePipeline.shared.image(url, maxPixels: artworkPixels)
            guard !Task.isCancelled, let e else { return }
            guard let image else { RemoteLog.info("nowplaying", "Kartenbild nicht geladen"); return }
            e.setNowPlayingInfo(info(card, artwork: image))
        }
    }

    /// Steuerleiste steht (PlayerControls.onAppear, auch nach dem Spur-Panel): Befehle auf ihre Funktionen.
    static func route<E: PlaybackEngine>(_ engine: E, handlers: Handlers) {
        guard let e = (engine as? AetherBackend)?.engine else { return }
        e.nowPlayingCommandInterceptor = { command in
            let c = transport(command)
            let action = RemoteTransport.action(for: c, context: handlers.context())
            RemoteLog.info("nowplaying", "Befehl \(c.logName) → \(action.logText)")
            switch action {
            case .toggle: handlers.toggle()
            case .seek(let delta): handlers.seekBy(delta)
            case .ignore: break
            }
            return true
        }
    }

    /// Jeder Ausgang (`leave`): ab jetzt nichts mehr ausführen, Karte leeren. `stop()` meldet die Ziele ab.
    static func detach<E: PlaybackEngine>(_ engine: E) {
        artworkTask?.cancel()
        artworkTask = nil
        guard let e = (engine as? AetherBackend)?.engine else { return }
        e.nowPlayingCommandInterceptor = { command in
            RemoteLog.info("nowplaying", "Befehl \(transport(command).logName) nach dem Verlassen ignoriert")
            return true
        }
        e.setNowPlayingInfo([:])
        RemoteLog.info("nowplaying", "Abgemeldet (Karte geleert, Befehle gesperrt bis zum Stopp)")
    }

    private static func transport(_ c: NowPlayingRemoteCommand) -> RemoteTransportCommand {
        switch c {
        case .play: .play
        case .pause: .pause
        case .togglePlayPause: .togglePlayPause
        case .skip(let s): .skip(seconds: s)
        case .changePosition(let t): .changePosition(to: t)
        case .nextTrack: .nextTrack
        case .previousTrack: .previousTrack
        }
    }

    /// Nur Identität; Stelle, Rate und Dauer setzt die Engine. Bild vorab dekodiert, Handler ohne Zustand.
    private static func info(_ card: NowPlayingCard, artwork: UIImage?) -> [String: Any] {
        var i: [String: Any] = [MPMediaItemPropertyTitle: card.title,
                                MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue]
        if let s = card.subtitle { i[MPMediaItemPropertyArtist] = s }
        if let artwork {
            i[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { @Sendable _ in artwork }
        }
        return i
    }
}
