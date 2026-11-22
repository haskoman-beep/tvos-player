import Foundation
import Testing
@testable import PlayerCore

// Wave P-a: skip action per segment type, countdown, credits rules and the card after a movie.

private func seg(_ k: SkipSegment.Kind, _ s: Double, _ e: Double, _ src: SkipSegment.Source = .introDB) -> SkipSegment {
    SkipSegment(kind: k, start: s, end: e, source: src)
}

// MARK: Settings

@Test func skipSettingsDefaultsKeepOldBehaviour() {
    let d = SkipSettings()
    #expect(d.intro == .button && d.recap == .button)
    #expect(d.credits == .off && d.preview == .off)
    #expect(d.postPlayCard)
    #expect(d.action(for: .postCredits) == .off)
    var s = d
    s.set(.auto, for: .postCredits)
    #expect(s == d)   // a scene after the credits has no setting
    s.set(.auto, for: .preview)
    #expect(s.preview == .auto)
    #expect(SkipSettings.configurableKinds == [.intro, .recap, .credits, .preview])
    #expect(SkipAction.allCases.map(\.label) == ["Aus", "Knopf", "Automatisch"])
}

@Test func skipSettingsDecodeLenient() throws {
    let s = try JSONDecoder().decode(SkipSettings.self, from: Data(#"{"intro":"auto","credits":"fancy"}"#.utf8))
    #expect(s.intro == .auto && s.credits == .off && s.recap == .button && s.postPlayCard)
    let round = try JSONDecoder().decode(SkipSettings.self, from: JSONEncoder().encode(s))
    #expect(round == s)
    // Old profiles without the field get the defaults.
    let old = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(Profile(name: "A")))
    #expect(old.skip == SkipSettings())
    var p = Profile(name: "B")
    p.skip.recap = .auto
    #expect(try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(p)).skip.recap == .auto)
}

// MARK: Preview kind

@Test func previewChapterAndIntroDB() {
    #expect(SkipSegments.kind(ofChapterTitle: "Preview") == .preview)
    #expect(SkipSegments.kind(ofChapterTitle: "Next Time") == .preview)
    #expect(SkipSegments.kind(ofChapterTitle: "Vorschau") == .preview)
    #expect(seg(.preview, 0, 10).buttonTitle == "Vorschau überspringen")
    #expect(seg(.credits, 0, 10).buttonTitle == "Abspann überspringen")
    #expect(seg(.postCredits, 0, 10).buttonTitle == nil)
    let json = #"{"preview":{"start_sec":2900,"end_sec":2930}}"#
    #expect(IntroDBClient.parse(Data(json.utf8)) == [seg(.preview, 2900, 2930)])
}

// MARK: Planner with settings

@Test func plannerHonoursActionPerKind() {
    let intro = seg(.intro, 60, 150), recap = seg(.recap, 0, 40), preview = seg(.preview, 2950, 2990)
    var p = SkipPlanner(segments: [recap, intro, preview])
    var s = SkipSettings()
    s.recap = .off
    let ctx = SkipContext(duration: 3000)
    let r1 = p.evaluate(at: 10, engineSeeking: false, playing: true, now: 0, settings: s, context: ctx)
    #expect(r1.prompt == nil)
    let r2 = p.evaluate(at: 70, engineSeeking: false, playing: true, now: 0, settings: s, context: ctx)
    #expect(r2.prompt == SkipPrompt(segment: intro))
    let r3 = p.evaluate(at: 2960, engineSeeking: false, playing: true, now: 0, settings: s, context: ctx)
    #expect(r3.prompt == nil)
    s.preview = .button
    let r4 = p.evaluate(at: 2960, engineSeeking: false, playing: true, now: 0, settings: s, context: ctx)
    #expect(r4.prompt?.segment == preview)
    // Old entry point keeps the defaults.
    #expect(p.prompt(at: 10, engineSeeking: false) == recap)
}

@Test func plannerCountdownRunsOnlyWhilePlayingThenSkipsOnce() {
    let intro = seg(.intro, 60, 150)
    var p = SkipPlanner(segments: [intro])
    let s = SkipSettings(intro: .auto), ctx = SkipContext(duration: 3000)
    var d = p.evaluate(at: 61, engineSeeking: false, playing: true, now: 100, settings: s, context: ctx)
    #expect(d.prompt?.countdown == 5 && d.prompt?.ringFraction == 1)
    d = p.evaluate(at: 63, engineSeeking: false, playing: true, now: 102, settings: s, context: ctx)
    #expect(d.prompt?.countdown == 3)
    // Paused: the ring stands still.
    d = p.evaluate(at: 63, engineSeeking: false, playing: false, now: 110, settings: s, context: ctx)
    #expect(d.prompt?.countdown == 3)
    d = p.evaluate(at: 66, engineSeeking: false, playing: true, now: 113, settings: s, context: ctx)
    #expect(d.prompt == nil && d.autoSkip == intro)
    let t150 = p.beginSkip(intro, duration: 3000, now: 113)
    #expect(t150 == 150)
    _ = p.evaluate(at: 150, engineSeeking: false, playing: true, now: 114, settings: s, context: ctx)
    p.observe(position: 150, engineSeeking: false, now: 114)
    p.observe(position: 160, engineSeeking: false, now: 115)
    // Rewound into the skipped intro: only the plain button, no second jump.
    p.observe(position: 70, engineSeeking: false, now: 120)
    d = p.evaluate(at: 70, engineSeeking: false, playing: true, now: 120, settings: s, context: ctx)
    #expect(d.prompt == SkipPrompt(segment: intro, countdown: nil) && d.autoSkip == nil)
}

@Test func plannerCancelCountdownKeepsButton() {
    let recap = seg(.recap, 0, 60)
    var p = SkipPlanner(segments: [recap])
    let s = SkipSettings(recap: .auto), ctx = SkipContext(duration: 3000)
    let none = p.cancelCountdown()
    #expect(!none)
    _ = p.evaluate(at: 1, engineSeeking: false, playing: true, now: 0, settings: s, context: ctx)
    let stopped = p.cancelCountdown()
    #expect(stopped)
    let d = p.evaluate(at: 30, engineSeeking: false, playing: true, now: 30, settings: s, context: ctx)
    #expect(d.prompt == SkipPrompt(segment: recap) && d.autoSkip == nil)
    // Menu dismisses the button.
    p.dismiss(recap)
    let r5 = p.evaluate(at: 31, engineSeeking: false, playing: true, now: 31, settings: s, context: ctx)
    #expect(r5.prompt == nil)
}

@Test func plannerCountdownResetsWhenSegmentLeftEarly() {
    let intro = seg(.intro, 60, 150)
    var p = SkipPlanner(segments: [intro])
    let s = SkipSettings(intro: .auto), ctx = SkipContext(duration: 3000)
    _ = p.evaluate(at: 61, engineSeeking: false, playing: true, now: 0, settings: s, context: ctx)
    _ = p.evaluate(at: 63, engineSeeking: false, playing: true, now: 2, settings: s, context: ctx)
    let r6 = p.evaluate(at: 20, engineSeeking: false, playing: true, now: 3, settings: s, context: ctx)
    #expect(r6.prompt == nil)
    #expect(p.countdown == nil)
    let d = p.evaluate(at: 61, engineSeeking: false, playing: true, now: 10, settings: s, context: ctx)
    #expect(d.prompt?.countdown == 5)
}

// MARK: Credits

@Test func creditsButtonOnlyWithoutCard() {
    let d = 3000.0, credits = seg(.credits, 2800, 2995)
    var p = SkipPlanner(segments: [credits])
    let s = SkipSettings(credits: .button)
    let r7 = p.evaluate(at: 2850, engineSeeking: false, playing: true, now: 0, settings: s, context: SkipContext(duration: d))
    #expect(r7.prompt?.segment == credits)
    // Next-episode card or movie card cover the credits: no button.
    let r8 = p.evaluate(at: 2850, engineSeeking: false, playing: true, now: 0, settings: s, context: SkipContext(upNextCard: true, duration: d))
    #expect(r8.prompt == nil)
    let r9 = p.evaluate(at: 2850, engineSeeking: false, playing: true, now: 0, settings: s, context: SkipContext(postPlayCard: true, duration: d))
    #expect(r9.prompt == nil)
    // Default (credits off): nothing.
    let r10 = p.evaluate(at: 2850, engineSeeking: false, playing: true, now: 0, settings: SkipSettings(), context: SkipContext(duration: d))
    #expect(r10.prompt == nil)
}

@Test func creditsWithSceneLandAtScene() {
    let d = 3000.0, credits = seg(.credits, 2700, 2850), post = seg(.postCredits, 2850, 2900)
    let list = [credits, post]
    #expect(SkipPolicy.sceneAfterCredits(list, duration: d) == 2850)
    #expect(SkipPolicy.target(for: credits, in: list, duration: d) == 2850)
    var p = SkipPlanner(segments: list)
    let t2850 = p.beginSkip(credits, duration: d, now: 0)
    #expect(t2850 == 2850)
    // The next-episode card waits for the scene, so the button may lead there.
    let s = SkipSettings(credits: .button)
    let r11 = p.evaluate(at: 2710, engineSeeking: false, playing: true, now: 20, settings: s, context: SkipContext(upNextCard: true, duration: d))
    #expect(r11.prompt == nil)   // still seeking
    var q = SkipPlanner(segments: list)
    let r12 = q.evaluate(at: 2710, engineSeeking: false, playing: true, now: 0, settings: s, context: SkipContext(upNextCard: true, duration: d))
    #expect(r12.prompt?.segment == credits)
}

@Test func creditsEndingEarlyMeanAScene() {
    let d = 3000.0
    // Credits from IntroDB end 60 s before the file end: content follows, never jump to the end.
    let credits = seg(.credits, 2700, 2940)
    #expect(SkipPolicy.sceneAfterCredits([credits], duration: d) == 2940)
    #expect(SkipPolicy.target(for: credits, in: [credits], duration: d) == 2940)
    #expect(SkipPolicy.sceneHintWindow([credits], duration: d) == 2700..<2940)
    // Up to the end (or 5 s before): no scene, the jump goes to the end.
    let full = seg(.credits, 2700, 2997)
    #expect(SkipPolicy.sceneAfterCredits([full], duration: d) == nil)
    #expect(SkipPolicy.target(for: full, in: [full], duration: d) == 2997)
    #expect(SkipPolicy.sceneHintWindow([full], duration: d) == nil)
    // A preview filling the rest is known content, not a scene.
    let preview = seg(.preview, 2941, 2998)
    #expect(SkipPolicy.sceneAfterCredits([credits, preview], duration: d) == nil)
    #expect(SkipSegments.upNextTime([credits, preview], duration: d) == 2700)
    #expect(SkipSegments.upNextTime([credits], duration: d) == nil)
    // Season estimates run to the end and never mark a scene.
    #expect(SkipPolicy.sceneAfterCredits([seg(.credits, 2700, 2900, .seasonEstimate)], duration: d) == nil)
    // Credits before 60 % are no end credits.
    #expect(SkipPolicy.endCredits([seg(.credits, 100, 200)], duration: d) == nil)
    #expect(SkipPolicy.target(for: seg(.credits, 100, 200), in: [seg(.credits, 100, 200)], duration: d) == 200)
}

@Test func postPlayWindowStopsBeforeScene() {
    let d = 7200.0
    #expect(SkipPolicy.postPlayWindow([seg(.credits, 6800, 7198)], duration: d) == 6800..<7200)
    #expect(SkipPolicy.postPlayWindow([seg(.credits, 6800, 7000), seg(.postCredits, 7000, 7100)], duration: d)
            == 6800..<7000)
    #expect(SkipPolicy.postPlayWindow([seg(.intro, 0, 60)], duration: d) == nil)
    #expect(SkipPolicy.postPlayWindow([seg(.credits, 6800, 7198)], duration: 0) == nil)
}

@Test func autoCreditsWithoutCardJumpsToScene() {
    let d = 3000.0, credits = seg(.credits, 2700, 2850), post = seg(.postCredits, 2850, 2900)
    var p = SkipPlanner(segments: [credits, post])
    let s = SkipSettings(credits: .auto), ctx = SkipContext(duration: d)
    _ = p.evaluate(at: 2701, engineSeeking: false, playing: true, now: 0, settings: s, context: ctx)
    let r = p.evaluate(at: 2706, engineSeeking: false, playing: true, now: 5, settings: s, context: ctx)
    #expect(r.autoSkip == credits)
    let t2850 = p.beginSkip(credits, duration: d, now: 5)
    #expect(t2850 == 2850)
    // The scene itself never gets a button.
    var q = SkipPlanner(segments: [credits, post])
    let r13 = q.evaluate(at: 2860, engineSeeking: false, playing: true, now: 0, settings: s, context: ctx)
    #expect(r13.prompt == nil)
}

@Test func postPlayPicksSkipSelfDoublesAndPosterless() {
    let a = MetaPreview(id: "tmdb:1", type: "movie", name: "A", poster: "p1")
    let b = MetaPreview(id: "tmdb:2", type: "movie", name: "B")
    let c = MetaPreview(id: "tt9", type: "movie", name: "Self", poster: "p")
    let d = MetaPreview(id: "tmdb:4", type: "movie", name: "D", poster: "p4")
    let e = MetaPreview(id: "tmdb:5", type: "movie", name: "E", poster: "p5")
    let f = MetaPreview(id: "tmdb:6", type: "movie", name: "F", poster: "p6")
    #expect(PostPlayPicks.choose([a, b, c, a, d, e, f], excluding: "tmdb:99", imdb: "tt9").map(\.id)
            == ["tmdb:1", "tmdb:4", "tmdb:5"])
    #expect(PostPlayPicks.choose([a, d], excluding: "tmdb:1", imdb: nil, limit: 2).map(\.id) == ["tmdb:4"])
    #expect(PostPlayPicks.choose([], excluding: "x", imdb: nil).isEmpty)
}
