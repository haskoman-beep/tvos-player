import Foundation
import Testing
@testable import PlayerCore

private let show = MetaPreview(id: "tt100", type: "series", name: "Serie")
private let eps = [EpisodeRef(season: 1, episode: 1), EpisodeRef(season: 1, episode: 2), EpisodeRef(season: 2, episode: 1)]

@Test func nextOpenEpisodeWithoutProgressStartsAtFirst() {
    let b = ProgressBook()
    #expect(b.nextOpenEpisode(seriesID: "tt100", in: eps) == EpisodeRef(season: 1, episode: 1))
    #expect(b.nextOpenEpisode(seriesID: "tt100", in: []) == EpisodeRef(season: 1, episode: 1))
}

@Test func nextOpenEpisodeResumesStartedEpisode() {
    var b = ProgressBook()
    b.record(id: "tt100:1:2", item: show, season: 1, episode: 2, position: 600, duration: 2400)
    #expect(b.nextOpenEpisode(seriesID: "tt100", in: eps) == EpisodeRef(season: 1, episode: 2))
}

@Test func nextOpenEpisodeAfterWatchedGoesOnAcrossSeasons() {
    var b = ProgressBook()
    b.record(id: "tt100:1:2", item: show, season: 1, episode: 2, position: 2390, duration: 2400)
    #expect(b.nextOpenEpisode(seriesID: "tt100", in: eps) == EpisodeRef(season: 2, episode: 1))
}

@Test func nextOpenEpisodeAfterLastStartsOver() {
    var b = ProgressBook()
    b.record(id: "tt100:2:1", item: show, season: 2, episode: 1, position: 2390, duration: 2400)
    #expect(b.nextOpenEpisode(seriesID: "tt100", in: eps) == EpisodeRef(season: 1, episode: 1))
}

@Test func nextOpenEpisodeUsesNewestEntry() {
    var b = ProgressBook()
    let t = Date(timeIntervalSince1970: 1_000_000)
    b.record(id: "tt100:1:1", item: show, season: 1, episode: 1, position: 2390, duration: 2400, now: t)
    b.recordNextUp(id: "tt100:1:2", item: show, season: 1, episode: 2, now: t + 10)
    #expect(b.nextOpenEpisode(seriesID: "tt100", in: eps) == EpisodeRef(season: 1, episode: 2))
}
