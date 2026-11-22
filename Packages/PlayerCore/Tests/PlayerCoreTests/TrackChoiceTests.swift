import Foundation
import Testing
@testable import PlayerCore

private func a(_ id: Int, _ lang: String?, ch: Int? = nil, codec: String? = nil, name: String? = nil,
               atmos: Bool = false, layout: String? = nil, profile: String? = nil) -> AudioTrackInfo {
    AudioTrackInfo(id: id, language: lang, name: name, channels: ch, codec: codec,
                   profile: profile, isAtmos: atmos, channelLayout: layout)
}

private func s(_ id: Int, _ lang: String?, forced: Bool = false, sdh: Bool = false, ext: Bool = false,
               name: String? = nil) -> AudioTrackInfo {
    AudioTrackInfo(id: id, language: lang, name: name, codec: "subrip",
                   isForced: forced, isHearingImpaired: sdh, isExternal: ext)
}

// MARK: Öffnen

private func entry(leaving: Bool = false, scrubbing: Bool = false, upNext: Bool = false, failure: Bool = false,
                   open: Bool = false, skip: Bool = false, lock: TrackLock? = nil) -> TrackPanelEntry.Step {
    TrackPanelEntry.decide(leaving: leaving, scrubbing: scrubbing, upNextShowing: upNext, failureShowing: failure,
                           alreadyOpen: open, skipPromptShowing: skip, lock: lock)
}

@Test func entryOpensOnlyWhenFree() {
    #expect(entry() == .open)
    #expect(entry(leaving: true) == .ignore(.leaving))
    #expect(entry(scrubbing: true) == .ignore(.scrubbing))
    #expect(entry(failure: true) == .ignore(.failure))
    #expect(entry(open: true) == .ignore(.alreadyOpen))
    #expect(entry(upNext: true) == .cancelUpNext)
    // Ausgang schlägt alles
    #expect(entry(leaving: true, upNext: true, lock: .loading) == .ignore(.leaving))
}

@Test func entrySkipPromptKeepsFocus() {
    #expect(entry(skip: true) == .ignore(.skipPrompt))
    #expect(TrackPanelEntry.IgnoreReason.skipPrompt.logText == "Überspringen-Knopf hat den Fokus")
    // Up-next zuerst abbrechen, auch wenn der Knopf noch steht
    #expect(entry(upNext: true, skip: true) == .cancelUpNext)
}

@Test func entryBlockedWhileReloading() {
    #expect(entry(lock: .recovering) == .ignore(.busy(.recovering)))
    #expect(entry(lock: .loading) == .ignore(.busy(.loading)))
    #expect(TrackPanelEntry.IgnoreReason.busy(.restoring).logText == "Neuaufbau nach Hintergrund")
}

@Test func trackLockOrderAndText() {
    let none = TrackLock.current(restoring: false, recovering: false, loadInFlight: false, startPending: false,
                                 waitingForNetwork: false, engineError: false)
    #expect(none == nil)
    let restoring = TrackLock.current(restoring: true, recovering: true, loadInFlight: true, startPending: true,
                                      waitingForNetwork: true, engineError: true)
    #expect(restoring == .restoring)
    let recovering = TrackLock.current(restoring: false, recovering: true, loadInFlight: false, startPending: true,
                                       waitingForNetwork: false, engineError: true)
    #expect(recovering == .recovering)
    let loading = TrackLock.current(restoring: false, recovering: false, loadInFlight: true, startPending: false,
                                    waitingForNetwork: false, engineError: false)
    #expect(loading == .loading)
    let pending = TrackLock.current(restoring: false, recovering: false, loadInFlight: false, startPending: true,
                                    waitingForNetwork: false, engineError: false)
    #expect(pending == .startPending)
    let net = TrackLock.current(restoring: false, recovering: false, loadInFlight: false, startPending: false,
                                waitingForNetwork: true, engineError: false)
    #expect(net == .waitingForNetwork)
    let err = TrackLock.current(restoring: false, recovering: false, loadInFlight: false, startPending: false,
                                waitingForNetwork: false, engineError: true)
    #expect(err == .engineError)
    #expect(TrackLock.loading.text == "Gerade nicht möglich – Quelle wird geladen")
    #expect(TrackLock.waitingForNetwork.text == "Gerade nicht möglich – warte auf das Netz")
}

@Test func swipeDownRecognition() {
    #expect(TrackPanelEntry.isSwipeDown(translationX: 10, translationY: 300, velocityY: 200))
    // kurz, aber schnell
    #expect(TrackPanelEntry.isSwipeDown(translationX: 0, translationY: 80, velocityY: 1200))
    // kurz und langsam: Finger zuckt nur
    #expect(!TrackPanelEntry.isSwipeDown(translationX: 0, translationY: 80, velocityY: 100))
    // nach oben
    #expect(!TrackPanelEntry.isSwipeDown(translationX: 0, translationY: -300, velocityY: -1500))
    // waagerecht/schräg: Spulen, kein Panel
    #expect(!TrackPanelEntry.isSwipeDown(translationX: 400, translationY: 300, velocityY: 900))
    #expect(!TrackPanelEntry.isSwipeDown(translationX: .nan, translationY: 300, velocityY: 900))
}

@Test func swipeDownNeverAlsoScrubs() {
    // Diese Wischer gelten als Wisch nach unten, und keiner davon spult.
    for (x, y) in [(0.0, 300.0), (100, 160), (199, 300), (-150, 240)] {
        #expect(TrackPanelEntry.isSwipeDown(translationX: x, translationY: y, velocityY: 0))
        #expect(!ScrubPlanner.panIsHorizontal(translationX: x, translationY: y))
    }
    // Gitter über viele Winkel und Längen: nie beides zugleich.
    for deg in stride(from: 0.0, to: 360.0, by: 5.0) {
        for len in [50.0, 100, 200, 400] {
            let x = cos(deg * .pi / 180) * len, y = sin(deg * .pi / 180) * len
            let down = TrackPanelEntry.isSwipeDown(translationX: x, translationY: y, velocityY: 2000)
            let horizontal = ScrubPlanner.panIsHorizontal(translationX: x, translationY: y)
            #expect(!(down && horizontal))
        }
    }
}

// MARK: Beschriftung

@Test func audioLabelsGerman() {
    #expect(TrackChoice.audioLabel(a(0, "ger", ch: 6, codec: "eac3")) == "Deutsch 5.1 (E-AC-3)")
    #expect(TrackChoice.audioLabel(a(1, "eng", ch: 2, codec: "aac")) == "Englisch Stereo (AAC)")
    #expect(TrackChoice.audioLabel(a(2, "eng", ch: 8, codec: "truehd", atmos: true)) == "Englisch 7.1 (TrueHD Atmos)")
    #expect(TrackChoice.audioLabel(a(3, "fre", ch: 6, codec: "dts", profile: "DTS-HD MA")) == "Französisch 5.1 (DTS-HD MA)")
    #expect(TrackChoice.audioLabel(a(4, "eng")) == "Englisch")
    #expect(TrackChoice.audioLabel(a(5, nil, ch: 6, codec: "ac3")) == "Spur 6 5.1 (AC-3)")
    #expect(TrackChoice.audioLabel(a(6, "und", name: "Director's Cut Mix")) == "Director's Cut Mix")
    #expect(TrackChoice.audioLabel(nil) == "–")
}

@Test func subtitleLabelsGerman() {
    #expect(TrackChoice.subtitleLabel(nil) == "Aus")
    #expect(TrackChoice.subtitleLabel(s(0, "eng")) == "Englisch")
    #expect(TrackChoice.subtitleLabel(s(1, "eng", forced: true)) == "Englisch (erzwungen)")
    #expect(TrackChoice.subtitleLabel(s(2, "de", sdh: true, ext: true)) == "Deutsch (SDH, extern)")
    #expect(TrackChoice.subtitleLabel(s(3, nil)) == "Spur 4")
}

@Test func summaryAndLogLine() {
    let audio = a(1, "ger", ch: 6, codec: "eac3")
    #expect(TrackChoice.summary(audio: audio, subtitle: nil) == "Ton Deutsch 5.1 (E-AC-3) / UT Aus")
    #expect(TrackChoice.summary(audio: audio, subtitle: s(5, "en")) == "Ton Deutsch 5.1 (E-AC-3) / UT Englisch")
    #expect(TrackChoice.overlayLine(audio: audio, subtitle: nil) == "Ton Deutsch 5.1 (E-AC-3) · Untertitel Aus · nach unten wischen: ändern")
}

// MARK: Zuordnung

@Test func activeTrackMapping() {
    let tracks = [a(1, "fre"), a(2, "eng")]
    #expect(TrackChoice.active(tracks, id: 2)?.language == "eng")
    #expect(TrackChoice.active(tracks, id: 9) == nil)
    #expect(TrackChoice.active(tracks, id: nil) == nil)
}

@Test func audioActionMapping() {
    #expect(TrackChoice.audioAction(selected: 1, active: 2, locked: false) == .apply)
    #expect(TrackChoice.audioAction(selected: 2, active: 2, locked: false) == .keep)
    #expect(TrackChoice.audioAction(selected: 1, active: nil, locked: false) == .apply)
    #expect(TrackChoice.audioAction(selected: 1, active: 2, locked: true) == .locked)
    // R2 N1: während des Neuladens geht auch die Rückkehr zur (noch gemeldeten) Ausgangsspur an die Engine
    #expect(TrackChoice.audioAction(selected: 2, active: 2, locked: false, switching: true) == .apply)
    #expect(TrackChoice.audioAction(selected: 1, active: 2, locked: false, switching: true) == .apply)
    #expect(TrackChoice.audioAction(selected: 2, active: 2, locked: true, switching: true) == .locked)
}
