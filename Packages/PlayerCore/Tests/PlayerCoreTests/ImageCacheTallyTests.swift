import Foundation
import Testing
@testable import PlayerCore

// Build 4 follow-up 2 (P3): why the picture memory cache misses so often (device log: 21 hits / 180 misses per 30 s).
// Each miss gets a class: a new address, the address in another size (target mismatch), the same key decoded before
// and dropped since (memory budget), or a load already running for it. Loads are split into disk and network
// (URLSession metrics), decodes timed, NSCache releases counted.

@Test func imageCacheMissClasses() {
    #expect(ImageCacheTally.classify(key: "u#300x450c", lastKey: nil, joined: false) == .new)
    #expect(ImageCacheTally.classify(key: "u#300x450c", lastKey: "u#300x450c", joined: false) == .evicted)
    #expect(ImageCacheTally.classify(key: "u#600x900c", lastKey: "u#300x450c", joined: false) == .otherSize)
    // A running load for the same key: joined, whatever was decoded before.
    #expect(ImageCacheTally.classify(key: "u#300x450c", lastKey: nil, joined: true) == .joined)
}

@Test func imageCacheTallyLine() {
    var t = ImageCacheTally()
    #expect(t.isEmpty)
    for _ in 0..<3 { t.hit() }
    for _ in 0..<5 { t.miss(.new) }
    t.miss(.otherSize)
    t.miss(.evicted)
    t.miss(.joined); t.miss(.joined)
    for _ in 0..<6 { t.fetched() }
    t.loaded(fromDisk: true); t.loaded(fromDisk: true); t.loaded(fromDisk: false)
    t.decoded(ms: 12); t.decoded(ms: 85); t.decoded(ms: 30)
    t.evicted(bytes: 33_177_600); t.evicted(bytes: 960_000)
    #expect(!t.isEmpty)
    #expect(t.misses == 9)
    #expect(t.text() == "Cache Treffer 3 / Fehlgriffe 9 (neu 5 · andere Größe 1 · verdrängt 1 · läuft schon 2)"
            + " · Ladungen 6 (Platte 2 · Netz 1) · dekodiert 3, längstes 85 ms · freigegeben 2 (32,6 MB)")
}

@Test func imageCacheTallyLineStaysShortWithoutDetails() {
    var t = ImageCacheTally()
    t.hit(); t.hit()
    #expect(t.text() == "Cache Treffer 2 / Fehlgriffe 0")
    t.miss(.new)
    #expect(t.text() == "Cache Treffer 2 / Fehlgriffe 1 (neu 1 · andere Größe 0 · verdrängt 0 · läuft schon 0)")
}
