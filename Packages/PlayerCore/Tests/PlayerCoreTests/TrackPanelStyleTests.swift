import Foundation
import Testing
@testable import PlayerCore

private func a(_ id: Int, _ lang: String?, ch: Int? = nil, codec: String? = nil) -> AudioTrackInfo {
    AudioTrackInfo(id: id, language: lang, channels: ch, codec: codec)
}

private func s(_ id: Int, _ lang: String?) -> AudioTrackInfo {
    AudioTrackInfo(id: id, language: lang, codec: "subrip")
}

private func step(_ style: TrackPanelStyle, _ g: TrackPanelGesture, upNext: Bool = false,
                  open: Bool = false, lock: TrackLock? = nil) -> TrackPanelEntry.Step {
    TrackPanelEntry.decide(style: style, gesture: g, leaving: false, scrubbing: false,
                           upNextShowing: upNext, failureShowing: false, alreadyOpen: open, skipPromptShowing: false, lock: lock)
}

// MARK: Geste je Stil

@Test func gestureMappingPerStyle() {
    // Leiste oben: wie bisher nur nach unten; Wisch/▲ nach oben tut nichts
    #expect(step(.topBar, .swipeDown) == .open)
    #expect(step(.topBar, .clickDown) == .open)
    #expect(step(.topBar, .swipeUp) == .ignore(.otherGesture))
    #expect(step(.topBar, .clickUp) == .ignore(.otherGesture))
    // Leiste unten: gespiegelt
    #expect(step(.bottomBar, .swipeUp) == .open)
    #expect(step(.bottomBar, .clickUp) == .open)
    #expect(step(.bottomBar, .swipeDown) == .ignore(.otherGesture))
    #expect(step(.bottomBar, .clickDown) == .ignore(.otherGesture))
    // Menü: Wisch nach oben und ▲ (R1 M1: auch bei sichtbarer Steuerleiste)
    #expect(step(.menu, .swipeUp) == .open)
    #expect(step(.menu, .clickUp) == .open)
    #expect(step(.menu, .swipeDown) == .ignore(.otherGesture))
    #expect(step(.menu, .clickDown) == .ignore(.otherGesture))
}

@Test func styleGestureKeepsOtherRules() {
    // Fremde Geste bricht kein Up-next ab; die eigene schon (wie jede Richtungstaste)
    #expect(step(.bottomBar, .swipeDown, upNext: true) == .ignore(.otherGesture))
    #expect(step(.bottomBar, .swipeUp, upNext: true) == .cancelUpNext)
    #expect(step(.menu, .swipeUp, open: true) == .ignore(.alreadyOpen))
    #expect(step(.menu, .swipeUp, lock: .restoring) == .ignore(.busy(.restoring)))
    // Tonwechsel hindert das Öffnen in keinem Stil
    for st in TrackPanelStyle.allCases {
        let g: TrackPanelGesture = st == .topBar ? .swipeDown : .swipeUp
        #expect(step(st, g, lock: .audioSwitching) == .open)
    }
    #expect(TrackPanelEntry.IgnoreReason.otherGesture.logText == "Geste gehört nicht zum Stil")
    #expect(TrackPanelGesture.clickUp.logText == "▲ Klick" && TrackPanelGesture.swipeUp.isSwipe && !TrackPanelGesture.clickUp.isSwipe)
    #expect(!TrackPanelStyle.topBar.coversBottom && TrackPanelStyle.bottomBar.coversBottom && TrackPanelStyle.menu.coversBottom)
    #expect(TrackPanelStyle.allCases.map(\.title) == ["Seite", "Unten", "Mitte"])   // Task 5.4
}

// MARK: Schließen per Wisch

@Test func swipeClosesPerStyle() {
    let cols = [TrackPanelLayout.audioColumn([a(0, "deu"), a(1, "eng"), a(2, "fre")], activeID: 0, priority: ["de"]),
                TrackPanelLayout.subtitleColumn([], activeID: nil, preferredLanguage: nil)]
    let top = TrackPanelSpot(.audio, .track(0)), mid = TrackPanelSpot(.audio, .track(1)), last = TrackPanelSpot(.audio, .track(2))
    // oben: Wisch nach oben aus der obersten Zeile; nach unten nie
    #expect(TrackPanelLayout.closesOnSwipe(.swipeUp, style: .topBar, startSpot: top, columns: cols))
    #expect(!TrackPanelLayout.closesOnSwipe(.swipeUp, style: .topBar, startSpot: mid, columns: cols))
    #expect(!TrackPanelLayout.closesOnSwipe(.swipeDown, style: .topBar, startSpot: last, columns: cols))
    // unten: Wisch nach unten aus der untersten Zeile, sonst Listenschritt; nach oben nie
    #expect(TrackPanelLayout.closesOnSwipe(.swipeDown, style: .bottomBar, startSpot: last, columns: cols))
    #expect(!TrackPanelLayout.closesOnSwipe(.swipeDown, style: .bottomBar, startSpot: mid, columns: cols))
    #expect(!TrackPanelLayout.closesOnSwipe(.swipeUp, style: .bottomBar, startSpot: top, columns: cols))
    // „Aus“ ist die einzige Untertitel-Zeile: oberste und unterste zugleich
    let off = TrackPanelSpot(.subtitles, .off)
    #expect(TrackPanelLayout.closesOnSwipe(.swipeDown, style: .bottomBar, startSpot: off, columns: cols))
    #expect(TrackPanelLayout.closesOnSwipe(.swipeDown, style: .bottomBar, startSpot: nil, columns: cols))
    // Menü: nie per Wisch
    #expect(!TrackPanelLayout.closesOnSwipe(.swipeDown, style: .menu, startSpot: nil, columns: cols))
    #expect(!TrackPanelLayout.closesOnSwipe(.swipeUp, style: .menu, startSpot: nil, columns: cols))
}

/// User decision 26.11.: „Unten“ shows Ton | Untertitel in one row with Versatz as a strip below. A swipe down
/// from the strip closes; from the last row of Ton or Untertitel it steps down onto the strip, unless the strip
/// cannot take focus (locked), then that row is the lowest and closes as before.
@Test func bottomBarSwipeDownClosesFromOffsetStrip() {
    let audio = TrackPanelLayout.audioColumn([a(0, "deu"), a(1, "eng")], activeID: 0, priority: ["de"])
    let subs = TrackPanelLayout.subtitleColumn([], activeID: nil, preferredLanguage: nil)
    let offset = TrackPanelLayout.offsetColumn(offset: 0, nativeTrack: false)
    let cols = [audio, subs, offset]
    let lastAudio = TrackPanelSpot(.audio, .track(1)), off = TrackPanelSpot(.subtitles, .off)
    #expect(!TrackPanelLayout.closesOnSwipe(.swipeDown, style: .bottomBar, startSpot: lastAudio, columns: cols))
    #expect(!TrackPanelLayout.closesOnSwipe(.swipeDown, style: .bottomBar, startSpot: off, columns: cols))
    #expect(TrackPanelLayout.closesOnSwipe(.swipeDown, style: .bottomBar, startSpot: TrackPanelSpot(.offset, .step(0)), columns: cols))
    #expect(TrackPanelLayout.closesOnSwipe(.swipeDown, style: .bottomBar, startSpot: TrackPanelSpot(.offset, .reset), columns: cols))
    #expect(!TrackPanelLayout.closesOnSwipe(.swipeUp, style: .bottomBar, startSpot: TrackPanelSpot(.offset, .reset), columns: cols))
    #expect(TrackPanelLayout.closesOnSwipe(.swipeDown, style: .bottomBar, startSpot: nil, columns: cols))
    // Strip locked (audio reload): the last list row is the lowest focusable row again.
    let locked = TrackPanelLayout.applying(.audioSwitching, to: cols)
    #expect(locked.first { $0.column == .offset }?.isLocked == true)
    #expect(TrackPanelLayout.closesOnSwipe(.swipeDown, style: .bottomBar, startSpot: lastAudio, columns: locked))
    // Seite keeps its rule: Versatz is stacked, a swipe down is a list step.
    #expect(!TrackPanelLayout.closesOnSwipe(.swipeDown, style: .topBar, startSpot: TrackPanelSpot(.offset, .reset), columns: cols))
}

@Test func bottomBarDetailNamesTwoColumnsAndStrip() {
    #expect(TrackPanelStyle.bottomBar.detail
            == "Wisch nach oben öffnet eine Karte am unteren Rand mit den Spalten Ton und Untertitel, darunter Versatz.")
}

// MARK: Einstellung

@Test func trackPanelStyleSettingDecodes() throws {
    #expect(PlayerComfortSettings().trackPanelStyle == .topBar)
    let old = try JSONDecoder().decode(PlayerComfortSettings.self, from: Data(#"{"rememberTracks":false}"#.utf8))
    #expect(old.trackPanelStyle == .topBar && !old.rememberTracks)
    let unknown = try JSONDecoder().decode(PlayerComfortSettings.self, from: Data(#"{"trackPanelStyle":"sidebar"}"#.utf8))
    #expect(unknown.trackPanelStyle == .topBar)
    var s = PlayerComfortSettings()
    s.trackPanelStyle = .menu
    let back = try JSONDecoder().decode(PlayerComfortSettings.self, from: JSONEncoder().encode(s))
    #expect(back.trackPanelStyle == .menu)
}

/// R1 M4: Versatz betreten landet auf +0,1 s, nicht auf dem größten Schritt zurück.
@Test func offsetEntryRowIsGentle() {
    let c = TrackPanelLayout.offsetColumn(offset: 0, nativeTrack: false)
    #expect(c.entryRow == .step(2))
    #expect(SubtitleOffset.steps[2] == 0.1)
    // andere Spalten unverändert: aktive Zeile
    let audio = TrackPanelLayout.audioColumn([a(0, "deu"), a(1, "eng")], activeID: 1, priority: ["de"])
    #expect(audio.entryRow == .track(1))
}
