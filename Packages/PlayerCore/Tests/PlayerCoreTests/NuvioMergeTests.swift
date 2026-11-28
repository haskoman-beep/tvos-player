import Foundation
import Testing
@testable import PlayerCore

// Nuvio account sync, T5: merge and delete rules for pulled account rows. Invented values only.

private let t0 = Date(timeIntervalSince1970: 1_750_000_000)
private let film = MetaPreview(id: "tt0137523", type: "movie", name: "Film", poster: "https://example.org/p.jpg")
private let show = MetaPreview(id: "tt0903747", type: "series", name: "Serie", poster: "https://example.org/s.jpg")

private func pulled(_ id: String = "tt0137523", item: MetaPreview? = nil, season: Int? = nil, episode: Int? = nil,
                    position: Double = 1800, duration: Double = 6000, at: Date, watched: Bool = false) -> NuvioProgressEntry {
    let m = item ?? MetaPreview(id: id, type: "movie", name: "")
    return NuvioProgressEntry(id: id, item: m, season: season, episode: episode, position: position, duration: duration,
                              updated: at, watched: watched)
}

private func bookWithFilm(position: Double = 600, at: Date = t0) -> ProgressBook {
    var b = ProgressBook()
    b.record(id: film.id, item: film, position: position, duration: 6000, now: at)
    return b
}

// MARK: Merge

@Test func nuvioRemoteNewerReplacesPositionAndKeepsLocalTitleArtAndSource() throws {
    var b = bookWithFilm()
    b.rememberSource(StreamItem(name: "Quelle", title: "file.mkv", url: "https://example.org/v.mkv"), addon: "A",
                     for: film.id, now: t0)
    let changed = b.merge(nuvio: [pulled(position: 2400, duration: 7200, at: t0.addingTimeInterval(60))])
    #expect(changed == 1)
    let e = try #require(b.entries[film.id])
    #expect(e.position == 2400 && e.duration == 7200 && e.updated == t0.addingTimeInterval(60) && !e.finished)
    #expect(e.item.name == "Film" && e.item.poster == film.poster)
    #expect(b.lastSource(for: film.id)?.addon == "A")
}

@Test func nuvioLocalNewerOrEqualStays() {
    var b = bookWithFilm()
    let before = b
    #expect(b.merge(nuvio: [pulled(position: 4000, at: t0)]) == 0)
    #expect(b.merge(nuvio: [pulled(position: 4000, at: t0.addingTimeInterval(-1))]) == 0)
    #expect(b == before)
}

@Test func nuvioNewTitleIsInsertedAndContinues() throws {
    var b = ProgressBook()
    let named = MetaPreview(id: "tt0137523", type: "movie", name: "Film")
    #expect(b.merge(nuvio: [pulled(item: named, at: t0)]) == 1)
    #expect(b.continueWatching().map(\.id) == ["tt0137523"])
    #expect(b.resumePosition(for: "tt0137523") == 1800)
}

@Test func nuvioNinetyFivePercentIsFinished() throws {
    var b = ProgressBook()
    b.merge(nuvio: [pulled(position: 5700, duration: 6000, at: t0)])
    let e = try #require(b.entries[film.id])
    #expect(e.finished && e.position == 0)
    #expect(b.continueWatching().isEmpty)
    #expect(b.history().map(\.id) == [film.id])
}

@Test func nuvioWatchedItemWithoutProgressIsFinishedInHistory() throws {
    var b = ProgressBook()
    b.merge(nuvio: [pulled(position: 0, duration: 0, at: t0, watched: true)])
    #expect(b.entries[film.id]?.finished == true)
    #expect(b.history().map(\.id) == [film.id])
    #expect(b.continueWatching().isEmpty)
}

@Test func nuvioEpisodeFeedsNextOpenEpisode() {
    var b = ProgressBook()
    let eps = [EpisodeRef(season: 1, episode: 1), EpisodeRef(season: 1, episode: 2), EpisodeRef(season: 1, episode: 3)]
    b.merge(nuvio: [pulled("tt0903747:1:2", item: show, season: 1, episode: 2, position: 900, duration: 3000, at: t0)])
    #expect(b.nextOpenEpisode(seriesID: show.id, in: eps) == EpisodeRef(season: 1, episode: 2))
    b.merge(nuvio: [pulled("tt0903747:1:2", item: show, season: 1, episode: 2, position: 0, duration: 0,
                           at: t0.addingTimeInterval(100), watched: true)])
    #expect(b.nextOpenEpisode(seriesID: show.id, in: eps) == EpisodeRef(season: 1, episode: 3))
}

@Test func nuvioMergingTwiceChangesNothingTheSecondTime() {
    var b = bookWithFilm()
    let input = [pulled(position: 3000, at: t0.addingTimeInterval(10)),
                 pulled("tt0903747:1:1", item: show, season: 1, episode: 1, position: 700, duration: 3000, at: t0),
                 pulled("tt0000001", position: 0, duration: 0, at: t0, watched: true)]
    #expect(b.merge(nuvio: input) == 3)
    let once = b
    #expect(b.merge(nuvio: input) == 0)
    #expect(b == once)
}

@Test func nuvioShortRemoteSessionDoesNotReopenAWatchedTitle() {
    var b = ProgressBook()
    b.record(id: film.id, item: film, position: 5900, duration: 6000, now: t0)
    #expect(b.entries[film.id]?.finished == true)
    // 100 s is below both limits of `record` (120 s and 5 %): it stays watched.
    #expect(b.merge(nuvio: [pulled(position: 100, at: t0.addingTimeInterval(60))]) == 0)
    #expect(b.entries[film.id]?.finished == true)
    // A real rewatch reopens it.
    #expect(b.merge(nuvio: [pulled(position: 2000, at: t0.addingTimeInterval(120))]) == 1)
    #expect(b.entries[film.id]?.finished == false)
}

@Test func nuvioEpisodeBeforeTheSeriesMarkerStaysOut() {
    var b = ProgressBook()
    b.markWatched(item: show, series: true, now: t0)
    #expect(b.merge(nuvio: [pulled("tt0903747:1:1", item: show, season: 1, episode: 1, position: 700, duration: 3000,
                                   at: t0.addingTimeInterval(-10))]) == 0)
    #expect(b.continueWatching().isEmpty)
    // Newer episode progress replaces the marker, as with `record`.
    #expect(b.merge(nuvio: [pulled("tt0903747:1:1", item: show, season: 1, episode: 1, position: 700, duration: 3000,
                                   at: t0.addingTimeInterval(10))]) == 1)
    #expect(b.entries[show.id] == nil)
    #expect(b.continueWatching().map(\.id) == ["tt0903747:1:1"])
}

@Test func nuvioUnusableNumbersAreRepairedNotStored() throws {
    var b = ProgressBook()
    b.merge(nuvio: [pulled(position: .nan, duration: .infinity, at: t0)])
    let e = try #require(b.entries[film.id])
    #expect(e.position == 0 && e.duration == 0 && !e.finished)
}

@Test func nuvioMergeKeepsTheNextUpHintForAShortSession() throws {
    var b = ProgressBook()
    b.recordNextUp(id: "tt0903747:1:2", item: show, season: 1, episode: 2, now: t0)
    b.merge(nuvio: [pulled("tt0903747:1:2", item: show, season: 1, episode: 2, position: 30, duration: 3000,
                           at: t0.addingTimeInterval(5))])
    #expect(b.entries["tt0903747:1:2"]?.nextUp == true)
    #expect(b.continueWatching().map(\.id) == ["tt0903747:1:2"])
}

// MARK: Deletes

@Test func nuvioDeleteOfAnUnfinishedEntryRemovesIt() {
    var b = bookWithFilm()
    b.record(id: "tt0903747:1:1", item: show, season: 1, episode: 1, position: 700, duration: 3000, now: t0)
    b.record(id: "tt0903747:1:2", item: show, season: 1, episode: 2, position: 700, duration: 3000, now: t0)
    let n = b.applyNuvio(deletedProgress: [film.id, "tt0903747:1:1"], watchedRemoved: [], protected: [],
                         before: t0.addingTimeInterval(1))
    #expect(n == 2)
    #expect(b.entries[film.id] == nil && b.entries["tt0903747:1:1"] == nil)
    // Only the deleted episode goes, not the whole series.
    #expect(b.entries["tt0903747:1:2"] != nil)
}

@Test func nuvioDeleteOfAFinishedEntryChangesNothing() {
    var b = ProgressBook()
    b.record(id: film.id, item: film, position: 5900, duration: 6000, now: t0)
    let before = b
    #expect(b.applyNuvio(deletedProgress: [film.id], watchedRemoved: [], protected: [], before: t0.addingTimeInterval(1)) == 0)
    #expect(b == before)
}

@Test func nuvioDeleteOfAProtectedOrNewerEntryChangesNothing() {
    var b = bookWithFilm()
    let before = b
    #expect(b.applyNuvio(deletedProgress: [film.id], watchedRemoved: [], protected: [film.id],
                         before: t0.addingTimeInterval(1)) == 0)
    // Local play after the last pull: the local play wins.
    #expect(b.applyNuvio(deletedProgress: [film.id], watchedRemoved: [], protected: [], before: t0) == 0)
    #expect(b.applyNuvio(deletedProgress: [film.id], watchedRemoved: [], protected: [], before: t0.addingTimeInterval(-5)) == 0)
    #expect(b.applyNuvio(deletedProgress: ["tt404"], watchedRemoved: [], protected: [], before: t0.addingTimeInterval(1)) == 0)
    #expect(b == before)
}

@Test func nuvioWatchedRemovalUnwatchesUnderTheSameGuards() {
    var b = ProgressBook()
    b.record(id: film.id, item: film, position: 5900, duration: 6000, now: t0)
    b.record(id: "tt0903747:1:1", item: show, season: 1, episode: 1, position: 2900, duration: 3000, now: t0)
    b.record(id: "tt0903747:1:2", item: show, season: 1, episode: 2, position: 2900, duration: 3000, now: t0)
    #expect(b.applyNuvio(deletedProgress: [], watchedRemoved: [film.id], protected: [film.id], before: t0.addingTimeInterval(1)) == 0)
    #expect(b.applyNuvio(deletedProgress: [], watchedRemoved: [film.id], protected: [], before: t0) == 0)
    #expect(b.isWatched(film.id))
    #expect(b.applyNuvio(deletedProgress: [], watchedRemoved: [film.id, "tt0903747:1:1"], protected: [],
                         before: t0.addingTimeInterval(1)) == 2)
    #expect(!b.isWatched(film.id) && b.entries[film.id] == nil)
    #expect(b.entries["tt0903747:1:1"] == nil && b.isWatched("tt0903747:1:2"))
}

@Test func nuvioWatchedRemovalLeavesUnfinishedProgress() {
    var b = bookWithFilm()
    let before = b
    #expect(b.applyNuvio(deletedProgress: [], watchedRemoved: [film.id], protected: [], before: t0.addingTimeInterval(1)) == 0)
    #expect(b == before)
}
