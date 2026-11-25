import Foundation
import Testing
@testable import PlayerCore

// Build 4 follow-up 2 (P3): pictures that went on screen (backdrop swaps, first poster per tile), summed up for one
// `bilder` line per window: from the memory cache or loaded, how long the load took until the fade started, the
// largest bitmap and the bitmap bytes in all (what the GPU has to take over).

@Test func pictureArrivalStatsLineForBackdrops() {
    var s = PictureArrivalStats(title: "Hintergrund")
    #expect(PictureArrivalStats.window == 10)
    #expect(s.take() == nil)
    let opened = s.record(fromMemory: true, waitMs: 0, pixelWidth: 1920, pixelHeight: 1080, bytes: 8_294_400, fades: false)
    #expect(opened)
    let second = s.record(fromMemory: false, waitMs: 640, pixelWidth: 3840, pixelHeight: 2160, bytes: 33_177_600, fades: true)
    let third = s.record(fromMemory: false, waitMs: 200, pixelWidth: 3840, pixelHeight: 1600, bytes: 24_576_000, fades: true)
    #expect(!second && !third)
    // 66 048 000 bytes = 63,0 MB; average wait over the loaded ones (640 + 200) / 2.
    #expect(s.take() == "Hintergrund 3 · aus Speicher 1 · geladen 2 (längstes 640 ms, Ø 420 ms) · eingeblendet 2"
            + " · größtes 3840×2160 px · zusammen 63,0 MB")
    #expect(s.take() == nil)
}

@Test func pictureArrivalStatsLineWithoutLoads() {
    var s = PictureArrivalStats(title: "Erste Poster")
    s.record(fromMemory: true, waitMs: 0, pixelWidth: 400, pixelHeight: 600, bytes: 960_000, fades: false)
    s.record(fromMemory: true, waitMs: 0, pixelWidth: 600, pixelHeight: 400, bytes: 960_000, fades: false)
    // Same area: the first one stays the largest. 1 920 000 bytes = 1,8 MB.
    #expect(s.take() == "Erste Poster 2 · aus Speicher 2 · geladen 0 · eingeblendet 0 · größtes 400×600 px · zusammen 1,8 MB")
}

@Test func pictureArrivalStatsWindowStartsAgainAfterTake() {
    var s = PictureArrivalStats(title: "Hintergrund")
    let first = s.record(fromMemory: false, waitMs: 100, pixelWidth: 10, pixelHeight: 10, bytes: 400, fades: true)
    _ = s.take()
    let again = s.record(fromMemory: false, waitMs: 50, pixelWidth: 10, pixelHeight: 10, bytes: 400, fades: true)
    #expect(first && again)
    #expect(s.take() == "Hintergrund 1 · aus Speicher 0 · geladen 1 (längstes 50 ms, Ø 50 ms) · eingeblendet 1"
            + " · größtes 10×10 px · zusammen 0,0 MB")
}
