import Foundation
import Testing
@testable import PlayerCore

// Wave Q: source list filter chips, focus held at its row while sources arrive, full file name.

private func traits(_ res: String? = nil, hdr: [String] = [], audio: [String] = [], lang: [String] = [],
                    size: Int64? = nil, cached: Bool? = nil, source: String? = nil) -> StreamTraits {
    var t = StreamTraits()
    t.resolution = res; t.hdr = hdr; t.audio = audio; t.languages = lang; t.sizeBytes = size; t.cached = cached
    t.source = source
    return t
}

private let gb: Int64 = 1_000_000_000

@Test func filterOffersOnlyChipsThatSplitTheList() {
    let list = [traits("2160p", hdr: ["DV", "HDR10"], audio: ["Atmos"], size: 60 * gb, cached: true, source: "REMUX"),
                traits("2160p", hdr: ["DV"], size: 18 * gb, cached: false),
                traits("1080p", lang: ["de"], size: 3 * gb, cached: true)]
    let chips = SourceFilter.options(list).map(\.chip)
    #expect(chips == [.resolution("2160p"), .resolution("1080p"), .dolbyVision, .hdr, .atmos, .remux, .german, .cached,
                      .size(.small), .size(.medium), .size(.large)])
    #expect(SourceFilter.options(list).first { $0.chip == .dolbyVision }?.count == 2)
    // DV alone is not HDR.
    #expect(SourceFilter.options(list).first { $0.chip == .hdr }?.count == 1)
    // A trait every source has filters nothing; a missing one has no chip. A selected chip always stays.
    let same = [traits("1080p", cached: true), traits("1080p", cached: true)]
    #expect(SourceFilter.options(same).isEmpty)
    #expect(SourceFilter.options(same, selected: [.cached]).map(\.chip) == [.cached])
    #expect(SourceFilter.options([]).isEmpty)
    #expect(SourceFilterChip.resolution("2160p").label == "4K")
}

@Test func filterToggleKeepsOneChipPerGroupAndCombinesGroups() {
    var s: Set<SourceFilterChip> = []
    s = SourceFilter.toggle(.resolution("2160p"), in: s)
    s = SourceFilter.toggle(.dolbyVision, in: s)
    s = SourceFilter.toggle(.resolution("1080p"), in: s)
    #expect(s == [.resolution("1080p"), .dolbyVision])
    s = SourceFilter.toggle(.dolbyVision, in: s)
    #expect(s == [.resolution("1080p")])
    s = SourceFilter.toggle(.size(.small), in: SourceFilter.toggle(.size(.large), in: s))
    #expect(s == [.resolution("1080p"), .size(.small)])

    let uhdDV = traits("2160p", hdr: ["DV"], size: 25 * gb, cached: true)
    #expect(SourceFilter.passes(uhdDV, [.resolution("2160p"), .dolbyVision, .cached, .size(.large)]))
    #expect(!SourceFilter.passes(uhdDV, [.resolution("2160p"), .hdr]))
    #expect(SourceFilter.passes(uhdDV, []))
    // Unknown size or cache state never passes those chips.
    #expect(!SourceFilter.passes(traits("2160p"), [.size(.small)]))
    #expect(!SourceFilter.passes(traits("2160p"), [.cached]))
    #expect(SourceSizeBucket.medium.contains(5 * gb) && SourceSizeBucket.medium.contains(20 * gb))
    #expect(!SourceSizeBucket.small.contains(0))
}

@Test func filterSelectionDropsChipsTheNewListLacks() {
    let opts = SourceFilter.options([traits("2160p"), traits("1080p")])
    #expect(SourceFilter.effective([.resolution("2160p"), .dolbyVision], options: opts) == [.resolution("2160p")])
}

@Test func focusKeepsRowPositionWhileSourcesArrive() {
    // New sources sort in above the focused row 3 ("c"): the focus stays on row 3, now "b".
    #expect(SourceFocus.keepPosition(focused: "c", old: ["a", "b", "c", "d"], new: ["x", "a", "b", "c", "d"]) == "b")
    #expect(SourceFocus.keepPosition(focused: "c", old: ["a", "b", "c"], new: ["a", "x", "y", "b", "c"]) == "y")
    // Added below or same place: nothing to do.
    #expect(SourceFocus.keepPosition(focused: "b", old: ["a", "b"], new: ["a", "b", "c"]) == nil)
    // No focus, focus outside the list (loading line), empty new list.
    #expect(SourceFocus.keepPosition(focused: nil, old: ["a"], new: ["x", "a"]) == nil)
    #expect(SourceFocus.keepPosition(focused: "z", old: ["a"], new: ["x", "a"]) == nil)
    #expect(SourceFocus.keepPosition(focused: "a", old: ["a"], new: []) == nil)
    // Focused source dropped (dedupe) and the list got shorter: last row.
    #expect(SourceFocus.keepPosition(focused: "c", old: ["a", "b", "c"], new: ["a", "b"]) == "b")
    // Focused source moved up: its old place now holds another one.
    #expect(SourceFocus.keepPosition(focused: "c", old: ["a", "b", "c"], new: ["c", "a", "b"]) == "b")
}

@Test func rowTextAddsFullFileNameOnlyWhenNotShown() {
    var h = try! JSONDecoder().decode(StreamBehaviorHints.self, from: Data("{}".utf8))
    h.filename = "Pixels.2015.2160p.UHD.BluRay.REMUX.DV.HDR.HEVC.TrueHD.Atmos.7.1-GRP.mkv"
    // Cut by the formatter: the full name follows.
    let cut = StreamItem(name: "AIO ⚡", description: "🎬 Pixels.2015.2160p.UHD.BluRay…\n💾 60 GB", url: "https://u", behaviorHints: h)
    #expect(StreamRowText(cut).fileName == h.filename)
    // Same name with spaces for dots is already shown.
    let spaced = StreamItem(name: "AIO", description: "Pixels 2015 2160p UHD BluRay REMUX DV HDR HEVC TrueHD Atmos 7 1 GRP mkv",
                            url: "https://u", behaviorHints: h)
    #expect(StreamRowText(spaced).fileName == nil)
    // Body built from the file name: no second copy.
    #expect(StreamRowText(StreamItem(url: "https://u", behaviorHints: h)).fileName == nil)
    #expect(StreamRowText(StreamItem(name: "n", description: "d", url: "https://u")).fileName == nil)
    #expect(StreamRowText.extraFileName("  ", shown: "x") == nil)
}
