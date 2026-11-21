import Foundation
import Testing
@testable import PlayerCore

/// #expect erlaubt keine verändernden Aufrufe im Ausdruck: Wert erst ausrechnen.
private func ok(_ b: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(b, sourceLocation: sourceLocation)
}

// MARK: Spulen über die Touchfläche

@Test func scrubSecondsPerPointAndAcceleration() {
    // 2 h Film: 7200 s / 4800 Punkte = 1,5 s je Punkt; kurzer Clip: Untergrenze 0,25 s.
    #expect(ScrubPlanner.secondsPerPoint(duration: 7200) == 1.5)
    #expect(ScrubPlanner.secondsPerPoint(duration: 60) == ScrubPlanner.minSecondsPerPoint)
    #expect(ScrubPlanner.secondsPerPoint(duration: .nan) == ScrubPlanner.minSecondsPerPoint)
    #expect(ScrubPlanner.acceleration(velocity: 100) == 1)
    #expect(ScrubPlanner.acceleration(velocity: -100_000) == ScrubPlanner.maxAcceleration)
    let mid = ScrubPlanner.acceleration(velocity: ScrubPlanner.accelerationStart + ScrubPlanner.accelerationSpan / 2)
    #expect(mid > 1 && mid < ScrubPlanner.maxAcceleration)
}

@Test func scrubPanNeedsThresholdThenMoves() {
    var p = ScrubPlanner()
    // Kleiner Weg: noch kein Spulen.
    ok(!p.pan(deltaX: 20, velocityX: 100, position: 1000, duration: 7200, now: 0))
    #expect(!p.isActive)
    // Schwelle überschritten: Spulen beginnt ab der Position, der ganze Weg zählt.
    ok(p.pan(deltaX: 30, velocityX: 100, position: 1000, duration: 7200, now: 0.1))
    #expect(p.isActive && p.origin == 1000)
    #expect(p.target == 1000 + 50 * 1.5)
    p.pan(deltaX: -100, velocityX: 100, position: 1000, duration: 7200, now: 0.2)
    #expect(p.target == 1000 + 50 * 1.5 - 150)
    ok(p.confirm() == 925)
    #expect(!p.isActive)
}

@Test func scrubClampsToFileAndSnaps() {
    var p = ScrubPlanner()
    p.pan(deltaX: -5000, velocityX: 0, position: 10, duration: 7200, now: 0)
    #expect(p.target == 0)
    p.pan(deltaX: 100_000, velocityX: 0, position: 10, duration: 7200, now: 0.1)
    #expect(p.target == 7200 - ScrubPlanner.endGuard)
    #expect(ScrubPlanner.snap(301, edges: [300, 400]) == 300)
    #expect(ScrubPlanner.snap(310, edges: [300, 400]) == 310)
    var q = ScrubPlanner()
    q.snapEdges = [300]
    q.pan(deltaX: 40, velocityX: 0, position: 239.5, duration: 7200, now: 0)   // 239,5 + 60 = 299,5 → 300
    #expect(q.target == 300)
}

@Test func scrubConfirmWithoutMoveAndCancel() {
    var p = ScrubPlanner()
    ok(p.confirm() == nil)
    ok(!p.cancel())
    p.pan(deltaX: 50, velocityX: 0, position: 100, duration: 7200, now: 0)
    p.pan(deltaX: -50, velocityX: 0, position: 100, duration: 7200, now: 0.1)
    #expect(p.isActive)
    ok(p.confirm() == nil)   // zurück an der Ausgangsstelle: kein Sprung
    p.pan(deltaX: 50, velocityX: 0, position: 100, duration: 7200, now: 1)
    ok(p.cancel())
    #expect(!p.isActive)
}

@Test func scrubMoveSuppressionIdleAndNudge() {
    var p = ScrubPlanner()
    p.pan(deltaX: 60, velocityX: 0, position: 100, duration: 7200, now: 5)
    #expect(p.suppressesMove(now: 5.2))
    #expect(!p.suppressesMove(now: 5.5))
    ok(p.nudge(10, now: 6))
    #expect(p.target == 100 + 90 + 10)
    #expect(!p.idleExpired(now: 15))
    #expect(p.idleExpired(now: 16))
    var idle = ScrubPlanner()
    ok(!idle.nudge(10, now: 0))
}

@Test func scrubWheelNeedsDwellOnRingAndTurnsClockwiseForward() {
    var p = ScrubPlanner()
    // Mitte: kein Drehrad.
    ok(!p.touch(x: 0.1, y: 0.1, position: 500, duration: 7200, now: 0))
    // Auf dem Ring (oben), aber noch nicht lange genug.
    p.touch(x: 0, y: 0.9, position: 500, duration: 7200, now: 1)
    #expect(!p.wheelOn)
    p.touch(x: 0, y: 0.9, position: 500, duration: 7200, now: 1.2)
    #expect(p.wheelOn && !p.isActive)   // ruhender Finger am Rand (z. B. vor einem ◀/▶-Klick) spult nicht
    // Viertel Umdrehung im Uhrzeigersinn (oben → rechts) = +6 s.
    ok(p.touch(x: 0.9, y: 0, position: 500, duration: 7200, now: 1.3))
    #expect(abs(p.target - 506) < 0.001)
    // Über die ±π-Grenze zurück (gegen den Uhrzeigersinn): rechts → oben → links → unten.
    p.touch(x: 0, y: 0.9, position: 500, duration: 7200, now: 1.4)
    p.touch(x: -0.9, y: 0, position: 500, duration: 7200, now: 1.5)
    p.touch(x: 0, y: -0.9, position: 500, duration: 7200, now: 1.6)
    #expect(abs(p.target - (506 - 18)) < 0.001)
    // Während das Drehrad zählt, ignoriert das Spulen Wischbewegungen.
    ok(!p.pan(deltaX: 500, velocityX: 0, position: 500, duration: 7200, now: 1.7))
    p.touchEnded()
    #expect(!p.wheelOn && p.isActive)
}

@Test func scrubWheelDwellRestartsWhenFingerMoves() {
    var p = ScrubPlanner()
    p.touch(x: 0, y: 0.9, position: 0, duration: 600, now: 0)
    p.touch(x: 0.9, y: 0, position: 0, duration: 600, now: 0.1)   // schnell über den Ring gewischt
    p.touch(x: 0.9, y: 0, position: 0, duration: 600, now: 0.2)
    #expect(!p.wheelOn)
    p.touch(x: 0.9, y: 0.05, position: 0, duration: 600, now: 0.3)
    #expect(p.wheelOn)
    // Kleine Drehung unter der Startschwelle: noch kein Spulen.
    ok(!p.touch(x: 0.9, y: 0.3, position: 0, duration: 600, now: 0.4))
    #expect(!p.isActive)
}

@Test func scrubPreviewCacheGridAndCapacity() {
    var c = ScrubPreviewCache<String>(capacity: 2)
    #expect(ScrubPreviewCache<String>.key(3.9) == 1)
    #expect(ScrubPreviewCache<String>.key(-1) == 0)
    c.store("a", at: 0)
    c.store("b", at: 2.5)
    ok(c.value(at: 1.9) == "a")       // gleiches Rasterfeld, „a“ wird zuletzt genutzt
    c.store("c", at: 10)                   // „b“ ist das älteste
    ok(c.value(at: 2) == nil)
    ok(c.value(at: 0) == "a" && c.count == 2)
    let g = c.generation
    c.reset()
    #expect(c.count == 0 && c.generation == g + 1)
}

// MARK: Ton-Formung

@Test func audioShapingDefaultsAreInactive() throws {
    let d = AudioShapingSettings()
    #expect(!d.shapesAudio && d.audioDelaySeconds == 0 && d.bridge == .surroundCompat && d.logText == "aus")
    // Alte Profile ohne Feld und Teilfelder laden mit Standard.
    let old = try JSONDecoder().decode(AudioShapingSettings.self, from: Data(#"{"nightMode":true,"bridge":"neu"}"#.utf8))
    #expect(old.nightMode && old.bridge == .surroundCompat && old.dialogueBoostDB == 0)
    let p = try JSONDecoder().decode(Profile.self, from: Data(#"{"id":"\#(UUID().uuidString)","name":"x"}"#.utf8))
    #expect(p.audioShaping == AudioShapingSettings())
}

@Test func audioShapingClampsValues() {
    let s = AudioShapingSettings(dialogueBoostDB: 40, loudnessTargetLUFS: -5, audioDelayMs: 9000)
    #expect(s.dialogueGain == 12)
    #expect(s.loudnessTarget == nil)
    #expect(s.audioDelaySeconds == 2)
    #expect(AudioShapingSettings(audioDelayMs: -250).audioDelaySeconds == -0.25)
    // Versatz allein formt nicht (Durchreichen bleibt).
    #expect(!AudioShapingSettings(audioDelayMs: 100).shapesAudio)
    #expect(AudioShapingSettings(loudnessTargetLUFS: -24).shapesAudio)
    #expect(AudioShapingSettings(nightMode: true, dialogueBoostDB: 3).logText == "Nacht, Dialog +3 dB")
}

@Test func audioOutputEARCAndSafeStereo() {
    var s = AudioShapingSettings()
    #expect(!s.hasEARCReceiver && s.maxChannels == nil)
    s.hasEARCReceiver = true
    #expect(s.bridge == .lossless && !s.shapesAudio)   // eARC ändert nur die Brücke, kein Dekodieren
    s.hasEARCReceiver = false
    #expect(s.bridge == .surroundCompat)
    let st = AudioShapingSettings(safeStereo: true)
    #expect(st.maxChannels == 2 && st.shapesAudio && st.logText == "Stereo (sicher)")
}

@Test func displayModeDefaultsAndDecoding() throws {
    let d = DisplayModeSettings()
    #expect(!d.panelPresentsDolbyVision && d.foldsDolbyVisionFEL && d.keepModeBetweenEpisodes && d.logText == "Standard")
    let old = try JSONDecoder().decode(DisplayModeSettings.self, from: Data(#"{"panelPresentsDolbyVision":true}"#.utf8))
    #expect(old.panelPresentsDolbyVision && old.foldsDolbyVisionFEL && old.keepModeBetweenEpisodes)
    let p = try JSONDecoder().decode(Profile.self, from: Data(#"{"id":"\#(UUID().uuidString)","name":"x"}"#.utf8))
    #expect(p.displayMode == DisplayModeSettings())
}

// MARK: Intro-Marken: Plattencache, Staffel-Schätzung, Zeitleiste

private func seg(_ k: SkipSegment.Kind, _ s: Double, _ e: Double) -> SkipSegment {
    SkipSegment(kind: k, start: s, end: e, source: .introDB)
}

@Test func skipStoreKeysAgeAndNeighbors() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    var st = SkipSegmentStore()
    let e1 = IntroDBQuery(imdb: "tt1", season: 1, episode: 1)
    let e2 = IntroDBQuery(imdb: "tt1:1:2", season: 1, episode: 2)
    #expect(SkipSegmentStore.key(e2) == "tt1|1|2")
    #expect(SkipSegmentStore.key(IntroDBQuery(imdb: "tt9")) == "tt9|m")
    st.store([], for: e1, now: now)
    #expect(st.entries.isEmpty)                      // leere Antwort wird nicht gemerkt
    st.store([seg(.intro, 60, 90)], for: e1, now: now)
    st.store([seg(.intro, 62, 92)], for: e2, now: now)
    ok(st.noteDuration(2700, for: e1))
    ok(!st.noteDuration(2700.4, for: e1))
    ok(!st.noteDuration(2700, for: IntroDBQuery(imdb: "tt1", season: 1, episode: 5)))
    st.store([seg(.intro, 61, 91)], for: e1, now: now)   // neue Antwort behält die Laufzeit
    #expect(st.entry(e1, now: now)?.duration == 2700)
    #expect(st.seasonNeighbors(of: IntroDBQuery(imdb: "tt1", season: 1, episode: 3), now: now).count == 2)
    #expect(st.seasonNeighbors(of: e1, now: now).count == 1)
    #expect(st.entry(e1, now: now.addingTimeInterval(SkipSegmentStore.maxAge + 1)) == nil)
    #expect(SkipSegmentStore.neighborEpisodes(of: 1) == [2, 3, 4, 5])
    #expect(SkipSegmentStore.neighborEpisodes(of: 5) == [4, 6, 3, 7])
}

@Test func skipStoreRoundTripsThroughBlobStorage() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skipstore-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let storage = FileBlobStorage(directory: dir)
    #expect(SkipSegmentStore.load(from: storage).entries.isEmpty)
    var st = SkipSegmentStore()
    st.store([seg(.intro, 10, 40), seg(.credits, 2500, 2600)], for: IntroDBQuery(imdb: "tt5", season: 2, episode: 3),
             now: Date(timeIntervalSince1970: 1_000_000))
    try st.save(to: storage)
    #expect(SkipSegmentStore.load(from: storage) == st)
}

@Test func skipStoreKeepsNewestEntries() {
    var st = SkipSegmentStore()
    let base = Date(timeIntervalSince1970: 2_000_000)
    for i in 0..<(SkipSegmentStore.maxEntries + 5) {
        st.store([seg(.intro, 1, 30)], for: IntroDBQuery(imdb: "tt\(i)"), now: base.addingTimeInterval(Double(i)))
    }
    #expect(st.entries.count == SkipSegmentStore.maxEntries)
    #expect(st.entries["tt0|m"] == nil)
    #expect(st.entries["tt\(SkipSegmentStore.maxEntries + 4)|m"] != nil)
}

@Test func seasonEstimateMediansAndSpread() {
    let t = Date()
    let n = [SkipSegmentStore.Entry(segments: [seg(.intro, 60, 90), seg(.credits, 2600, 2690)], duration: 2700, savedAt: t),
             SkipSegmentStore.Entry(segments: [seg(.intro, 70, 100), seg(.credits, 2410, 2500)], duration: 2500, savedAt: t),
             SkipSegmentStore.Entry(segments: [seg(.intro, 64, 94)], duration: nil, savedAt: t)]
    let est = SeasonSkipEstimate.estimate(from: n, duration: 2800)
    #expect(est == [SkipSegment(kind: .intro, start: 64, end: 94, source: .seasonEstimate),
                    // Abstand zum Ende: 100 und 90 → Median 95; Ende = Dateiende.
                    SkipSegment(kind: .credits, start: 2705, end: 2800, source: .seasonEstimate)])
    // Nur eine Folge: keine Schätzung.
    #expect(SeasonSkipEstimate.estimate(from: [n[0]], duration: 2800).isEmpty)
    // Intro wandert stark: keine Schätzung.
    let spread = [SkipSegmentStore.Entry(segments: [seg(.intro, 0, 30)], savedAt: t),
                  SkipSegmentStore.Entry(segments: [seg(.intro, 300, 330)], savedAt: t)]
    #expect(SeasonSkipEstimate.estimate(from: spread, duration: 2800).isEmpty)
    // Ohne Laufzeit kein Abspann, Intro trotzdem.
    #expect(SeasonSkipEstimate.estimate(from: n, duration: 0).map(\.kind) == [.intro])
}

@Test func seasonEstimateLosesAgainstRealMarks() {
    let est = [SkipSegment(kind: .intro, start: 64, end: 94, source: .seasonEstimate)]
    let real = [seg(.intro, 120, 150)]
    let merged = SkipSegments.merge(chapters: [], introDB: real + est, duration: 2800)
    #expect(merged == real)
}

@Test func timelineMarksAndSnapEdges() {
    let s = [seg(.intro, 60, 90), seg(.credits, 2700, 2900)]
    #expect(SkipSegments.timelineMarks(s, duration: 3000)
            == [TimelineMark(kind: .intro, from: 0.02, to: 0.03), TimelineMark(kind: .credits, from: 0.9, to: 2900.0 / 3000)])
    #expect(SkipSegments.timelineMarks(s, duration: 0).isEmpty)
    #expect(SkipSegments.timelineMarks([seg(.credits, 3100, 3200)], duration: 3000).isEmpty)
    #expect(SkipSegments.snapEdges(s) == [60, 90, 2700, 2900])
}

// MARK: Ausstieg nach Moduswechsel

@Test func modeSwitchExitClosesWithoutSwitch() {
    var e = ModeSwitchExit(stoppedAt: 10)
    ok(e.observe(switching: false, now: 10.1) == .wait)
    ok(e.observe(switching: false, now: 10.5) == .close(reason: "kein Moduswechsel"))
}

@Test func modeSwitchExitWaitsForSwitchAndSettle() {
    var e = ModeSwitchExit(stoppedAt: 0)
    ok(e.observe(switching: true, now: 0.2) == .wait)
    ok(e.observe(switching: true, now: 2) == .wait)
    ok(e.observe(switching: false, now: 2.1) == .wait)
    ok(e.observe(switching: false, now: 2.3) == .wait)
    ok(e.observe(switching: false, now: 2.5) == .close(reason: "Moduswechsel fertig"))
}

@Test func modeSwitchExitHasHardLimit() {
    var e = ModeSwitchExit(stoppedAt: 0)
    ok(e.observe(switching: true, now: 5.9) == .wait)
    ok(e.observe(switching: true, now: 6) == .close(reason: "Zeitgrenze 6 s"))
}
