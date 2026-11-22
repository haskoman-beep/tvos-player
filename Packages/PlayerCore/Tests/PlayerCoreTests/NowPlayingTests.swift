import Foundation
import Testing
@testable import PlayerCore

// MARK: Karte

@Test func nowPlayingCardSeriesAndFilm() {
    let ep = NowPlayingCard.make(title: "Severance", episodeLine: "S2 E3 · Who Is Alive?", year: "2022",
                                 poster: "https://img.example/p.jpg", background: "https://img.example/b.jpg")
    #expect(ep.title == "Severance")
    #expect(ep.subtitle == "S2 E3 · Who Is Alive?")   // Folge vor Jahr
    #expect(ep.artworkURL?.absoluteString == "https://img.example/p.jpg")

    let film = NowPlayingCard.make(title: "  Dune  ", episodeLine: nil, year: "2021", poster: nil,
                                   background: "https://img.example/b.jpg")
    #expect(film.title == "Dune")
    #expect(film.subtitle == "2021")
    #expect(film.artworkURL?.absoluteString == "https://img.example/b.jpg")   // ohne Poster: Hintergrund

    let bare = NowPlayingCard.make(title: " ", episodeLine: " ", year: nil, poster: nil, background: nil)
    #expect(bare.title == "Player")
    #expect(bare.subtitle == nil)
    #expect(bare.artworkURL == nil)
}

@Test func nowPlayingArtworkOnlyWebAddresses() {
    #expect(NowPlayingCard.artworkURL(poster: "file:///etc/x.png", background: "http://img.example/b.jpg")?.absoluteString
            == "http://img.example/b.jpg")
    #expect(NowPlayingCard.artworkURL(poster: "kein link", background: "") == nil)
    #expect(NowPlayingCard.artworkURL(poster: "data:image/png;base64,AAAA", background: nil) == nil)
}

@Test func nowPlayingLogTextHasNoAddress() {
    let c = NowPlayingCard(title: "Dune", subtitle: "2021", artworkURL: URL(string: "https://img.example/geheim.jpg"))
    #expect(c.logText == "„Dune“ · 2021 · mit Bild")
    #expect(!c.logText.contains("img.example"))
}

// MARK: Systembefehle

private let playing = RemoteTransportContext(isPlaying: true, position: 600)
private let paused = RemoteTransportContext(isPlaying: false, position: 600)

@Test func remotePlayPauseGoThroughToggleOnlyWhenTheyChangeSomething() {
    #expect(RemoteTransport.action(for: .play, context: paused) == .toggle)
    #expect(RemoteTransport.action(for: .play, context: playing) == .ignore("spielt schon"))
    #expect(RemoteTransport.action(for: .pause, context: playing) == .toggle)
    #expect(RemoteTransport.action(for: .pause, context: paused) == .ignore("schon pausiert"))
    #expect(RemoteTransport.action(for: .togglePlayPause, context: playing) == .toggle)
    #expect(RemoteTransport.action(for: .togglePlayPause, context: paused) == .toggle)
}

@Test func remoteSkipAndPositionBecomeRelativeSeeks() {
    #expect(RemoteTransport.action(for: .skip(seconds: 30), context: playing) == .seek(by: 30))
    #expect(RemoteTransport.action(for: .skip(seconds: -10), context: paused) == .seek(by: -10))
    #expect(RemoteTransport.action(for: .skip(seconds: 0), context: playing) == .ignore("ungültige Sprungweite"))
    #expect(RemoteTransport.action(for: .skip(seconds: .nan), context: playing) == .ignore("ungültige Sprungweite"))
    // Position absolut → Sprung relativ zum Ausgangspunkt (gesammeltes Ziel oder aktuelle Stelle).
    #expect(RemoteTransport.action(for: .changePosition(to: 1200), context: playing) == .seek(by: 600))
    #expect(RemoteTransport.action(for: .changePosition(to: 0), context: playing) == .seek(by: -600))
    #expect(RemoteTransport.action(for: .changePosition(to: 600.2), context: playing) == .ignore("gleiche Stelle"))
    #expect(RemoteTransport.action(for: .changePosition(to: -5), context: playing) == .ignore("ungültige Position"))
    #expect(RemoteTransport.action(for: .changePosition(to: .infinity), context: playing) == .ignore("ungültige Position"))
}

@Test func remoteCommandsBlockedWhileLeavingOrScrubbing() {
    let blocked = RemoteTransportContext(isPlaying: true, position: 10, inputBlocked: true)
    for c: RemoteTransportCommand in [.play, .pause, .togglePlayPause, .skip(seconds: 10), .changePosition(to: 50)] {
        #expect(RemoteTransport.action(for: c, context: blocked) == .ignore("gesperrt"))
    }
}

@Test func remoteUpNextPauseIgnoredToggleStartsNext() {
    let upNext = RemoteTransportContext(isPlaying: true, position: 2500, upNextShowing: true)
    #expect(RemoteTransport.action(for: .pause, context: upNext) == .ignore("Up-next läuft"))
    #expect(RemoteTransport.action(for: .togglePlayPause, context: upNext) == .toggle)
    #expect(RemoteTransport.action(for: .nextTrack, context: playing) == .ignore("keine Titelliste"))
    #expect(RemoteTransport.action(for: .previousTrack, context: playing) == .ignore("keine Titelliste"))
}

@Test func remotePlayPauseRightAfterRemotePressIgnored() {
    // Druck hat gerade das Spulen bestätigt (oder getoggelt): Systembefehl derselbe Druck → nichts tun.
    let justPressed = RemoteTransportContext(isPlaying: true, position: 600, sinceLastPress: 0.1)
    for c: RemoteTransportCommand in [.play, .pause, .togglePlayPause] {
        #expect(RemoteTransport.action(for: c, context: justPressed) == .ignore("doppelt zum Tastendruck"))
    }
    #expect(RemoteTransport.action(for: .skip(seconds: 10), context: justPressed) == .seek(by: 10))   // Sprünge zählen
    let later = RemoteTransportContext(isPlaying: true, position: 600, sinceLastPress: 0.4)
    #expect(RemoteTransport.action(for: .togglePlayPause, context: later) == .toggle)
}

@Test func remotePlayPauseIgnoredWhileLoadingOrSeeking() {
    // Springen aus der Pause oder aus dem Spielen: Zustand unklar → Play/Pause/Toggle nicht ausführen.
    for playing in [true, false] {
        let busy = RemoteTransportContext(isPlaying: playing, isBusy: true, position: 600)
        for c: RemoteTransportCommand in [.play, .pause, .togglePlayPause] {
            #expect(RemoteTransport.action(for: c, context: busy) == .ignore("lädt/springt"))
        }
        #expect(RemoteTransport.action(for: .skip(seconds: -10), context: busy) == .seek(by: -10))   // Sprünge zählen
    }
}

@Test func remoteSkipIntervalChoicesAndLogs() {
    #expect(RemoteTransport.skipInterval(10) == 10)
    #expect(RemoteTransport.skipInterval(30) == 30)
    #expect(RemoteTransport.skipInterval(15) == 10)   // unbekannt → Standard
    #expect(RemoteTransport.choiceLabel(30) == "30 Sekunden")
    #expect(RemoteTransportCommand.skip(seconds: -30).logName == "−30 s")
    #expect(RemoteTransportCommand.skip(seconds: 10).logName == "+10 s")
    #expect(RemoteTransportAction.seek(by: -9.6).logText == "Sprung -10 s")
}

@Test func comfortSettingsRemoteSkipDefaultsForOldProfiles() throws {
    let old = try JSONDecoder().decode(PlayerComfortSettings.self, from: Data(#"{"rememberTracks":false}"#.utf8))
    #expect(old.remoteSkipSeconds == RemoteTransport.defaultSkipSeconds)
    #expect(old.rememberTracks == false)
    var s = PlayerComfortSettings()
    s.remoteSkipSeconds = 30
    let back = try JSONDecoder().decode(PlayerComfortSettings.self, from: JSONEncoder().encode(s))
    #expect(back.remoteSkipSeconds == 30)
}
