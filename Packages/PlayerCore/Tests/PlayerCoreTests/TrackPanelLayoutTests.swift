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
    #expect(lines.allSatisfy { $0.count <= TrackPanelMetrics.lineBudget(columnWidth: TrackPanelMetrics.audioColumnWidth, tag: "Standard") && !$0.contains("\n") })
}

@Test func audioDuplicatesGetNameThenNumber() {
    let named = TrackPanelLayout.audioLines([a(0, "fre", ch: 6, codec: "ac3", name: "VFF"),
                                             a(1, "fre", ch: 6, codec: "ac3", name: "VFQ")])
    #expect(named == ["Französisch · VFF · Dolby Digital 5.1", "Französisch · VFQ · Dolby Digital 5.1"])
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

@Test func fitKeepsKindAndKeyShortensLanguageFirst() {
    let pt = ["Portugiesisch (Brasilien)", "Port. (BR)", "pt-BR"]
    // passt alles: Langform mit Technik
    #expect(TrackPanelLayout.fit(lead: ["Englisch"], tech: "Dolby Atmos 5.1", max: 31) == "Englisch · Dolby Atmos 5.1")
    // Technik fällt vor der Sprache, Art und Unterscheider bleiben, Sprache wird gekürzt
    #expect(TrackPanelLayout.fit(lead: pt, kind: "SDH", key: "SRT", max: 25) == "Port. (BR) · SDH · SRT")
    #expect(TrackPanelLayout.fit(lead: pt, kind: "SDH", key: "SRT", tech: "AAC", max: 28) == "Port. (BR) · SDH · SRT · AAC")
    #expect(TrackPanelLayout.fit(lead: pt, kind: "SDH", key: "Spur 12", max: 21) == "pt-BR · SDH · Spur 12")
    // zuletzt gekappt mit „…“, Art und Unterscheider bleiben
    #expect(TrackPanelLayout.fit(lead: pt, kind: "Erzwungen", key: "Spur 3", max: 26) == "pt-BR · Erzwungen · Spur 3")
    #expect(TrackPanelLayout.fit(lead: ["Serbokroatisch"], kind: "Erzwungen", key: "Spur 3", max: 24) == "Se… · Erzwungen · Spur 3")
    #expect(TrackPanelLayout.fit(lead: [], max: 10) == "")
}

@Test func languageFormsLongToShort() {
    #expect(TrackPanelLayout.languageForms("pt-BR") == ["Portugiesisch (Brasilien)", "Port. (BR)", "pt-BR"])
    #expect(TrackPanelLayout.languageForms("eng") == ["Englisch", "en"])
    #expect(TrackPanelLayout.languageForms("und") == [])
}

@Test func longLocalesStayDistinct() {
    // pt-BR SDH ×2 (SRT, PGS): Unterscheider bleibt, Sprache wird gekürzt; eng in der UT-Spalte
    let pt = TrackPanelLayout.subtitleLines([s(0, "pt-BR", sdh: true), s(1, "pt-BR", codec: "hdmv_pgs_subtitle", sdh: true)])
    #expect(pt[0] != pt[1])
    #expect(pt.allSatisfy { $0.contains("SDH") })
    #expect(pt[0].hasSuffix("SRT") && pt[1].hasSuffix("PGS Bild"))
    // gleiche Spuren ohne Format-Unterschied: „Spur n“, SDH bleibt
    let same = TrackPanelLayout.subtitleLines([s(0, "pt-BR", sdh: true, def: true), s(1, "pt-BR", sdh: true, def: true)])
    #expect(same[0] != same[1] && same.allSatisfy { $0.contains("SDH") && $0.contains("Spur") })
    let budget = TrackPanelMetrics.lineBudget(columnWidth: TrackPanelMetrics.subtitleColumnWidth, tag: "Standard")
    #expect(same.allSatisfy { $0.count <= budget })
    // es-419 erzwungen: „Erzwungen“ bleibt sichtbar
    let es = TrackPanelLayout.subtitleLines([s(0, "es-419", forced: true), s(1, "es-419", forced: true)])
    #expect(es[0] != es[1] && es.allSatisfy { $0.contains("Erzwungen") })
    // Kollision in Runde 2: Name der einen Spur gleich der Zeile der anderen
    let clash = TrackPanelLayout.subtitleLines([s(0, "ger", name: "Spur 2"), s(1, "ger", name: "Spur 2"), s(2, "ger")])
    #expect(Set(clash).count == 3)
}

@Test func lineBudgetFromColumnWidth() {
    let audioTagged = TrackPanelMetrics.lineBudget(columnWidth: TrackPanelMetrics.audioColumnWidth, tag: "Standard")
    #expect(audioTagged >= "Englisch · Dolby Atmos 5.1".count)
    #expect(TrackPanelMetrics.lineBudget(columnWidth: TrackPanelMetrics.audioColumnWidth) > audioTagged)
    let sub = TrackPanelMetrics.lineBudget(columnWidth: TrackPanelMetrics.subtitleColumnWidth)
    #expect(sub < TrackPanelMetrics.lineBudget(columnWidth: TrackPanelMetrics.audioColumnWidth))
    #expect(TrackPanelMetrics.lineBudget(columnWidth: 50, tag: "Standard") == 8)
    #expect(TrackPanelMetrics.lineBudget(columnWidth: .nan) == 8)
    // Spalten passen in den Sicherheitsrand (1920 − 2 × 80)
    let total = TrackPanelMetrics.audioColumnWidth + TrackPanelMetrics.subtitleColumnWidth
        + TrackPanelMetrics.offsetColumnWidth + 2 * TrackPanelMetrics.columnSpacing
    #expect(total <= 1760)
    // die echte Ton-Zeile mit Standard-Marke bleibt ungekürzt
    let line = TrackPanelLayout.audioLines([a(0, "eng", ch: 6, codec: "eac3", atmos: true, def: true)])
    #expect(line == ["Englisch · Dolby Atmos 5.1"])
}

@Test func lockDisablesColumns() {
    let c = TrackPanelLayout.applying(.audioSwitching, to: sample)
    #expect(c.map(\.isLocked) == [false, true, true])
    #expect(c[1].note == "lädt…" && c[2].note == "lädt…" && c[0].note == nil)
    let r = TrackPanelLayout.applying(.restoring, to: sample)
    #expect(r.map(\.isLocked) == [true, true, false])
    #expect(TrackPanelLayout.applying(nil, to: sample) == sample)
    #expect(TrackPanelLayout.audioColumn([], activeID: nil, priority: [], audioLocked: true).note == "bis Play gesperrt")
    // gesperrte Spalten sind kein Startfokus
    #expect(TrackPanelLayout.initialSpot([TrackPanelLayout.audioColumn([], activeID: nil, priority: []), c[1], c[2]]) == nil)
}

@Test func trackLockAudioSwitching() {
    #expect(TrackLock.current(restoring: false, recovering: false, loadInFlight: false, startPending: false,
                              waitingForNetwork: false, engineError: false, audioSwitching: true) == .audioSwitching)
    #expect(TrackLock.current(restoring: true, recovering: false, loadInFlight: false, startPending: false,
                              waitingForNetwork: false, engineError: false, audioSwitching: true) == .restoring)
    #expect(!TrackLock.audioSwitching.blocksOpening && TrackLock.loading.blocksOpening)
    #expect(!TrackLock.audioSwitching.blocks(.audio) && TrackLock.audioSwitching.blocks(.subtitles) && TrackLock.audioSwitching.blocks(.offset))
    #expect(TrackLock.loading.blocks(.audio) && !TrackLock.loading.blocks(.offset))
    #expect(TrackLock.audioSwitching.logText == "Tonwechsel lädt")
    // Tonwechsel hindert das Öffnen nicht
    let step = TrackPanelEntry.decide(leaving: false, scrubbing: false, upNextShowing: false, failureShowing: false,
                                      alreadyOpen: false, skipPromptShowing: false, lock: .audioSwitching)
    #expect(step == .open)
}

@Test func audioSwitchWatchEnds() {
    let t0 = Date(timeIntervalSince1970: 1000)
    var w = AudioSwitchWatch()
    let idle = w.update(activeID: 1, isLoading: false, failed: false, now: t0)
    #expect(idle == nil && !w.isActive)
    w.begin(2, now: t0)
    let r1 = w.update(activeID: 1, isLoading: true, failed: false, now: t0 + 1)
    #expect(r1 == nil && w.isActive)
    let r2 = w.update(activeID: 2, isLoading: true, failed: false, now: t0 + 2)
    #expect(r2 == nil)
    let r3 = w.update(activeID: 2, isLoading: false, failed: false, now: t0 + 3)
    #expect(r3 == .done && !w.isActive)
    // nichts lädt, Spur bleibt: verworfen nach 3 s (vorher läuft es)
    w.begin(3, now: t0)
    let r4 = w.update(activeID: 1, isLoading: false, failed: false, now: t0 + 2.9)
    #expect(r4 == nil)
    let r5 = w.update(activeID: 1, isLoading: false, failed: false, now: t0 + 3)
    #expect(r5 == .ignored)
    // lädt ewig: harte Grenze
    w.begin(3, now: t0)
    let r6 = w.update(activeID: 1, isLoading: true, failed: false, now: t0 + 10)
    #expect(r6 == nil)
    let r7 = w.update(activeID: 1, isLoading: true, failed: false, now: t0 + 30)
    #expect(r7 == .timedOut)
    w.begin(3, now: t0)
    let r8 = w.update(activeID: 1, isLoading: true, failed: true, now: t0 + 1)
    #expect(r8 == .failed)
}

@Test func infoFooterLine() {
    let rows = [TrackPanelInfoRow(label: "Auflösung", value: "4K"), TrackPanelInfoRow(label: "Dynamik", value: "HDR10"),
                TrackPanelInfoRow(label: "Ton-Ausgabe", value: "PCM 7.1 (dekodiert)")]
    #expect(TrackPanelLayout.infoLine(rows) == "4K · HDR10 · Ton-Ausgabe: PCM 7.1 (dekodiert)")
    #expect(TrackPanelLayout.infoLine([]) == nil)
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
    #expect(c.note == "wirkt hier nicht")
    #expect(TrackPanelLayout.offsetColumn(offset: 0, nativeTrack: false).note == nil)
}

@Test func focusStartsOnActiveAudio() {
    #expect(TrackPanelLayout.initialSpot(sample) == TrackPanelSpot(.audio, .track(0)))
    let noAudio = [TrackPanelLayout.audioColumn([], activeID: nil, priority: []), sample[1], sample[2]]
    #expect(TrackPanelLayout.initialSpot(noAudio) == TrackPanelSpot(.subtitles, .track(5)))
    let nothing = [TrackPanelLayout.audioColumn([], activeID: nil, priority: []), TrackPanelLayout.offsetColumn(offset: 0, nativeTrack: false)]
    #expect(TrackPanelLayout.initialSpot(nothing) == nil)
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
    // aus Versatz zurück nach Untertitel: aktive Zeile
    #expect(TrackPanelLayout.redirect(from: TrackPanelSpot(.offset, .step(0)), to: TrackPanelSpot(.subtitles, .track(6)), columns: c)
            == TrackPanelSpot(.subtitles, .track(5)))
}

@Test func swipeUpGestureIsRecognised() {
    #expect(TrackPanelEntry.isSwipeUp(translationX: 10, translationY: -200, velocityY: -300))
    #expect(TrackPanelEntry.isSwipeUp(translationX: 0, translationY: -80, velocityY: -900))
    #expect(!TrackPanelEntry.isSwipeUp(translationX: 0, translationY: 200, velocityY: 300))
    #expect(!TrackPanelEntry.isSwipeUp(translationX: 200, translationY: -200, velocityY: -900))
}


/// R2 N2: Die Zeitgrenzen allein (ohne jede Engine-Änderung) beenden jeden Wechsel; der Takt folgt `nextDeadline`.
@Test func audioSwitchWatchNeverSticks() {
    let t0 = Date(timeIntervalSince1970: 1000)
    var w = AudioSwitchWatch()
    #expect(w.nextDeadline == nil)
    // Engine verwirft still (Remote-HLS): Frist 3 s, dort Ende
    w.begin(2, now: t0)
    #expect(w.nextDeadline == t0 + AudioSwitchWatch.ignoreAfter)
    let r1 = w.update(activeID: 1, isLoading: false, failed: false, now: w.nextDeadline!)
    #expect(r1 == .ignored && w.nextDeadline == nil)
    // lädt, wird nie fertig: nach der 3-s-Frist gilt die harte Grenze
    w.begin(2, now: t0)
    let r2 = w.update(activeID: 1, isLoading: true, failed: false, now: t0 + 3)
    #expect(r2 == nil && w.nextDeadline == t0 + AudioSwitchWatch.giveUpAfter)
    let r3 = w.update(activeID: 1, isLoading: true, failed: false, now: w.nextDeadline!)
    #expect(r3 == .timedOut && !w.isActive)
    // zweite Wahl während des Neuladens: kein „verworfen“, Frist bleibt die harte Grenze ab der neuen Wahl
    w.begin(2, now: t0)
    let r4 = w.update(activeID: 1, isLoading: true, failed: false, now: t0 + 1)
    #expect(r4 == nil)
    w.begin(1, now: t0 + 2)
    #expect(w.nextDeadline == t0 + 2 + AudioSwitchWatch.giveUpAfter)
    let r5 = w.update(activeID: 1, isLoading: true, failed: false, now: t0 + 6)
    #expect(r5 == nil)
    let r6 = w.update(activeID: 1, isLoading: false, failed: false, now: t0 + 7)
    #expect(r6 == .done)
}
