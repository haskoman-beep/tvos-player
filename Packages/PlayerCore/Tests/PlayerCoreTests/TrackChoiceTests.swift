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

// MARK: Automatische Tonwahl ohne Kommentar und Hörfilm

private func sp(_ id: Int, _ lang: String?, ch: Int, codec: String, commentary: Bool = false,
                hoerfilm: Bool = false) -> AudioTrackInfo {
    AudioTrackInfo(id: id, language: lang, channels: ch, codec: codec,
                   isCommentary: commentary, isVisualImpaired: hoerfilm)
}

@Test func commentaryInDolbyLosesToMainAAC() {
    // Hauptton AAC 2.0 gegen Kommentar AC-3 2.0 (früher 2 gegen 102 Punkte).
    let tracks = [sp(0, "ger", ch: 2, codec: "aac"), sp(1, "ger", ch: 2, codec: "ac3", commentary: true)]
    #expect(preferredAudioTrack(tracks, priority: ["de"])?.id == 0)
    // Auch Surround-Kommentar gegen Mono-Hauptton.
    let t2 = [sp(0, "eng", ch: 1, codec: "flac"), sp(1, "eng", ch: 6, codec: "eac3", commentary: true),
              sp(2, "ger", ch: 6, codec: "eac3")]
    #expect(preferredAudioTrack(t2, priority: ["en", "de"])?.id == 0)
    // Nur Kommentar in der Sprache: nie automatisch, die nächste Sprache bzw. der Rückfall gilt.
    let onlyCommentary = [sp(0, "ger", ch: 2, codec: "ac3", commentary: true), sp(1, "jpn", ch: 2, codec: "aac"),
                          sp(2, "eng", ch: 6, codec: "eac3")]
    #expect(preferredAudioTrack(onlyCommentary, priority: ["de"])?.id == 1)
    #expect(preferredAudioTrack(onlyCommentary, priority: ["de", "en"])?.id == 2)
    // "orig" und der letzte Rückfall nehmen die erste Spur, die kein Kommentar ist.
    #expect(preferredAudioTrack(onlyCommentary, priority: ["orig"])?.id == 1)
    #expect(preferredAudioTrack(onlyCommentary, priority: ["fr"])?.id == 1)
    // Nur Kommentarspuren in der ganzen Datei: die erste Spur als letzter Ausweg.
    let all = [sp(0, "ger", ch: 2, codec: "ac3", commentary: true), sp(1, "eng", ch: 2, codec: "ac3", commentary: true)]
    #expect(preferredAudioTrack(all, priority: ["en"])?.id == 0)
    #expect(preferredAudioTrack(all, priority: ["orig"])?.id == 0)
}

@Test func hoerfilmOnlyWhenNoOtherTrackOfLanguage() {
    // Hörfilm E-AC-3 5.1 gegen Hauptton TrueHD 7.1 (früher 1106 gegen 1008 Punkte).
    let tracks = [sp(0, "eng", ch: 8, codec: "truehd"), sp(1, "eng", ch: 6, codec: "eac3", hoerfilm: true)]
    #expect(preferredAudioTrack(tracks, priority: ["en"])?.id == 0)
    // Nur Hörfilm in der Sprache: er wird gewählt, vor einem Kommentar derselben Sprache.
    let only = [sp(0, "eng", ch: 6, codec: "eac3"), sp(1, "ger", ch: 2, codec: "ac3", commentary: true),
                sp(2, "ger", ch: 2, codec: "aac", hoerfilm: true)]
    #expect(preferredAudioTrack(only, priority: ["de", "en"])?.id == 2)
    // Gedächtnis ohne Hörfilm-Merker folgt derselben Regel.
    #expect(TrackMemoryPlan.audio(TrackMemory(audioLanguage: "en"), tracks: tracks)?.id == 0)
    #expect(TrackMemoryPlan.audio(TrackMemory(audioLanguage: "de"), tracks: only)?.id == 2)
    // Als Hörfilm gemerkt: der Hörfilm kommt wieder; fehlt er, die übliche Wahl.
    var m = TrackMemory()
    m.apply(.audio(tracks[1]))
    #expect(m.audioLanguage == "en" && m.audioVisualImpaired == true && m.audioCommentary == false)
    #expect(TrackMemoryPlan.audio(m, tracks: tracks)?.id == 1)
    #expect(TrackMemoryPlan.audio(m, tracks: [tracks[0]])?.id == 0)
}

@Test func trackMemoryMayRepickCommentaryExplicitly() {
    let tracks = [sp(0, "ger", ch: 2, codec: "aac"), sp(1, "ger", ch: 2, codec: "ac3", commentary: true),
                  sp(2, "ger", ch: 6, codec: "eac3", commentary: true)]
    var m = TrackMemory()
    m.apply(.audio(tracks[1]))
    #expect(m.audioLanguage == "de" && m.audioCommentary == true && m.audioVisualImpaired == false)
    // Gemerkt als Kommentar: beste Kommentarspur der Sprache.
    #expect(TrackMemoryPlan.audio(m, tracks: tracks)?.id == 2)
    // Wieder Hauptton gewählt: Merker fällt.
    m.apply(.audio(tracks[0]))
    #expect(m.audioCommentary == false)
    #expect(TrackMemoryPlan.audio(m, tracks: tracks)?.id == 0)
    // Alter Eintrag (nur Sprache): nie Kommentar, auch wenn es in der Sprache nur Kommentar gibt (wie bisher).
    #expect(TrackMemoryPlan.audio(TrackMemory(audioLanguage: "de"), tracks: Array(tracks.dropFirst())) == nil)
    // Spur ohne Sprache löscht auch die Merker.
    m.apply(.audio(tracks[1])); m.apply(.audio(sp(3, nil, ch: 2, codec: "aac")))
    #expect(m.audioLanguage == nil && m.audioCommentary == nil && m.audioVisualImpaired == nil)
}

/// Spur-Gedächtnis wie Build 249/250, Build 1 und Build 2 es lesen (Decoder unverändert seit Build 249).
private struct OldTrackMemory: Decodable {
    var audioLanguage: String?
    var subtitle: TrackMemory.SubtitleChoice?
    var subtitleOffset: Double?
    var updated: Date
    enum CodingKeys: String, CodingKey { case audioLanguage, subtitle, subtitleOffset, updated }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        audioLanguage = (try? c.decodeIfPresent(String.self, forKey: .audioLanguage)) ?? nil
        subtitle = (try? c.decodeIfPresent(TrackMemory.SubtitleChoice.self, forKey: .subtitle)) ?? nil
        subtitleOffset = (try? c.decodeIfPresent(Double.self, forKey: .subtitleOffset)) ?? nil
        updated = (try? c.decodeIfPresent(Date.self, forKey: .updated)) ?? nil ?? .distantPast
    }
}

private struct OldTrackMemoryBook: Decodable { var entries: [String: OldTrackMemory] }

@Test func trackMemoryFixtureOfBuild2StillLoadsAndNewKeysStayReadable() throws {
    let data = try fixture("build2-trackmemory.json")
    let book = try JSONDecoder().decode(TrackMemoryBook.self, from: data)
    #expect(book.entries.count == 3)
    let bb = try #require(book.memory(for: "tt0903747"))
    #expect(bb.audioLanguage == "en" && bb.subtitle == .language("de", forced: true, hearingImpaired: false))
    #expect(bb.subtitleOffset == -0.5 && bb.audioCommentary == nil && bb.audioVisualImpaired == nil)
    #expect(book.memory(for: "tmdb:1396")?.subtitle == .off)
    #expect(book.memory(for: "tt1160419")?.audioLanguage == "de")
    // Alte Einträge ohne Merker schreiben genau die alten Schlüssel.
    let reencoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(book)) as! [String: Any]
    let entry = try #require((reencoded["entries"] as? [String: Any])?["tt1160419"] as? [String: Any])
    #expect(Set(entry.keys) == ["audioLanguage", "updated"])
    // Neue Merker: ältere Builds ignorieren sie und lesen den Rest.
    var nb = book
    nb.update("tt0903747", now: Date(timeIntervalSince1970: 1_000_000_000)) {
        $0.apply(.audio(AudioTrackInfo(id: 1, language: "eng", isCommentary: true)))
    }
    let out = try JSONEncoder().encode(nb)
    let old = try JSONDecoder().decode(OldTrackMemoryBook.self, from: out)
    let oe = try #require(old.entries["tt0903747"])
    #expect(oe.audioLanguage == "en" && oe.subtitle == .language("de", forced: true, hearingImpaired: false))
    #expect(oe.subtitleOffset == -0.5)
    let back = try JSONDecoder().decode(TrackMemoryBook.self, from: out)
    #expect(back == nb && back.entries["tt0903747"]?.audioCommentary == true)
    // Kaputter Merker kippt den Eintrag nicht.
    let bad = try JSONDecoder().decode(TrackMemory.self,
        from: Data(#"{"audioLanguage":"de","audioCommentary":"ja","audioVisualImpaired":3}"#.utf8))
    #expect(bad.audioLanguage == "de" && bad.audioCommentary == nil && bad.audioVisualImpaired == nil)
}
