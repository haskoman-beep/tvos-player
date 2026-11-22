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

@Test func entryOpensOnlyWhenFree() {
    let open = TrackPanelEntry.decide(leaving: false, scrubbing: false, upNextShowing: false, failureShowing: false, alreadyOpen: false)
    #expect(open == .open)
    let leaving = TrackPanelEntry.decide(leaving: true, scrubbing: false, upNextShowing: false, failureShowing: false, alreadyOpen: false)
    #expect(leaving == .ignore)
    let scrub = TrackPanelEntry.decide(leaving: false, scrubbing: true, upNextShowing: false, failureShowing: false, alreadyOpen: false)
    #expect(scrub == .ignore)
    let failure = TrackPanelEntry.decide(leaving: false, scrubbing: false, upNextShowing: false, failureShowing: true, alreadyOpen: false)
    #expect(failure == .ignore)
    let twice = TrackPanelEntry.decide(leaving: false, scrubbing: false, upNextShowing: false, failureShowing: false, alreadyOpen: true)
    #expect(twice == .ignore)
    let upNext = TrackPanelEntry.decide(leaving: false, scrubbing: false, upNextShowing: true, failureShowing: false, alreadyOpen: false)
    #expect(upNext == .cancelUpNext)
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
    // Was als Wisch nach unten zählt, ist nie waagerecht genug zum Spulen.
    for (x, y) in [(0.0, 300.0), (100, 160), (199, 300), (-150, 240)] {
        if TrackPanelEntry.isSwipeDown(translationX: x, translationY: y, velocityY: 0) {
            #expect(!ScrubPlanner.panIsHorizontal(translationX: x, translationY: y))
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
}
