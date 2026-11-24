import Foundation
import Testing
@testable import PlayerCore

// Task 3.8 ([04 §6.5]): the continue row looks up its play targets once per row (`resumeTargets`), not once per card.

private let movie = MetaPreview(id: "tt1", type: "movie", name: "Der Film")
private let show = MetaPreview(id: "tt9", type: "series", name: "Die Serie")
private let other = MetaPreview(id: "tt5", type: "movie", name: "Ohne Quelle")
private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func book() -> ProgressBook {
    var b = ProgressBook()
    b.entries["tt1"] = WatchProgress(id: "tt1", item: movie, position: 600, duration: 6000, updated: t0)
    b.entries["tt9:1:2"] = WatchProgress(id: "tt9:1:2", item: show, season: 1, episode: 2, position: 300, duration: 2400,
                                         updated: t0.addingTimeInterval(10))
    b.entries["tt9:1:3"] = WatchProgress(id: "tt9:1:3", item: show, season: 1, episode: 3, position: 200, duration: 2400,
                                         updated: t0.addingTimeInterval(20))
    b.entries["tt5"] = WatchProgress(id: "tt5", item: other, position: 900, duration: 6000, updated: t0.addingTimeInterval(5))
    let s = StreamItem(name: "[TB⚡] 1080p", description: "File.mkv", url: "https://x/1")
    b.rememberSource(s, addon: "A", for: "tt1", now: t0)
    b.rememberSource(s, addon: "A", for: "tt9:1:2", now: t0)
    return b
}

@Test func resumeTargetsKeyByItemWithLastSourceOnly() {
    let t = book().resumeTargets()
    #expect(Set(t.keys) == ["tt1", "tt9"])
    #expect(t["tt1"]?.id == "tt1")
    // Newest episode of the series, as in the continue row.
    #expect(t["tt9"]?.id == "tt9:1:3")
    #expect(t["tt5"] == nil)
}

@Test func resumeTargetsAgreeWithPerCardLookup() {
    let b = book()
    let t = b.resumeTargets()
    for item in [movie, show, other] {
        let perCard = b.continueWatching().first { $0.item.id == item.id }.flatMap { b.lastSource(for: $0.id) != nil ? $0 : nil }
        #expect(t[item.id] == perCard)
    }
    #expect(ProgressBook().resumeTargets().isEmpty)
}
