import Foundation
import Testing
@testable import PlayerCore

private func a(_ id: Int, _ lang: String?, ch: Int? = nil, codec: String? = nil, name: String? = nil, atmos: Bool = false,
               def: Bool = false, commentary: Bool = false) -> AudioTrackInfo {
    AudioTrackInfo(id: id, language: lang, name: name, channels: ch, codec: codec, isDefault: def,
                   isCommentary: commentary, isAtmos: atmos)
}

private func s(_ id: Int, _ lang: String?, codec: String = "subrip", forced: Bool = false, sdh: Bool = false,
               ext: Bool = false, def: Bool = false, name: String? = nil) -> AudioTrackInfo {
    AudioTrackInfo(id: id, language: lang, name: name, codec: codec, isDefault: def, isForced: forced,
                   isHearingImpaired: sdh, isExternal: ext)
}

// MARK: Zeilen

@Test func audioLineIsOneShortLine() {
    let tracks = [a(0, "eng", ch: 6, codec: "eac3", atmos: true), a(1, "fre", ch: 6, codec: "ac3", name: "VFF", def: true)]
    let lines = TrackPanelLayout.audioLines(tracks)
    #expect(lines == ["Englisch · Dolby Atmos 5.1", "Französisch · Dolby Digital 5.1"])
    #expect(TrackPanelLayout.tag(tracks[1]) == "Standard")
    #expect(TrackPanelLayout.tag(tracks[0]) == nil)
    #expect(lines.allSatisfy { $0.count <= TrackPanelLayout.maxLineLength && !$0.contains("\n") })
}

@Test func audioDuplicatesGetNameThenNumber() {
    let named = TrackPanelLayout.audioLines([a(0, "fre", ch: 6, codec: "ac3", name: "VFF"),
                                             a(1, "fre", ch: 6, codec: "ac3", name: "VFQ")])
    // Name geht vor der Technik, die wegfällt, wenn die Zeile zu lang wird
    #expect(named == ["Französisch · VFF", "Französisch · VFQ"])
    let plain = TrackPanelLayout.audioLines([a(0, "ger", ch: 2, codec: "aac"), a(1, "ger", ch: 2, codec: "aac")])
    #expect(plain == ["Deutsch · Spur 1 · AAC Stereo", "Deutsch · Spur 2 · AAC Stereo"])
    let comm = TrackPanelLayout.audioLines([a(0, "eng", ch: 2, codec: "aac", commentary: true)])
    #expect(comm == ["Englisch · Kommentar · AAC Stereo"])
}

@Test func subtitleLinesAreLanguageAndKind() {
    let lines = TrackPanelLayout.subtitleLines([s(0, "eng"), s(1, "eng", forced: true), s(2, "eng", sdh: true)])
    #expect(lines == ["Englisch", "Englisch · Erzwungen", "Englisch · SDH"])
    // Gleiche Zeilen: Format unterscheidet, sonst die Nummer
    let byFormat = TrackPanelLayout.subtitleLines([s(0, "ger"), s(1, "ger", codec: "hdmv_pgs_subtitle")])
    #expect(byFormat == ["Deutsch · SRT", "Deutsch · PGS Bild"])
    let byNumber = TrackPanelLayout.subtitleLines([s(0, "ger"), s(1, "ger")])
    #expect(byNumber == ["Deutsch · Spur 1", "Deutsch · Spur 2"])
    #expect(TrackPanelLayout.tag(s(3, "eng", ext: true)) == "Extern")
    #expect(TrackPanelLayout.tag(s(3, "eng", ext: true, def: true)) == "Standard")
}

@Test func fitDropsTailAndShortensLead() {
    #expect(TrackPanelLayout.fit(["Englisch", nil, "", "Dolby Atmos 5.1"]) == "Englisch · Dolby Atmos 5.1")
    #expect(TrackPanelLayout.fit(["Französisch", "Kommentar", "Dolby Digital+ 5.1"], max: 26) == "Französisch · Kommentar")
    let long = TrackPanelLayout.fit([String(repeating: "x", count: 50), "AAC"], max: 10)
    #expect(long == "xxxxxxxxx…")
    #expect(TrackPanelLayout.fit([nil, ""]) == "")
}

@Test func shortFormatDropsCarrier() {
    #expect(TrackPanelLayout.shortAudioFormat(a(0, "eng", codec: "truehd", atmos: true)) == "Dolby Atmos")
    #expect(TrackPanelLayout.shortAudioFormat(a(0, "eng", codec: "dts")) == "DTS")
    #expect(TrackPanelLayout.shortAudioFormat(a(0, "eng", codec: nil)) == nil)
    // Unbekannte Sprache ohne Namen: Format als Hauptteil
    #expect(TrackPanelLayout.audioLines([a(0, nil, ch: 2, codec: "aac")]) == ["AAC · Stereo"])
}

// MARK: Spalten und Fokus

private var sample: [TrackPanelColumnModel] {
    [TrackPanelLayout.audioColumn([a(0, "eng", ch: 6, codec: "eac3"), a(1, "ger", ch: 6, codec: "ac3")], activeID: 0, priority: ["de"]),
     TrackPanelLayout.subtitleColumn([s(5, "eng"), s(6, "ger")], activeID: 5, preferredLanguage: "de"),
     TrackPanelLayout.offsetColumn(offset: 0, nativeTrack: false)]
}

@Test func columnsOrderAndActive() {
    let c = sample
    #expect(c.map(\.title) == ["Ton", "Untertitel", "Versatz"])
    #expect(c[0].rows.map(\.id) == [.track(1), .track(0)])           // Profil-Tonsprache zuerst
    #expect(c[0].rows.filter(\.isActive).map(\.id) == [.track(0)])
    #expect(c[1].rows.map(\.id) == [.off, .track(6), .track(5)])
    #expect(c[1].entryRow == .track(5))
    #expect(c[2].rows.map(\.id) == [.step(0), .step(1), .step(2), .step(3), .reset])
    #expect(c[2].rows.map(\.line) == ["\u{2212}0,5 s", "\u{2212}0,1 s", "+0,1 s", "+0,5 s", "Zurücksetzen"])
    let off = TrackPanelLayout.subtitleColumn([s(5, "eng")], activeID: nil, preferredLanguage: nil)
    #expect(off.rows.filter(\.isActive).map(\.id) == [.off])
    let missing = TrackPanelLayout.subtitleColumn([s(5, "eng")], activeID: 9, preferredLanguage: nil)
    #expect(missing.entryRow == .off)
}

@Test func offsetColumnTitleAndNote() {
    let c = TrackPanelLayout.offsetColumn(offset: 0.3, nativeTrack: true)
    #expect(c.title == "Versatz +0,3 s")
    #expect(c.note == "wirkt bei dieser Spur nicht")
    #expect(TrackPanelLayout.offsetColumn(offset: 0, nativeTrack: false).note == nil)
}

@Test func focusStartsOnActiveAudio() {
    #expect(TrackPanelLayout.initialSpot(sample) == TrackPanelSpot(.audio, .track(0)))
    let noAudio = [TrackPanelLayout.audioColumn([], activeID: nil, priority: []), sample[1], sample[2]]
    #expect(TrackPanelLayout.initialSpot(noAudio) == TrackPanelSpot(.subtitles, .track(5)))
}

@Test func columnSwitchLandsOnActiveRow() {
    let c = sample
    // ◀/▶ von Ton nach Untertitel: auf der aktiven Zeile, nicht der nächstgelegenen
    #expect(TrackPanelLayout.redirect(from: TrackPanelSpot(.audio, .track(1)), to: TrackPanelSpot(.subtitles, .off), columns: c)
            == TrackPanelSpot(.subtitles, .track(5)))
    // schon richtig, gleiche Spalte, erster Fokus, Versatz: nichts umlenken
    #expect(TrackPanelLayout.redirect(from: TrackPanelSpot(.audio, .track(1)), to: TrackPanelSpot(.subtitles, .track(5)), columns: c) == nil)
    #expect(TrackPanelLayout.redirect(from: TrackPanelSpot(.audio, .track(1)), to: TrackPanelSpot(.audio, .track(0)), columns: c) == nil)
    #expect(TrackPanelLayout.redirect(from: nil, to: TrackPanelSpot(.subtitles, .off), columns: c) == nil)
    #expect(TrackPanelLayout.redirect(from: TrackPanelSpot(.subtitles, .off), to: TrackPanelSpot(.offset, .step(2)), columns: c) == nil)
}

@Test func swipeUpClosesOnlyFromTopRow() {
    let c = sample
    #expect(TrackPanelLayout.closesOnSwipeUp(startSpot: TrackPanelSpot(.audio, .track(1)), columns: c))
    #expect(!TrackPanelLayout.closesOnSwipeUp(startSpot: TrackPanelSpot(.audio, .track(0)), columns: c))
    #expect(TrackPanelLayout.closesOnSwipeUp(startSpot: TrackPanelSpot(.subtitles, .off), columns: c))
    #expect(!TrackPanelLayout.closesOnSwipeUp(startSpot: TrackPanelSpot(.offset, .reset), columns: c))
    #expect(TrackPanelLayout.closesOnSwipeUp(startSpot: nil, columns: c))
    #expect(TrackPanelEntry.isSwipeUp(translationX: 10, translationY: -200, velocityY: -300))
    #expect(TrackPanelEntry.isSwipeUp(translationX: 0, translationY: -80, velocityY: -900))
    #expect(!TrackPanelEntry.isSwipeUp(translationX: 0, translationY: 200, velocityY: 300))
    #expect(!TrackPanelEntry.isSwipeUp(translationX: 200, translationY: -200, velocityY: -900))
}

@Test func panelIsOneThirdHigh() {
    #expect(TrackPanelLayout.panelHeight(screenHeight: 1080) == 360)
    #expect(TrackPanelLayout.panelHeight(screenHeight: 2160) == 720)
    #expect(TrackPanelLayout.panelHeight(screenHeight: .nan) == 0)
}
