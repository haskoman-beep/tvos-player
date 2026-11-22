import Foundation
import Testing
@testable import PlayerCore

// Wave F-k: focus headroom of tile rows, picture fallback of poster tiles, badge log line.

// Token values of the app (Theme.Focus.cardLiftScale / cardLiftShadow), repeated here on purpose: a change of the
// tokens should be a conscious change of these expectations too.
private let lift: CGFloat = 1.15
private let shadow: CGFloat = 12

@Test func focusHeadroomPerSideGrowsWithHeightAndScale() {
    // 360 pt poster at 1.15: 27 pt growth per side + 12 pt shadow.
    #expect(FocusHeadroom.perSide(height: 360, scale: lift, shadow: shadow) == 39)
    // Rounded up to whole points, never down.
    #expect(FocusHeadroom.perSide(height: 306, scale: lift, shadow: shadow) == 35)   // 22.95 + 12
    #expect(FocusHeadroom.perSide(height: 432, scale: lift, shadow: shadow) == 45)   // 32.4 + 12
    // No lift: only the shadow; shrinking or negative values grow nothing.
    #expect(FocusHeadroom.perSide(height: 360, scale: 1, shadow: shadow) == 12)
    #expect(FocusHeadroom.perSide(height: 360, scale: 0.9, shadow: 0) == 0)
    #expect(FocusHeadroom.perSide(height: -10, scale: lift, shadow: -5) == 0)
}

@Test func focusHeadroomRowPaddingKeepsRowsThatHadRoom() {
    // Poster rows at Small / Medium / Large: old padding 32·s was too tight, the headroom wins.
    for size in CardSize.allCases {
        let s = size.scale
        let h = PosterSize.tileSize(.poster, scale: s).height
        let pad = FocusHeadroom.rowPadding(height: h, scale: lift, shadow: shadow, minimum: 32 * s)
        #expect(pad > 32 * s)
        #expect(pad >= h * (lift - 1) / 2 + shadow)
    }
    // Landscape (248) and logo (180) rows at Medium already had 32: unchanged.
    #expect(FocusHeadroom.rowPadding(height: 248, scale: lift, shadow: shadow, minimum: 32) == 32)
    #expect(FocusHeadroom.rowPadding(height: 180, scale: lift, shadow: shadow, minimum: 32) == 32)
    // Fixed tile rows (detail page) keep their wider padding.
    #expect(FocusHeadroom.rowPadding(height: 360, scale: lift, shadow: shadow, minimum: 44) == 44)
}

@Test func focusHeadroomPaddingIsConstantPerSize() {
    // Rows must not jump: the padding depends only on the card size, not on focus or content.
    let a = FocusHeadroom.rowPadding(height: 360, scale: lift, shadow: shadow, minimum: 32)
    let b = FocusHeadroom.rowPadding(height: 360, scale: lift, shadow: shadow, minimum: 32)
    #expect(a == b)
    #expect(FocusHeadroom.rowPadding(height: 306, scale: lift, shadow: shadow, minimum: 27.2)
            < FocusHeadroom.rowPadding(height: 432, scale: lift, shadow: shadow, minimum: 38.4))
}

@Test func focusHeadroomTallestTileOfRows() {
    #expect(FocusHeadroom.tallest([TileKind](), cardScale: 1) == 0)
    #expect(FocusHeadroom.tallest([.landscape, .poster, .logo], cardScale: 1) == 360)
    #expect(FocusHeadroom.tallest([.poster], cardScale: 1.2) == 432)
    // Quality strip below the poster belongs to the lifted card; not to other kinds.
    #expect(FocusHeadroom.tallest([.poster], cardScale: 1, posterExtra: 34) == 394)
    #expect(FocusHeadroom.tallest([.landscape], cardScale: 1, posterExtra: 34) == 248)
    // Hero stays fixed (620) at every size.
    #expect(FocusHeadroom.tallest([.hero, .poster], cardScale: 0.85) == 620)
}

@Test func focusHeadroomEdgeBandAddsFadeAboveLift() {
    // Hero home: band above the list = lift room (opaque) + fade 24.
    #expect(FocusHeadroom.edgeBand(height: 360, scale: lift, shadow: shadow, fade: 24) == 63)
    #expect(FocusHeadroom.edgeBand(height: 432, scale: lift, shadow: shadow, fade: 24) == 69)
    #expect(FocusHeadroom.edgeBand(height: 360, scale: lift, shadow: shadow, fade: -3) == 39)
    // The band stays clear of the hero info (list top 470, info ends well above 400 pt).
    #expect(FocusHeadroom.edgeBand(height: 620, scale: lift, shadow: shadow, fade: 24) < 100)
}

@Test func tilePosterChoiceOrderAndFallback() {
    let addon = "https://posters.example/a.jpg", tmdb = "https://image.tmdb.org/t/p/w500/b.jpg"
    #expect(TilePosterChoice.candidates(addon: addon, poster: tmdb) == [addon, tmdb])
    #expect(TilePosterChoice.current(addon: addon, poster: tmdb, failed: []) == addon)
    // Addon picture failed → TMDB poster.
    #expect(TilePosterChoice.current(addon: addon, poster: tmdb, failed: [addon]) == tmdb)
    #expect(TilePosterChoice.fallbackText(addon: addon, poster: tmdb, failed: [addon]) == "nächstes Poster")
    // Both failed → nothing left: the tile shows its title.
    #expect(TilePosterChoice.current(addon: addon, poster: tmdb, failed: [addon, tmdb]) == nil)
    #expect(TilePosterChoice.fallbackText(addon: addon, poster: tmdb, failed: [addon, tmdb]) == "Titel")
}

@Test func tilePosterChoiceSkipsEmptyAndRepeated() {
    let tmdb = "https://image.tmdb.org/t/p/w500/b.jpg"
    // Addon answered with an empty poster field: straight to TMDB, never an empty address.
    #expect(TilePosterChoice.candidates(addon: "", poster: tmdb) == [tmdb])
    #expect(TilePosterChoice.candidates(addon: "  ", poster: tmdb) == [tmdb])
    #expect(TilePosterChoice.candidates(addon: tmdb, poster: tmdb) == [tmdb])
    #expect(TilePosterChoice.candidates(addon: nil, poster: nil).isEmpty)
    #expect(TilePosterChoice.current(addon: nil, poster: nil, failed: []) == nil)
    // Only the addon poster known (catalogue item without poster) and it failed → title.
    #expect(TilePosterChoice.current(addon: "https://posters.example/a.jpg", poster: nil,
                                     failed: ["https://posters.example/a.jpg"]) == nil)
}

@Test func posterBadgeStatsLine() {
    #expect(PosterBadgeStats.logLine(row: "Trending", withQuality: 3, total: 20, placement: .topTrailing)
            == "Plaketten: Trending 3/20 mit Qualität")
    #expect(PosterBadgeStats.logLine(row: "Ähnliche Titel", withQuality: 0, total: 12, placement: .off)
            == "Plaketten: Ähnliche Titel 0/12 mit Qualität (Anzeige aus)")
    let s = BadgeSettings()
    #expect(PosterBadgeStats.hasBadges(BestQuality(resolution: "2160p"), settings: s))
    #expect(PosterBadgeStats.hasBadges(BestQuality(resolution: "1080p"), settings: s))
    // 720p without HDR/Atmos gives no poster badge; unknown quality neither.
    #expect(!PosterBadgeStats.hasBadges(BestQuality(resolution: "720p"), settings: s))
    #expect(!PosterBadgeStats.hasBadges(nil, settings: s))
}
