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

// MARK: Menü

private func menuColumns(lock: TrackLock? = nil, audio: [AudioTrackInfo] = [a(0, "deu", ch: 6, codec: "ac3"), a(1, "eng")]) -> [TrackPanelColumnModel] {
    TrackPanelLayout.applying(lock, to: [
        TrackPanelLayout.audioColumn(audio, activeID: audio.first?.id, priority: ["de"], width: TrackMenuMetrics.width),
        TrackPanelLayout.subtitleColumn([s(5, "deu")], activeID: nil, preferredLanguage: "de", width: TrackMenuMetrics.width),
        TrackPanelLayout.offsetColumn(offset: 0.3, nativeTrack: false)])
}

@Test func menuEntriesShowCurrentChoice() {
    let e = TrackMenuNav.entries(menuColumns(), offset: 0.3)
    #expect(e.map(\.title) == ["Ton", "Untertitel", "Versatz"])
    #expect(e[0].detail == "Deutsch · Dolby Digital 5.1")
    #expect(e[1].detail == "Aus")
    #expect(e[2].detail == "+0,3 s")
    #expect(e.allSatisfy { !$0.isLocked && !$0.isEmpty })
    // Tonwechsel: Untertitel/Versatz gesperrt mit „lädt…“
    let locked = TrackMenuNav.entries(menuColumns(lock: .audioSwitching), offset: 0)
    #expect(!locked[0].isLocked && locked[1].isLocked && locked[2].isLocked)
    #expect(locked[1].note == "lädt…")
    #expect(locked[2].detail == "0,0 s")
    // ohne Tonspuren
    let none = TrackMenuNav.entries(menuColumns(audio: []), offset: 0)
    #expect(none[0].isEmpty && none[0].detail == "Keine Tonspuren")
    let start = TrackMenuNav(entries: none)
    #expect(start.rootFocus == .subtitles && start.level == .root)
}

@Test func menuNavigation() {
    let e = TrackMenuNav.entries(menuColumns(), offset: 0)
    var nav = TrackMenuNav(entries: e)
    #expect(nav.level == .root && nav.rootFocus == .audio)
    // Menü auf Ebene 1 schließt
    var closing = nav
    let b0 = closing.back()
    #expect(b0 == .close)
    // Ebene 2 öffnen, Menü geht zurück mit Fokus auf dem Eintrag
    let o1 = nav.open(e[1])
    #expect(o1 && nav.level == .list(.subtitles))
    let b1 = nav.back()
    #expect(b1 == .toRoot && nav.level == .root && nav.rootFocus == .subtitles)
    // Wahl: Ton/Untertitel zurück auf Ebene 1, Versatz bleibt in der Liste
    _ = nav.open(e[0])
    nav.picked(.audio)
    #expect(nav.level == .root && nav.rootFocus == .audio)
    _ = nav.open(e[2])
    nav.picked(.offset)
    #expect(nav.level == .list(.offset))
    // Wahl aus einer anderen Ebene ändert nichts
    nav.picked(.audio)
    #expect(nav.level == .list(.offset))
    // Aus Ebene 2 lässt sich kein weiterer Eintrag öffnen
    let o2 = nav.open(e[0])
    #expect(!o2 && nav.level == .list(.offset))
    // gesperrt oder leer: bleibt auf Ebene 1
    var n2 = TrackMenuNav()
    let locked = TrackMenuNav.entries(menuColumns(lock: .audioSwitching), offset: 0)
    let o3 = n2.open(locked[1])
    #expect(!o3 && n2.level == .root)
    let empty = TrackMenuNav.entries(menuColumns(audio: []), offset: 0)
    let o4 = n2.open(empty[0])
    #expect(!o4 && n2.level == .root)
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
