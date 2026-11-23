import Foundation
import Testing
@testable import PlayerCore

/// Kleiner, deterministischer Zufallsgenerator (SplitMix64), damit der Fuzz-Test bei jedem Lauf dieselben Texte prüft.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Test func parseSizeRejectsHugeNumber() {
    #expect(StreamTraits.parseSize("12345678901234567890 GB") == nil)
    #expect(StreamTraits.parseSize("X 99999999999999 TB") == nil)
    #expect(StreamTraits.parseSize("45.2 GB") == 45_200_000_000)   // gültige Größe bleibt
}

@Test func streamTraitsParseSurvivesFuzzInput() {
    var rng = SplitMix64(state: 0x5EED_1234)
    let pieces = ["", " ", "\n", "GB", "MB", "TB", "gb", " GB", ",", ".", "💾", "⚡", "🇩🇪", "👨‍👩‍👧", "[", "]", "(", ")",
                  "2160p", "1080p", "4K", "HDR", "DV", "DD+", "5.1", "x265", "TB+", "Instant TB", "⏳", "-", ":",
                  "0", "9", "00000", "\u{0}", "\u{FEFF}", "é", "Ⅻ", "٣", "١٢٣"]
    func digits(_ rng: inout SplitMix64) -> String {
        let n = Int.random(in: 1...24, using: &rng)
        return String((0..<n).map { _ in Character(String(Int.random(in: 0...9, using: &rng))) })
    }
    func text(_ rng: inout SplitMix64) -> String? {
        if Int.random(in: 0..<6, using: &rng) == 0 { return nil }   // leeres Feld
        var s = ""
        for _ in 0..<Int.random(in: 0...8, using: &rng) {
            switch Int.random(in: 0..<3, using: &rng) {
            case 0: s += digits(&rng)
            case 1: s += digits(&rng) + [",", ".", ""].randomElement(using: &rng)! + digits(&rng)
            default: s += pieces.randomElement(using: &rng)!
            }
        }
        return s
    }
    var parsed = 0
    for _ in 0..<2_000 {
        let item = StreamItem(name: text(&rng), title: text(&rng), description: text(&rng), url: text(&rng))
        let t = StreamTraits.parse(item)
        if let size = t.sizeBytes { #expect(size >= 0) }
        parsed += 1
    }
    #expect(parsed == 2_000)
}
