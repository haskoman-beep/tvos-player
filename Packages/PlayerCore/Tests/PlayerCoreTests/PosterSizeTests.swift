import Foundation
import Testing
@testable import PlayerCore

// Welle F-f: Postergröße Klein / Mittel / Groß; Mittel = bisherige Maße, Seitenverhältnis bleibt.
@Test func posterSizeMediumKeepsTodaysTiles() {
    #expect(PosterSize.tileSize(for: .medium, style: .poster) == CGSize(width: 240, height: 360))
    #expect(PosterSize.tileSize(for: .medium, style: .top10) == CGSize(width: 240, height: 360))
    #expect(PosterSize.tileSize(for: .medium, style: .landscape) == CGSize(width: 440, height: 248))
    #expect(PosterSize.tileSize(for: .medium, style: .collectionTiles) == CGSize(width: 440, height: 248))
    #expect(PosterSize.tileSize(for: .medium, style: .logoTiles) == CGSize(width: 320, height: 180))
    #expect(PosterSize.tileWidth(for: .medium, style: .poster) == 240)
    #expect(PosterSize.tileHeight(for: .medium, style: .landscape) == 248)
}

@Test func posterSizeScalesAndKeepsAspect() {
    for size in CardSize.allCases {
        for style in RowStyle.allCases where style != .hero {
            let base = PosterSize.baseSize(PosterSize.kind(for: style))
            let t = PosterSize.tileSize(for: size, style: style)
            #expect(abs(t.width / t.height - base.width / base.height) < 0.0001)
            #expect(abs(t.width - base.width * size.scale) < 0.0001)
        }
    }
    #expect(PosterSize.tileWidth(for: .small, style: .poster) < PosterSize.tileWidth(for: .medium, style: .poster))
    #expect(PosterSize.tileWidth(for: .large, style: .poster) > PosterSize.tileWidth(for: .medium, style: .poster))
    // Hero bleibt fest.
    #expect(PosterSize.tileSize(for: .large, style: .hero) == CGSize(width: 1600, height: 620))
    #expect(PosterSize.spacing(scale: 1) == 20)
}

@Test func placeholdersFillVisibleWidth() {
    // Mittel: 1840 / (240 + 20) = 7,1 → 8 Poster.
    #expect(PosterSize.placeholderCount(for: .medium, style: .poster) == 8)
    #expect(PosterSize.placeholderCount(for: .small, style: .poster) > PosterSize.placeholderCount(for: .large, style: .poster))
    #expect(PosterSize.placeholderCount(for: .medium, style: .hero) == 2)
    for size in CardSize.allCases {
        for style in RowStyle.allCases {
            let n = PosterSize.placeholderCount(for: size, style: style)
            #expect(n >= 1 && n <= 12)
            // Gefüllt: n Kacheln reichen über die sichtbare Breite.
            let w = PosterSize.tileWidth(for: size, style: style) + (style == .top10 ? 190 * size.scale : 0)
            #expect(CGFloat(n) * (w + PosterSize.spacing(scale: size.scale)) >= 1840 || n == 12)
        }
    }
}

// Welle F-f: jede Phase einer Reihe hat ein Fokusziel; Rückgabe des Fokus nach dem Laden.
@Test func homeRowPhaseDecidesTileAndFocus() {
    #expect(HomeRowPhase(loaded: false, failed: false, count: 0) == .loading)
    #expect(HomeRowPhase(loaded: false, failed: true, count: 3) == .loading)
    #expect(HomeRowPhase(loaded: true, failed: false, count: 3) == .items(3))
    #expect(HomeRowPhase(loaded: true, failed: true, count: 3) == .items(3))   // alter Stand schlägt Fehler
    #expect(HomeRowPhase(loaded: true, failed: false, count: 0) == .empty)
    #expect(HomeRowPhase(loaded: true, failed: true, count: 0) == .failed)
    #expect(HomeRowPhase.empty.statusText(empty: "Keine Einträge") == "Keine Einträge")
    #expect(HomeRowPhase.failed.statusText(empty: "x") == "Laden fehlgeschlagen – erneut versuchen")
    #expect(HomeRowPhase.loading.statusText(empty: "x") == nil && HomeRowPhase.items(2).statusText(empty: "x") == nil)
    #expect(HomeRowPhase.items(3).focusAfterLoad(placeholder: 5) == 2)
    #expect(HomeRowPhase.items(3).focusAfterLoad(placeholder: 1) == 1)
    #expect(HomeRowPhase.empty.focusAfterLoad(placeholder: 4) == 0)
    #expect(HomeRowPhase.failed.focusAfterLoad(placeholder: 4) == 0)
}

@Test func preloadKeepsHomeOrderSkipsLocalAndDuplicates() {
    let a = CatalogSource.watchlist
    let rows = [HomeRow(content: .list(.continueWatching)), HomeRow(content: .list(a)),
                HomeRow(content: .collection(id: "c")), HomeRow(content: .list(.upcoming)), HomeRow(content: .list(a))]
    #expect(HomeRowPreload.sources(rows).map(\.id) == [a.id, CatalogSource.upcoming.id])
    #expect(HomeRowPreload.limit == 4)
}
