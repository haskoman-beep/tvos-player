import Foundation
import Testing
@testable import PlayerCore

// Task 2.1 (W-B-1, S-13): recording progress merges into the existing entry instead of replacing it.

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private let movie = MetaPreview(id: "tt1", type: "movie", name: "Der Film", poster: "p-de", background: "b-de",
                                logo: "l-de", description: "Deutsch")
private let show = MetaPreview(id: "tt9", type: "series", name: "Die Serie", poster: "sp", logo: "sl")

@Test func reopeningFinishedTitleFor15sKeepsCheckmark() {
    var b = ProgressBook()
    b.record(id: "tt1", item: movie, position: 6000, duration: 6000, now: t0)
    #expect(b.isWatched("tt1"))
    b.record(id: "tt1", item: movie, position: 15, duration: 6000, now: t0.addingTimeInterval(60))
    #expect(b.isWatched("tt1"))
    #expect(b.history().map(\.id) == ["tt1"])
    #expect(b.continueWatching().isEmpty)
}

@Test func finishedTitleLosesCheckmarkOnlyAfterFivePercentAndTwoMinutes() {
    var b = ProgressBook()
    b.record(id: "tt1", item: movie, position: 6000, duration: 6000, now: t0)
    // 200 s is more than 120 s but less than 5 % of 6000 s (300 s): stays watched.
    b.record(id: "tt1", item: movie, position: 200, duration: 6000, now: t0.addingTimeInterval(60))
    #expect(b.isWatched("tt1"))
    // Short film: 100 s is more than 5 % of 1200 s but not more than 120 s: stays watched.
    b.record(id: "tt1", item: movie, position: 100, duration: 1200, now: t0.addingTimeInterval(120))
    #expect(b.isWatched("tt1"))
    // Both thresholds passed: a real rewatch, the entry is in progress again.
    b.record(id: "tt1", item: movie, position: 400, duration: 6000, now: t0.addingTimeInterval(180))
    #expect(!b.isWatched("tt1"))
    #expect(b.resumePosition(for: "tt1") == 400)
}

@Test func leavingNextEpisodeInFirstMinuteKeepsSeriesInContinueWatching() {
    var b = ProgressBook()
    b.record(id: "tt9:1:2", item: show, season: 1, episode: 2, position: 2400, duration: 2400, now: t0)
    b.recordNextUp(id: "tt9:1:3", item: show, season: 1, episode: 3, now: t0.addingTimeInterval(1))
    b.record(id: "tt9:1:3", item: show, season: 1, episode: 3, position: 40, duration: 2400, now: t0.addingTimeInterval(50))
    #expect(b.continueWatching().map(\.id) == ["tt9:1:3"])
    #expect(b.entries["tt9:1:3"]?.nextUp == true)
    // Still a hint up to 120 s; more than 120 s turns it into real progress.
    b.record(id: "tt9:1:3", item: show, season: 1, episode: 3, position: 120, duration: 2400, now: t0.addingTimeInterval(130))
    #expect(b.entries["tt9:1:3"]?.nextUp == true)
    b.record(id: "tt9:1:3", item: show, season: 1, episode: 3, position: 121, duration: 2400, now: t0.addingTimeInterval(140))
    #expect(b.entries["tt9:1:3"]?.nextUp == nil)
    #expect(b.continueWatching().map(\.id) == ["tt9:1:3"])
    #expect(b.resumePosition(for: "tt9:1:3") == 121)
}

@Test func finishingNextEpisodeClearsHint() {
    var b = ProgressBook()
    b.recordNextUp(id: "tt9:1:3", item: show, season: 1, episode: 3, now: t0)
    b.record(id: "tt9:1:3", item: show, season: 1, episode: 3, position: 2300, duration: 2400, now: t0.addingTimeInterval(10))
    #expect(b.isWatched("tt9:1:3"))
    #expect(b.entries["tt9:1:3"]?.nextUp == nil)
}

@Test func recordKeepsRemoteFractionTitleAndArtwork() {
    var b = ProgressBook()
    b.entries["tt1"] = WatchProgress(id: "tt1", item: movie, position: 0, duration: 0, updated: t0, remoteFraction: 0.4)
    let bare = MetaPreview(id: "tt1", type: "movie", name: "")
    b.record(WatchProgress(id: "tt1", item: bare, position: 10, duration: 6000), now: t0.addingTimeInterval(5))
    let e = try! #require(b.entries["tt1"])
    #expect(e.remoteFraction == 0.4)
    #expect(e.item == movie)
    #expect(e.position == 10 && e.duration == 6000 && e.updated == t0.addingTimeInterval(5))
    // A new entry that brings its own values wins.
    let other = MetaPreview(id: "tt1", type: "movie", name: "Neu", poster: "p2")
    b.record(WatchProgress(id: "tt1", item: other, position: 20, duration: 6000, remoteFraction: 0.5),
             now: t0.addingTimeInterval(10))
    #expect(b.entries["tt1"]?.item.name == "Neu" && b.entries["tt1"]?.item.poster == "p2")
    #expect(b.entries["tt1"]?.item.logo == "l-de")
    #expect(b.entries["tt1"]?.remoteFraction == 0.5)
}

@Test func remoteMergeKeepsLocalArtwork() {
    var b = ProgressBook()
    b.record(id: "tt1", item: movie, position: 2400, duration: 6000, now: t0)
    let remoteItem = MetaPreview(id: "tt1", type: "movie", name: "", poster: nil)
    b.merge(remote: [RemoteProgress(id: "tt1", item: remoteItem, fraction: 0.5, updated: t0.addingTimeInterval(1))])
    let e = try! #require(b.entries["tt1"])
    #expect(e.position == 3000 && e.updated == t0.addingTimeInterval(1))
    #expect(e.item == movie)
}

@Test func remoteMergeKeepsLocalTitleButFillsMissingArtwork() {
    var b = ProgressBook()
    let local = MetaPreview(id: "tt1", type: "movie", name: "Der Film")
    b.record(id: "tt1", item: local, position: 600, duration: 6000, now: t0)
    let remoteItem = MetaPreview(id: "tt1", type: "movie", name: "The Movie", poster: "remote-poster")
    b.merge(remote: [RemoteProgress(id: "tt1", item: remoteItem, fraction: 0.2, updated: t0.addingTimeInterval(1))])
    let e = try! #require(b.entries["tt1"])
    #expect(e.item.name == "Der Film")
    #expect(e.item.poster == "remote-poster")
    #expect(e.position == 1200)
}
