import Foundation
import Testing
@testable import PlayerCore

// Task 3.8 ([04 §6.2]): traits are parsed once per stream (`RankedStream`) and passed through ordering,
// „Beste Wahl“ and badges; the tuple APIs give the same results as before.

private func st(_ name: String, _ desc: String = "", hints: StreamBehaviorHints? = nil, url: String? = nil) -> StreamItem {
    StreamItem(name: name, description: desc, url: url ?? "https://x/\(name.hashValue)/\(desc.hashValue)", behaviorHints: hints)
}

private let de = SourceRankContext(primaryLanguage: "de", av1Hardware: false)

private let mixed: [(addon: String, stream: StreamItem)] = [
    ("A", st("[TB⏳] 2160p", "German DV")),
    ("A", st("[RD⚡] 2160p", "English AV1 HDR")),
    ("B", st("[TB⚡] 1080p", "German DD5.1")),
    ("B", st("[TB⚡] 2160p", "German DV HDR10 DDP5.1")),
    ("A", st("[RD⚡] 720p", "Multi AAC")),
    ("B", st("[TB⚡] 1080p", "French")),
]

private func ids(_ l: [(addon: String, stream: StreamItem)]) -> [String] { l.map(\.stream.id) }
private func ids(_ l: [RankedStream]) -> [String] { l.map(\.stream.id) }

@Test func rankedStreamParsesTraitsOnce() {
    let s = st("[TB⚡] 2160p", "German DV 💾 12.3 GB")
    let r = RankedStream(addon: "A", stream: s)
    #expect(r.addon == "A")
    #expect(r.stream == s)
    #expect(r.traits == StreamTraits.parse(s))
    #expect(RankedStream.rank(mixed).map(\.traits) == mixed.map { StreamTraits.parse($0.stream) })
}

@Test func rankedOrderingMatchesTupleOrdering() {
    let ranked = RankedStream.rank(mixed)
    #expect(ids(SourceRanking.order(ranked, context: de)) == ids(SourceRanking.order(mixed, context: de)))
    #expect(ids(StreamListOrder.automatic(ranked, context: de)) == ids(StreamListOrder.automatic(mixed, context: de)))
    for mode in StreamOrderMode.allCases {
        #expect(ids(StreamListOrder.ordered(ranked, mode: mode, context: de))
                == ids(StreamListOrder.ordered(mixed, mode: mode, context: de)))
    }
}

@Test func rankedAutomaticDropsDuplicates() {
    let a = st("[TB⚡] 1080p", "German", url: "https://same")
    let b = st("[TB⚡] 2160p", "German", url: "https://same")
    let ranked = RankedStream.rank([("A", a), ("A", b)])
    #expect(ids(StreamListOrder.automatic(ranked, context: de)) == [a.id])
}

/// The given traits are used as they are (no second parse): a stream whose text says 720p but carries 2160p
/// traits wins the pick.
@Test func rankedPickUsesCarriedTraits() {
    let low = st("[TB⚡] 720p", "German")
    let high = st("[TB⚡] 1080p", "German")
    var boosted = StreamTraits.parse(low)
    boosted.resolution = "2160p"
    let ranked = [RankedStream(addon: "A", stream: low, traits: boosted), RankedStream(addon: "A", stream: high)]
    #expect(BestChoice.pick(ranked: ranked, context: de, last: nil, isFailed: { _ in false })?.stream == low)
    #expect(BestChoice.pick([("A", low), ("A", high)], context: de, last: nil, isFailed: { _ in false })?.stream == high)
}

@Test func rankedPickMatchesTuplePick() {
    let ranked = RankedStream.rank(mixed)
    let a = BestChoice.pick(ranked: ranked, context: de, last: nil, isFailed: { _ in false })
    let b = BestChoice.pick(mixed, context: de, last: nil, isFailed: { _ in false })
    #expect(a == b)
    let last = LastSource(stream: mixed[2].stream, addon: "B", contentID: "tt1")
    let la = BestChoice.pick(ranked: ranked, context: de, last: last, isFailed: { _ in false })
    #expect(la == BestChoice.pick(mixed, context: de, last: last, isFailed: { _ in false }))
    #expect(la?.reason == .lastSource)
}

@Test func lastSourceMatchOnRankedUsesTraits() {
    // Same addon and name, different file: matched by resolution from the carried traits.
    let old = StreamItem(name: "[TB⚡] Torrentio", description: "Old.File.2160p.mkv", url: "https://x/old")
    let last = LastSource(stream: old, addon: "A", contentID: "tt1")
    let new = StreamItem(name: "[TB⚡] Torrentio", description: "New.File.2160p.mkv", url: "https://x/new")
    #expect(last.match(in: [RankedStream(addon: "A", stream: new)]) == new)
    var other = StreamTraits.parse(new)
    other.resolution = "1080p"
    #expect(last.match(in: [RankedStream(addon: "A", stream: new, traits: other)]) == nil)
    #expect(last.match(in: [(addon: "A", stream: new)]) == new)
}

@Test func rankedBadgesMatchStreamBadges() {
    let ranked = RankedStream.rank(mixed)
    let streams = mixed.map(\.stream)
    #expect(BestQuality.from(ranked) == BestQuality.from(streams))
    #expect(DetailQuality.from(ranked) == DetailQuality.from(streams))
    #expect(DetailQuality.from([RankedStream]()) == nil)
}

@Test func parseSizeKeepsResults() {
    #expect(StreamTraits.parseSize("💾 12.3 GB") == 12_300_000_000)
    #expect(StreamTraits.parseSize("1,5 TB") == 1_500_000_000_000)
    #expect(StreamTraits.parseSize("850MB") == 850_000_000)
    #expect(StreamTraits.parseSize("NO SIZE") == nil)
    #expect(StreamTraits.parseSize("12345678901234567890 GB") == nil)
}
