import Foundation
import Testing
@testable import PlayerCore

/// Antwort von api.introdb.app für eine Folge (Aufbau wie real abgerufen am 21.11.2026).
private let episodeJSON = #"""
{"imdb_id":"tt0903747","media_type":"tv","is_movie":false,"season":1,"episode":2,
 "intro":{"start_sec":314.5,"end_sec":331,"start_ms":314500,"end_ms":331000,"confidence":1,"submission_count":5},
 "recap":null,
 "outro":{"start_sec":2843,"end_sec":2901,"start_ms":2843000,"end_ms":2901000,"confidence":1,"submission_count":1},
 "post_credits":null,"no_intro":false,"no_recap":false,"no_outro":false}
"""#

// MARK: IntroDB

@Test func introDBURLForEpisodeAndMovie() {
    #expect(IntroDBClient.url(IntroDBQuery(imdb: "tt0903747", season: 1, episode: 2))?.absoluteString
            == "https://api.introdb.app/segments?imdb_id=tt0903747&season=1&episode=2")
    #expect(IntroDBClient.url(IntroDBQuery(imdb: "tt0133093"))?.absoluteString
            == "https://api.introdb.app/segments?imdb_id=tt0133093&is_movie=true")
    // Folgen-ID wird auf die Serien-ID gekürzt; Nicht-IMDb-IDs ergeben keine Adresse.
    #expect(IntroDBClient.url(IntroDBQuery(imdb: "tt0903747:1:2", season: 1, episode: 2))?.query
            == "imdb_id=tt0903747&season=1&episode=2")
    #expect(IntroDBClient.url(IntroDBQuery(imdb: "tmdb:1396", season: 1, episode: 1)) == nil)
    #expect(IntroDBClient.url(IntroDBQuery(imdb: "tt")) == nil)
    #expect(IntroDBQuery(imdb: "tt1", season: 1, episode: nil).isMovie)
}

@Test func introDBParseRealShape() {
    let list = IntroDBClient.parse(Data(episodeJSON.utf8))
    #expect(list == [SkipSegment(kind: .intro, start: 314.5, end: 331, source: .introDB),
                     SkipSegment(kind: .credits, start: 2843, end: 2901, source: .introDB)])
}

@Test func introDBParseTextTimesAndBadValues() {
    let json = #"""
    {"intro":{"start_sec":"1:05","end_sec":"01:35.5"},
     "recap":{"start_ms":"2000","end_ms":"40000"},
     "outro":{"start_sec":100,"end_sec":90},
     "post_credits":{"start_sec":"abc","end_sec":"1:99"}}
    """#
    let list = IntroDBClient.parse(Data(json.utf8))
    #expect(list.map(\.kind) == [.recap, .intro])
    #expect(list[0].start == 2 && list[0].end == 40)
    #expect(list[1].start == 65 && list[1].end == 95.5)
    #expect(IntroDBClient.seconds("1:02:03") == 3723)
    #expect(IntroDBClient.seconds("12.5") == 12.5)
    #expect(IntroDBClient.seconds("1:2:3:4") == nil)
    #expect(IntroDBClient.parse(Data("kein json".utf8)).isEmpty)
    #expect(IntroDBClient.parse(Data(#"{"intro":null}"#.utf8)).isEmpty)
}

@Test func introDBFetchAndErrors() async {
    let http = RecordingHTTP(episodeJSON)
    let list = await IntroDBClient(http: http).segments(IntroDBQuery(imdb: "tt0903747", season: 1, episode: 2))
    #expect(http.urls.count == 1 && list.count == 2)
    let none = await IntroDBClient(http: FakeHTTP(routes: [:])).segments(IntroDBQuery(imdb: "tt0903747", season: 1, episode: 2))
    #expect(none.isEmpty)
    let bad = await IntroDBClient(http: http).segments(IntroDBQuery(imdb: "kitsu:1"))
    #expect(bad.isEmpty && http.urls.count == 1)
}

// MARK: Kapitel

@Test func chapterTitlesMustBeTheKeyword() {
    #expect(SkipSegments.kind(ofChapterTitle: "Opening") == .intro)
    #expect(SkipSegments.kind(ofChapterTitle: "OP2") == .intro)
    #expect(SkipSegments.kind(ofChapterTitle: "Intro") == .intro)
    #expect(SkipSegments.kind(ofChapterTitle: "  Opening 2 ") == .intro)
    #expect(SkipSegments.kind(ofChapterTitle: "Previously on…") == .recap)
    #expect(SkipSegments.kind(ofChapterTitle: "Recap") == .recap)
    #expect(SkipSegments.kind(ofChapterTitle: "ED") == .credits)
    #expect(SkipSegments.kind(ofChapterTitle: "End Credits") == .credits)
    #expect(SkipSegments.kind(ofChapterTitle: "Abspann") == .credits)
    #expect(SkipSegments.kind(ofChapterTitle: "Post-Credits Scene") == .postCredits)
    // Handlungskapitel mit Stichwort im Satz zählen nicht.
    #expect(SkipSegments.kind(ofChapterTitle: "Introduction to the Case") == nil)
    #expect(SkipSegments.kind(ofChapterTitle: "Chapter 01") == nil)
    #expect(SkipSegments.kind(ofChapterTitle: "The Ending of Everything") == nil)
    #expect(SkipSegments.kind(ofChapterTitle: "") == nil)
}

@Test func chapterSegmentsLengthAndEnds() {
    let chapters = [
        ChapterMark(name: "Recap", start: 0, duration: 3),              // zu kurz
        ChapterMark(name: "Intro", start: 60, duration: 0),             // Ende = nächstes Kapitel
        ChapterMark(name: "Teil 1", start: 150, duration: 1200),
        ChapterMark(name: "Opening", start: 1400, duration: 60),        // zweites Intro: nur das erste zählt
        ChapterMark(name: "Credits", start: 2500, duration: 0),         // letztes: bis Dateiende
    ]
    let s = SkipSegments.fromChapters(chapters, duration: 2600)
    #expect(s == [SkipSegment(kind: .intro, start: 60, end: 150, source: .chapter),
                  SkipSegment(kind: .credits, start: 2500, end: 2600, source: .chapter)])
    // Länger als 240 s → kein Sprungkapitel.
    #expect(SkipSegments.fromChapters([ChapterMark(name: "Intro", start: 0, duration: 300)], duration: 2600).isEmpty)
}

@Test func mergeChaptersWinPerKind() {
    let ch = [SkipSegment(kind: .intro, start: 50, end: 120, source: .chapter)]
    let db = [SkipSegment(kind: .intro, start: 314, end: 331, source: .introDB),
              SkipSegment(kind: .recap, start: 0, end: 40, source: .introDB),
              SkipSegment(kind: .credits, start: 2843, end: 2950, source: .introDB),
              SkipSegment(kind: .postCredits, start: 4000, end: 4010, source: .introDB)]
    let m = SkipSegments.merge(chapters: ch, introDB: db, duration: 2900)
    #expect(m.map(\.kind) == [.recap, .intro, .credits])
    #expect(m[1].source == .chapter)
    #expect(m[2].end == 2900)   // ans Dateiende gekürzt; post_credits liegt außerhalb und fällt weg
}

@Test func upNextTimeFromCredits() {
    let d = 2900.0
    let credits = SkipSegment(kind: .credits, start: 2843, end: 2898, source: .introDB)
    #expect(SkipSegments.upNextTime([credits], duration: d) == 2843)
    // Vor 60 % der Laufzeit: kein Abspann.
    #expect(SkipSegments.upNextTime([SkipSegment(kind: .credits, start: 1000, end: 1060, source: .chapter)], duration: d) == nil)
    // Mehr als 5 s nach dem Abspann ohne bekannte Szene: Standard.
    #expect(SkipSegments.upNextTime([SkipSegment(kind: .credits, start: 2700, end: 2800, source: .chapter)], duration: d) == nil)
    // Szene nach dem Abspann: Karte nach deren Ende.
    let post = SkipSegment(kind: .postCredits, start: 2800, end: 2860, source: .introDB)
    #expect(SkipSegments.upNextTime([SkipSegment(kind: .credits, start: 2700, end: 2800, source: .chapter), post], duration: d) == 2860)
    // Szene reicht bis ans Ende: Standard.
    let postToEnd = SkipSegment(kind: .postCredits, start: 2800, end: 2899, source: .introDB)
    #expect(SkipSegments.upNextTime([SkipSegment(kind: .credits, start: 2700, end: 2800, source: .chapter), postToEnd], duration: d) == nil)
    #expect(SkipSegments.upNextTime([], duration: d) == nil)
    #expect(SkipSegments.upNextTime([credits], duration: 0) == nil)
}

// MARK: Planer

@Test func plannerPromptsInsideSegmentOnly() {
    let intro = SkipSegment(kind: .intro, start: 60, end: 150, source: .chapter)
    let credits = SkipSegment(kind: .credits, start: 2500, end: 2600, source: .chapter)
    let p = SkipPlanner(segments: [intro, credits])
    #expect(p.prompt(at: 59, engineSeeking: false) == nil)
    #expect(p.prompt(at: 60, engineSeeking: false) == intro)
    #expect(p.prompt(at: 148.5, engineSeeking: false) == intro)
    #expect(p.prompt(at: 149.5, engineSeeking: false) == nil)   // kurz vor Ende kein Knopf
    #expect(p.prompt(at: 2550, engineSeeking: false) == nil)    // Abspann: kein Knopf
    #expect(p.prompt(at: 100, engineSeeking: true) == nil)      // Engine springt/lädt
    #expect(intro.buttonTitle == "Intro überspringen")
    #expect(SkipSegment(kind: .recap, start: 0, end: 30, source: .introDB).buttonTitle == "Rückblick überspringen")
}

@Test func plannerDoesNotTrustPositionWhileSeeking() {
    let intro = SkipSegment(kind: .intro, start: 60, end: 150, source: .chapter)
    var p = SkipPlanner(segments: [intro])
    let target = p.beginSkip(intro, duration: 2600, now: 0)
    #expect(target == 150)
    // Alte Position noch im Bereich: kein Knopf während des Sprungs.
    p.observe(position: 80, engineSeeking: true, now: 1)
    #expect(p.prompt(at: 80, engineSeeking: false) == nil)
    p.observe(position: 80, engineSeeking: false, now: 2)
    #expect(p.seeking != nil)
    // Am Ziel angekommen: wieder normal.
    p.observe(position: 150.4, engineSeeking: false, now: 3)
    #expect(p.seeking == nil)
    #expect(p.prompt(at: 150.4, engineSeeking: false) == nil)
    // Zurückgespult in den Bereich: Knopf wieder da.
    #expect(p.prompt(at: 70, engineSeeking: false) == intro)
}

@Test func plannerSeekTimeoutAndClamp() {
    let tail = SkipSegment(kind: .recap, start: 10, end: 600, source: .introDB)
    var p = SkipPlanner(segments: [tail])
    #expect(p.beginSkip(tail, duration: 300, now: 100) == 295)   // nie hinter das Dateiende
    p.observe(position: 20, engineSeeking: false, now: 105)
    #expect(p.seeking != nil)
    p.observe(position: 20, engineSeeking: false, now: 108)
    #expect(p.seeking == nil)                                     // Wartezeit abgelaufen
}

@Test func plannerDismissUntilLeftSegment() {
    let intro = SkipSegment(kind: .intro, start: 60, end: 150, source: .chapter)
    var p = SkipPlanner(segments: [intro])
    p.dismiss(intro)
    p.observe(position: 90, engineSeeking: false, now: 0)
    #expect(p.prompt(at: 90, engineSeeking: false) == nil)
    p.observe(position: 200, engineSeeking: false, now: 1)        // Bereich verlassen
    #expect(p.prompt(at: 70, engineSeeking: false) == intro)
    // Neue Bereiche (z. B. Kapitel kommen dazu) behalten nur noch gültige Wegschicken.
    p.dismiss(intro)
    p.setSegments([SkipSegment(kind: .intro, start: 61, end: 150, source: .chapter)])
    #expect(p.prompt(at: 70, engineSeeking: false)?.start == 61)
}

// MARK: Lade-Schritte

@Test func startupStepLines() {
    #expect(StartupSteps.line(nil, dynamicRange: nil) == nil)
    #expect(StartupSteps.line(StartupStatus(step: .connecting, fraction: 0), dynamicRange: nil)
            == StartupStepLine(text: "Verbinde mit der Quelle", percent: nil))
    #expect(StartupSteps.line(StartupStatus(step: .analyzingStreams, fraction: 0.25), dynamicRange: nil)
            == StartupStepLine(text: "Spuren werden gelesen", percent: 25))
    #expect(StartupSteps.line(StartupStatus(step: .preparingDisplay, fraction: 0.375), dynamicRange: "dolbyVision")?.text
            == "Dolby Vision wird vorbereitet")
    #expect(StartupSteps.line(StartupStatus(step: .preparingDisplay, fraction: 0.375), dynamicRange: "sdr")?.text
            == "Bildmodus wird vorbereitet")
    #expect(StartupSteps.line(StartupStatus(step: .awaitingFirstFrame, fraction: 0.875), dynamicRange: nil)
            == StartupStepLine(text: "Puffern", percent: 88))
    #expect(StartupSteps.line(StartupStatus(step: .presenting, fraction: 1), dynamicRange: nil) == nil)
    // Bildmodus-Umschaltung zählt auch nach dem ersten Bild.
    #expect(StartupSteps.line(StartupStatus(step: .presenting, fraction: 1, awaitingDisplaySwitch: true), dynamicRange: "hdr10")?.text
            == "Fernseher schaltet auf HDR10")
    #expect(StartupSteps.line(StartupStatus(step: nil, fraction: 0.5), dynamicRange: nil) == nil)
    // Rohwerte entsprechen den Engine-Namen (StartupStage.rawValue).
    #expect(StartupStep(rawValue: "openingContainer") == .openingContainer)
    #expect(StartupStep.allCases.count == 9)
}
