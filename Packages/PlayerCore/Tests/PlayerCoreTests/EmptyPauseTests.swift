import Foundation
import Testing
@testable import PlayerCore

// Task 3.7 (A-A-4, A-A-6): the prefetch pauses only after several different titles without sources; the detail
// page's quality row only gains values once it is shown.

private let t0 = Date(timeIntervalSince1970: 1_000_000)

@Test func emptyPauseOneTitleWithoutSourcesDoesNotPause() {
    var p = EmptyPause()
    #expect(p.recordEmpty(id: "tt1", now: t0) == false)
    #expect(p.pausedAt == nil)
    #expect(p.isPaused(now: t0.addingTimeInterval(1)) == false)
}

@Test func emptyPauseSameTitleRepeatedCountsOnce() {
    var p = EmptyPause()
    for s in 0..<5 { p.recordEmpty(id: "tt1", now: t0.addingTimeInterval(Double(s))) }
    #expect(p.pausedAt == nil)
    p.recordEmpty(id: "tt2", now: t0.addingTimeInterval(6))
    #expect(p.isPaused(now: t0.addingTimeInterval(7)) == false)
}

@Test func emptyPauseThreeDifferentTitlesWithinWindowPause() {
    var p = EmptyPause()
    #expect(p.recordEmpty(id: "tt1", now: t0) == false)
    #expect(p.recordEmpty(id: "tt2", now: t0.addingTimeInterval(20)) == false)
    #expect(p.recordEmpty(id: "tt3", now: t0.addingTimeInterval(59)) == true)
    #expect(p.pausedAt == t0.addingTimeInterval(59))
    #expect(p.isPaused(now: t0.addingTimeInterval(60)))
    #expect(p.isPaused(now: t0.addingTimeInterval(59 + EmptyPause.defaultPause + 1)) == false)
}

@Test func emptyPauseTitlesOutsideWindowDoNotCount() {
    var p = EmptyPause()
    p.recordEmpty(id: "tt1", now: t0)
    p.recordEmpty(id: "tt2", now: t0.addingTimeInterval(30))
    // tt1 is 61 s old by now: only two titles in the last 60 s.
    #expect(p.recordEmpty(id: "tt3", now: t0.addingTimeInterval(61)) == false)
    #expect(p.pausedAt == nil)
    // Another title within 60 s of tt2 and tt3 reaches three.
    #expect(p.recordEmpty(id: "tt4", now: t0.addingTimeInterval(80)) == true)
}

@Test func emptyPauseHitEndsStreakAndPause() {
    var p = EmptyPause()
    p.recordEmpty(id: "tt1", now: t0)
    p.recordEmpty(id: "tt2", now: t0.addingTimeInterval(1))
    #expect(p.recordHit(now: t0.addingTimeInterval(1)) == false)   // no pause to lift
    // Not consecutive any more: the streak starts again.
    #expect(p.recordEmpty(id: "tt3", now: t0.addingTimeInterval(2)) == false)
    p.recordEmpty(id: "tt4", now: t0.addingTimeInterval(3))
    #expect(p.recordEmpty(id: "tt5", now: t0.addingTimeInterval(4)) == true)
    #expect(p.recordHit(now: t0.addingTimeInterval(5)) == true)
    #expect(p.isPaused(now: t0.addingTimeInterval(5)) == false)
    p.recordEmpty(id: "tt6", now: t0.addingTimeInterval(6))
    #expect(p.pausedAt == nil)
}

@Test func detailQualityAddingKeepsShownValuesAndFillsGaps() {
    let shown = DetailQuality(best: BestQuality(resolution: "1080p", hdr: "HDR10", channels: "5.1"),
                              audioFormat: nil, audioChannels: "5.1")
    let final = DetailQuality(best: BestQuality(resolution: "2160p", dolbyVision: true, hdr: "HDR10+", atmos: true,
                                                remux: true, channels: "7.1"),
                              audioFormat: "TrueHD", audioChannels: "7.1")
    let q = shown.adding(final)
    // Shown badges stay as they are (no jump): resolution, HDR kind.
    #expect(q.best.resolution == "1080p")
    #expect(q.best.hdr == "HDR10")
    #expect(q.best.dolbyVision == false)
    // Missing ones are added: Atmos, REMUX, the audio format with its own channels.
    #expect(q.best.atmos)
    #expect(q.best.remux)
    #expect(q.audioFormat == "TrueHD")
    #expect(q.audioChannels == "7.1")
    #expect(shown.adding(nil) == shown)
}

@Test func detailQualityAddingNeverDropsABadge() {
    let s = BadgeSettings()
    let shown = DetailQuality(best: BestQuality(resolution: "2160p", dolbyVision: true, atmos: true, remux: true),
                              audioFormat: "DD+", audioChannels: "5.1")
    // The final state is poorer (e.g. cached sources only): nothing that is shown goes away.
    let final = DetailQuality(best: BestQuality(resolution: "1080p"), audioFormat: nil, audioChannels: nil)
    let before = QualityBadges.detailRow(shown, settings: s).map(\.text)
    let after = QualityBadges.detailRow(shown.adding(final), settings: s).map(\.text)
    #expect(after == before)
    // Empty row first: the final state fills it.
    let none = DetailQuality(best: BestQuality(), audioFormat: nil, audioChannels: nil)
    #expect(QualityBadges.detailRow(none.adding(final), settings: s).map(\.text)
        == QualityBadges.detailRow(final, settings: s).map(\.text))
}

// Task 3.7 (A-A-17): the YouTube fallback has one overall deadline across visitor token and clients.

private final class SlowPoster: HTTPPosting, @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var calls: Int { lock.lock(); defer { lock.unlock() }; return n }
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> Data {
        lock.withLock { n += 1 }
        try await Task.sleep(nanoseconds: 5_000_000_000)   // a hanging YouTube (cancellable)
        return Data()
    }
}

private final class LogLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ s: String) { lock.lock(); lines.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return lines }
}

@Test func youtubeResolveGivesUpAtOverallDeadline() async {
    #expect(YouTubeResolver.overallDeadline == 8)
    let poster = SlowPoster(), log = LogLines()
    let start = ContinuousClock.now
    let s = await YouTubeResolver(poster: poster).resolve(videoID: "aqz-KE-bpKQ", deadline: 0.3) { log.add($0) }
    let waited = ContinuousClock.now - start
    #expect(s == nil)
    // Before: visitor token plus three clients one after another (here 4 × 5 s).
    #expect(waited < .seconds(3))
    #expect(log.all.contains { $0.contains("Gesamtfrist") })
}

@Test func youtubeResolveStopsAfterSecondClientWithMP4() async throws {
    let poster = ScriptedPoster([
        #"{"responseContext":{"visitorData":"V"}}"#,
        #"{"playabilityStatus":{"status":"OK"},"streamingData":{"formats":[{"mimeType":"video/mp4","height":720,"url":"https://media.example/v22"}]}}"#,
        #"{"playabilityStatus":{"status":"LOGIN_REQUIRED"}}"#,
        #"{"playabilityStatus":{"status":"OK"},"streamingData":{"formats":[{"mimeType":"video/mp4","height":360,"url":"https://media.example/v18"}]}}"#,
    ])
    let log = LogLines()
    let s = try #require(await YouTubeResolver(poster: poster).resolve(videoID: "aqz-KE-bpKQ") { log.add($0) })
    #expect(s.client == "visionos" && s.height == 720)
    #expect(poster.calls.count == 3)   // visitor token, visionOS, iOS – no third client
    // Every step names its duration.
    #expect(log.all.contains { $0.hasPrefix("Besucher-Token") && $0.contains(" ms") })
    #expect(log.all.contains { $0.hasPrefix("visionos:") && $0.contains(" ms") })
}
