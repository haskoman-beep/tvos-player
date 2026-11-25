import Foundation
import Testing
@testable import PlayerCore

// Task 5.5 (D-3, Q-28): system "reduce transparency" / "reduce motion" and the fixed-size glyphs of the other screens.

@Test func opaqueWhiteMixesOverBase() {
    #expect(LookTheme.opaqueWhite(0.10, over: 0x000000) == 0x1A1A1A)
    #expect(LookTheme.opaqueWhite(0.10, over: 0x121212) == 0x2A2A2A)
    #expect(LookTheme.opaqueWhite(0, over: 0x111827) == 0x111827)
    #expect(LookTheme.opaqueWhite(1, over: 0x111827) == 0xFFFFFF)
    // Channels stay apart (no carry from one byte into the next).
    #expect(LookTheme.opaqueWhite(0.18, over: 0x0E0B08) == 0x393734)
}

@Test func opaqueSurfaceFollowsBackground() {
    var v = LookPreset.values(.appleTV)
    // Preset background keeps today's surface (white 7 % over black, `Theme.Palette.surface`).
    #expect(LookTheme.opaqueSurface(v) == 0x121212)
    v.global.background = .tinte
    #expect(LookTheme.opaqueSurface(v) == LookTheme.background(.tinte).surface)
}

@Test func expandsPostersOffWhileSystemReducesMotion() {
    var v = LookPreset.values(.appleTV)
    v.home.expandPosters = true
    #expect(LookTheme.expandsPosters(v, reduceMotion: false))
    #expect(!LookTheme.expandsPosters(v, reduceMotion: true))
    v.home.expandPosters = false
    #expect(!LookTheme.expandsPosters(v, reduceMotion: false))
}

@Test func glyphsKeepTodaysSizesAndFollowTypeScale() {
    #expect(LookTheme.glyph(.monogram, scale: .standard) == LookTheme.GlyphSpec(size: 90, weight: 700, monospaced: false))
    #expect(LookTheme.glyph(.code, scale: .standard) == LookTheme.GlyphSpec(size: 90, weight: 700, monospaced: true))
    #expect(LookTheme.glyph(.symbol, scale: .standard) == LookTheme.GlyphSpec(size: 32, weight: 400, monospaced: false))
    for g in LookTheme.Glyph.allCases {
        let s = LookTheme.glyph(g, scale: .standard).size
        #expect(abs(LookTheme.glyph(g, scale: .gross).size - s * LookMetrics.typeScale(.gross)) < 0.001)
        #expect(abs(LookTheme.glyph(g, scale: .kompakt).size - s * LookMetrics.typeScale(.kompakt)) < 0.001)
    }
}

@Test func tileMotionStaysStillWhileSystemReducesMotion() throws {
    let json = #"{"id":"a","title":"A","sources":[],"focusGif":"g","focusVideo":"https://example.com/a.focus.mp4"}"#
    let f = try JSONDecoder().decode(Folder.self, from: Data(json.utf8))
    #expect(TileMotion.of(f, reduceMotion: false) == TileMotion.of(f))
    #expect(TileMotion.of(f, reduceMotion: false) != .still)
    #expect(TileMotion.of(f, reduceMotion: true) == .still)
}
