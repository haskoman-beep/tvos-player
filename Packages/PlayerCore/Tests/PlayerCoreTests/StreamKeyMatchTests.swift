import Foundation
import Testing
@testable import PlayerCore

// Build 4 follow-up S3: when a source list is stored, every tile and row on screen tests whether it is theirs.
// `PrefetchTarget.matches` answers like comparing with `streamID(type:imdb:progress:)` of the latest progress,
// but searches the progress only when the stored ID can be the tile's key.

private func preview(_ id: String, _ type: String) -> MetaPreview { MetaPreview(id: id, type: type, name: id) }

private func episode(_ id: String, series: String, s: Int?, e: Int?, finished: Bool = false, at: TimeInterval) -> WatchProgress {
    WatchProgress(id: id, item: preview(series, "series"), season: s, episode: e, position: 600, duration: 2400,
                  updated: Date(timeIntervalSince1970: at), finished: finished)
}

private func book(_ entries: [WatchProgress]) -> ProgressBook {
    var b = ProgressBook()
    for e in entries { b.entries[e.id] = e }
    return b
}

@Test func movieTileMatchesItsIMDbID() {
    let b = ProgressBook()
    #expect(PrefetchTarget.matches("tt1", type: "movie", imdb: "tt1", itemID: "tt1", book: b))
    #expect(!PrefetchTarget.matches("tt2", type: "movie", imdb: "tt1", itemID: "tt1", book: b))
    #expect(!PrefetchTarget.matches("tt1:1:1", type: "movie", imdb: "tt1", itemID: "tt1", book: b))
    #expect(!PrefetchTarget.matches("tt1", type: "movie", imdb: nil, itemID: "tmdb:5", book: b))
    #expect(!PrefetchTarget.matches("tt1", type: "channel", imdb: "tt1", itemID: "tt1", book: b))
}

@Test func seriesTileMatchesStartedEpisodeOrFirstOne() {
    let started = book([episode("tt1:2:3", series: "tt1", s: 2, e: 3, at: 100)])
    #expect(PrefetchTarget.matches("tt1:2:3", type: "series", imdb: "tt1", itemID: "tt1", book: started))
    #expect(!PrefetchTarget.matches("tt1:1:1", type: "series", imdb: "tt1", itemID: "tt1", book: started))
    // Without progress: S1E1.
    #expect(PrefetchTarget.matches("tt1:1:1", type: "series", imdb: "tt1", itemID: "tt1", book: ProgressBook()))
    #expect(!PrefetchTarget.matches("tt1:2:3", type: "series", imdb: "tt1", itemID: "tt1", book: ProgressBook()))
    // Without IMDb ID only the started episode.
    #expect(PrefetchTarget.matches("tt1:2:3", type: "series", imdb: nil, itemID: "tt1", book: started))
    #expect(!PrefetchTarget.matches("tt1:1:1", type: "series", imdb: nil, itemID: "tt1", book: ProgressBook()))
    // Another series' episode never matches.
    let other = book([episode("tt9:1:4", series: "tt9", s: 1, e: 4, at: 100)])
    #expect(!PrefetchTarget.matches("tt9:1:4", type: "series", imdb: "tt1", itemID: "tt1", book: other))
}

/// Equal to comparing with `streamID(type:imdb:progress:)` of the latest entry, for every ID in play: older,
/// finished and marker entries, other series, films.
@Test func matchesEqualsStreamIDComparison() {
    let books: [ProgressBook] = [
        ProgressBook(),
        book([episode("tt1:1:2", series: "tt1", s: 1, e: 2, at: 100), episode("tt1:1:3", series: "tt1", s: 1, e: 3, at: 200)]),
        book([episode("tt1:1:2", series: "tt1", s: 1, e: 2, at: 300), episode("tt1:1:3", series: "tt1", s: 1, e: 3, finished: true, at: 400)]),
        book([episode("tt1:1:1", series: "tt1", s: 1, e: 1, at: 100)]),
        book([episode("tt1", series: "tt1", s: nil, e: nil, finished: true, at: 500), episode("tt1:2:1", series: "tt1", s: 2, e: 1, at: 100)]),
        book([episode("tt9:3:1", series: "tt9", s: 3, e: 1, at: 100), episode("tt1:4:4", series: "tt1", s: 4, e: 4, at: 50)]),
    ]
    let ids = ["tt1", "tt1:1:1", "tt1:1:2", "tt1:1:3", "tt1:2:1", "tt1:4:4", "tt9", "tt9:3:1", "tt9:1:1", "x"]
    let tiles: [(type: String, imdb: String?, item: String)] = [
        ("series", "tt1", "tt1"), ("series", nil, "tt1"), ("series", "tt9", "tt9"), ("movie", "tt1", "tt1"),
        ("movie", nil, "tmdb:1"), ("series", "tt1", "tmdb:7"),
    ]
    for b in books {
        for t in tiles {
            let key = PrefetchTarget.streamID(type: t.type, imdb: t.imdb, progress: t.type == "series" ? b.latest(forItem: t.item) : nil)
            for id in ids {
                #expect(PrefetchTarget.matches(id, type: t.type, imdb: t.imdb, itemID: t.item, book: b) == (key == id),
                        "\(t) \(id)")
            }
        }
    }
}

