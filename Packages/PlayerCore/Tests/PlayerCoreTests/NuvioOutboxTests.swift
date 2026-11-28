import Foundation
import Testing
@testable import PlayerCore

// Nuvio account sync, T6: the latest-wins push buffer. Invented values only.

private let t0 = Date(timeIntervalSince1970: 1_750_000_000)
private func push(_ content: String = "tt0137523", season: Int? = nil, episode: Int? = nil, position: Int = 600_000,
                  duration: Int = 6_000_000, last: Int = 1_750_000_000_000) -> NuvioProgressPush {
    NuvioProgressPush(contentID: content, contentType: season == nil ? "movie" : "series",
                      videoID: NuvioMapping.videoID(contentID: content, season: season, episode: episode),
                      season: season, episode: episode, position: position, duration: duration, lastWatched: last)
}

@Test func nuvioOutboxKeysByProgressKey() {
    var o = NuvioOutbox()
    o.note(push(), now: t0)
    o.note(push("tmdb:1396", season: 1, episode: 1), now: t0)
    #expect(o.keys == ["tt0137523", "tmdb:1396_s1e1"])
    #expect(o.entries["tmdb:1396_s1e1"]?.kind == .progress)
}

@Test func nuvioOutboxTwoNotesKeepTheNewer() {
    var o = NuvioOutbox()
    o.note(push(position: 1000, last: 2000), now: t0)
    o.note(push(position: 5000, last: 3000), now: t0)
    #expect(o.batch().map(\.entry.position) == [5000])
    // An older report arriving late does not replace a newer one.
    o.note(push(position: 9000, last: 2500), now: t0)
    #expect(o.batch().map(\.entry.position) == [5000])
    #expect(o.batch().count == 1)
}

@Test func nuvioOutboxWatchedKindIsSentAsTheFullLength() {
    // Addendum A8: "marked watched by the app" goes out as position = duration.
    var o = NuvioOutbox()
    o.note(push(position: 0, duration: 5_400_000), kind: .watched, now: t0)
    let b = o.batch()
    #expect(b.count == 1 && b[0].entry.position == 5_400_000 && b[0].entry.duration == 5_400_000)
    #expect(o.entries["tt0137523"]?.kind == .watched)
}

@Test func nuvioOutboxIsDueOnceAMinute() {
    var o = NuvioOutbox()
    #expect(!o.isDue(now: t0, force: true))   // nothing to send
    o.note(push(), now: t0)
    #expect(o.isDue(now: t0, force: false))   // never sent
    o.confirm(o.batch(), now: t0)
    o.note(push(last: 1_750_000_010_000), now: t0.addingTimeInterval(10))
    #expect(!o.isDue(now: t0.addingTimeInterval(59), force: false))
    #expect(o.isDue(now: t0.addingTimeInterval(60), force: false))
    #expect(o.isDue(now: t0.addingTimeInterval(59), force: true))
    // A failed send throttles too.
    o.failed(now: t0.addingTimeInterval(60))
    #expect(!o.isDue(now: t0.addingTimeInterval(100), force: false))
    #expect(o.isDue(now: t0.addingTimeInterval(120), force: false))
    // A clock that went back never blocks sending.
    #expect(o.isDue(now: t0, force: false))
}

@Test func nuvioOutboxConfirmKeepsAnEntryReplacedInFlight() {
    var o = NuvioOutbox()
    o.note(push(position: 1000, last: 1000), now: t0)
    o.note(push("tt2", position: 1000, last: 1000), now: t0)
    let sent = o.batch()
    o.note(push(position: 2000, last: 2000), now: t0.addingTimeInterval(5))
    o.confirm(sent, now: t0.addingTimeInterval(6))
    #expect(o.keys == ["tt0137523"])
    #expect(o.batch().map(\.entry.position) == [2000])
}

@Test func nuvioOutboxPruneDropsOldAndOverflow() {
    var o = NuvioOutbox()
    o.note(push("tt1"), now: t0)
    o.note(push("tt2"), now: t0.addingTimeInterval(NuvioOutbox.maxAge - 10))
    o.prune(now: t0.addingTimeInterval(NuvioOutbox.maxAge + 1))
    #expect(o.keys == ["tt2"])

    var big = NuvioOutbox()
    for i in 0..<(NuvioOutbox.maxEntries + 5) {
        big.note(push("tt\(1000 + i)", last: 1_000_000 + i), now: t0.addingTimeInterval(Double(i)))
    }
    big.prune(now: t0.addingTimeInterval(1000))
    #expect(big.keys.count == NuvioOutbox.maxEntries)
    #expect(!big.keys.contains("tt1000") && !big.keys.contains("tt1004") && big.keys.contains("tt1005"))
    #expect(big.batch().count == NuvioOutbox.maxEntries)
}

@Test func nuvioOutboxBatchIsOldestFirst() {
    var o = NuvioOutbox()
    o.note(push("tt3", last: 3000), now: t0)
    o.note(push("tt1", last: 1000), now: t0)
    o.note(push("tt2", last: 2000), now: t0)
    #expect(o.batch().map(\.key) == ["tt1", "tt2", "tt3"])
}

@Test func nuvioOutboxRemoveForATitle() {
    var o = NuvioOutbox()
    o.note(push("tmdb:1396", season: 1, episode: 1), now: t0)
    o.note(push("tmdb:1396", season: 1, episode: 2), now: t0)
    o.note(push("tt9"), now: t0)
    #expect(o.remove(contentIDs: ["tmdb:1396"]) == 2)
    #expect(o.keys == ["tt9"])
    o.removeAll()
    #expect(o.isEmpty)
}

@Test func nuvioOutboxRoundTripAndLenientDecoding() throws {
    var o = NuvioOutbox()
    o.note(push(), kind: .watched, now: t0)
    o.failed(now: t0)
    let back = try JSONDecoder().decode(NuvioOutbox.self, from: JSONEncoder().encode(o))
    #expect(back == o)
    // One unreadable entry is dropped, the rest stays; an unknown kind reads as progress.
    let json = """
    {"entries":{"tt1":{"push":{"content_id":"tt1","content_type":"movie","video_id":"tt1","position":1,"duration":2,
    "last_watched":3},"kind":"future-kind","notedAt":0},"tt2":{"push":"broken"}},"extra":true}
    """
    let lenient = try JSONDecoder().decode(NuvioOutbox.self, from: Data(json.utf8))
    #expect(lenient.keys == ["tt1"] && lenient.entries["tt1"]?.kind == .progress)
    #expect(try JSONDecoder().decode(NuvioOutbox.self, from: Data("{}".utf8)).isEmpty)
}
