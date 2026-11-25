import Foundation
import Testing
@testable import PlayerCore

// MARK: Task 5.2: hero variants (heroStyle, heroInfo, carousel, backdrop after focus)

// HomeTopEdge per hero style (4): up from the first row lands on the hero button; with `aus` in the navigation.

@Test func topEdgeFullscreenHeroIsTheHeroButton() {
    #expect(HomeTopEdge.topmost(heroStyle: .vollbild, hasHeroSource: true, rowCount: 4, layoutEmpty: false) == .heroButtons)
    #expect(HomeTopEdge.aboveFirstRow(heroStyle: .vollbild, hasHeroSource: true) == .heroButton)
}

@Test func topEdgeBannerHeroIsTheHeroButton() {
    #expect(HomeTopEdge.topmost(heroStyle: .banner, hasHeroSource: true, rowCount: 4, layoutEmpty: false) == .heroButtons)
    #expect(HomeTopEdge.aboveFirstRow(heroStyle: .banner, hasHeroSource: true) == .heroButton)
}

@Test func topEdgeCarouselHeroIsTheHeroButton() {
    #expect(HomeTopEdge.topmost(heroStyle: .karussell, hasHeroSource: true, rowCount: 4, layoutEmpty: false) == .heroButtons)
    #expect(HomeTopEdge.aboveFirstRow(heroStyle: .karussell, hasHeroSource: true) == .heroButton)
}

@Test func topEdgeWithoutHeroStyleIsTheNavigation() {
    // `aus`: no hero; the first row is the top edge, up from it reaches the navigation.
    #expect(HomeTopEdge.topmost(heroStyle: .aus, hasHeroSource: true, rowCount: 4, layoutEmpty: false) == .firstRow)
    #expect(HomeTopEdge.aboveFirstRow(heroStyle: .aus, hasHeroSource: true) == .navigation)
    // A style without a hero source behaves like `aus` (no list row can feed the hero).
    #expect(HomeTopEdge.aboveFirstRow(heroStyle: .banner, hasHeroSource: false) == .navigation)
    #expect(HomeTopEdge.topmost(heroStyle: .aus, hasHeroSource: true, rowCount: 0, layoutEmpty: true) == .addRowsButton)
}

@Test func rowsTopPerInfoLevel() {
    // Full screen: the device-verified list top (470 below the page top) for standard; minimal 60 higher (plan
    // 640 vs 700); detailed keeps 470 while its info still fits above the buttons.
    #expect(HomeTopEdge.rowsTop(style: .vollbild, info: .standard) == 470)
    #expect(HomeTopEdge.rowsTop(style: .vollbild, info: .minimal) == 410)
    #expect(HomeTopEdge.rowsTop(style: .vollbild, info: .ausfuehrlich) == 470)
    // Banner and carousel: the buttons sit in the card's bottom; more info makes the card (and the list) lower.
    let b = LookHeroInfo.allCases.map { HomeTopEdge.rowsTop(style: .banner, info: $0) }
    #expect(b[0] <= b[1] && b[1] < b[2])
    #expect(HomeTopEdge.rowsTop(style: .banner, info: .minimal) == 300)   // card 460: 12 + 460 − 44 − 104 − 24
    #expect(HomeTopEdge.rowsTop(style: .karussell, info: .standard) <= HomeTopEdge.rowsTop(style: .banner, info: .standard))
    // `aus`: no hero, nothing above the list.
    #expect(HomeTopEdge.rowsTop(style: .aus, info: .standard) == 0)
    // A taller overview (bigger text) never pushes the info into the buttons.
    var big = HeroInfoMetrics.standard
    big.overview = 200
    let top = HomeTopEdge.rowsTop(style: .vollbild, info: .ausfuehrlich, metrics: big)
    #expect(top + big.listPadding >= big.infoBottom(.vollbild, level: .ausfuehrlich) + big.spacing)
}

@Test func carouselWrapsAtEnds() {
    #expect(HeroCarousel.step(0, count: 5, forward: false) == 4)
    #expect(HeroCarousel.step(4, count: 5, forward: true) == 0)
    #expect(HeroCarousel.step(2, count: 5, forward: true) == 3)
    #expect(HeroCarousel.step(2, count: 5, forward: false) == 1)
    #expect(HeroCarousel.step(0, count: 1, forward: true) == 0)
    #expect(HeroCarousel.step(0, count: 0, forward: false) == 0)
    #expect(HeroCarousel.step(9, count: 3, forward: true) == 0)   // stale index after a smaller slide set
}

@Test func backdropRequestsAtMostOncePerRest() {
    var f = HeroBackdropFollow()
    // Quick moves over three cards: only the last stop asks for a picture, once.
    let a = f.focus("a", follows: true), b = f.focus("b", follows: true), c = f.focus("c", follows: true)
    #expect(a != nil && b != nil && c != nil)
    #expect(f.rested(a!) == nil)
    #expect(f.rested(b!) == nil)
    #expect(f.rested(c!) == "c")
    #expect(f.rested(c!) == nil)
    #expect(f.shown == "c")
    // Back on the card it shows: no new request.
    #expect(f.focus("c", follows: true) == nil)
    // Leaving the rows cancels a waiting stop.
    let d = f.focus("d", follows: true)
    f.leave()
    #expect(f.rested(d!) == nil)
    #expect(f.shown == "c")
    // Option off: never a request.
    #expect(f.focus("e", follows: false) == nil)
}

// MARK: Info parts and frames

@Test func infoPartsPerLevel() {
    #expect(HeroInfoParts.of(.minimal) == HeroInfoParts(meta: false, ratings: false, overview: false, badges: false))
    #expect(HeroInfoParts.of(.standard) == HeroInfoParts(meta: true, ratings: true, overview: true, badges: false))
    #expect(HeroInfoParts.of(.ausfuehrlich) == HeroInfoParts(meta: true, ratings: true, overview: true, badges: true))
    // Collapsed full screen keeps every part (user decision 25.11.); the cards keep logo and meta line only.
    #expect(HeroInfoParts.collapsed(.standard, style: .vollbild) == .of(.standard))
    #expect(HeroInfoParts.collapsed(.ausfuehrlich, style: .banner)
            == HeroInfoParts(meta: true, ratings: false, overview: false, badges: false))
    #expect(HeroInfoParts.collapsed(.minimal, style: .karussell) == .of(.minimal))
}

@Test func fullscreenStandardCompactInfoIsTodays() {
    let m = HeroInfoMetrics.standard
    let c = m.compactInfo(.vollbild, level: .standard)
    let today = HeroInfoCollapse.CompactInfo(topInset: 12, logoMax: 100, logoMin: 80, spacing: 12, metaLine: 30,
                                             ratings: 34, overview: m.overview)
    #expect(c == today)
}

@Test func cardHeightShrinksAboveTheCollapsedList() {
    let m = HeroInfoMetrics.standard
    let open = m.cardHeight(.banner, level: .standard, collapsedTop: nil)
    #expect(open >= 460)
    let shut = m.cardHeight(.banner, level: .standard, collapsedTop: 294)
    #expect(shut == 294 - m.frameGap - m.frameTop)
    // The collapsed card holds its compact info (floor of the collapse layout).
    let info = m.compactInfo(.banner, level: .standard)
    let l = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 45, rowHeight: 580,
                                    expandedTop: HomeTopEdge.rowsTop(style: .banner, info: .standard), info: info)
    let h = m.cardHeight(.banner, level: .standard, collapsedTop: l.collapsedTop)
    #expect(h >= m.cardInnerTop + l.compactLogo + m.compactSpacing + m.metaLine + m.cardInnerBottom)
    // Never taller than open, and full screen has no card.
    #expect(m.cardHeight(.banner, level: .standard, collapsedTop: 2000) == open)
    #expect(m.cardHeight(.vollbild, level: .standard, collapsedTop: nil) == 0)
}
