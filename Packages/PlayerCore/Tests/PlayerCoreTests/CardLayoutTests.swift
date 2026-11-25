import Foundation
import Testing
@testable import PlayerCore

// Task 5.1 (D-6, D-8, D-16, D-23, D-24, Q-10, Q-26): card form, size, title strip and focus room of the home rows.

private func home(_ change: (inout LookHome) -> Void = { _ in }) -> LookHome {
    var h = LookPreset.values(.appleTV).home
    change(&h)
    return h
}

@Test func cardShapeMixingUsesLandscapeOnlyForContinueWatching() {
    #expect(CardLayout.shape(for: .continueWatching, option: .mischung) == .landscape)
    #expect(CardLayout.shape(for: .other, option: .mischung) == .poster)
    for row in [HomeRowKind.continueWatching, .other] {
        #expect(CardLayout.shape(for: row, option: .poster) == .poster)
        #expect(CardLayout.shape(for: row, option: .querformat) == .landscape)
    }
}

@Test func cardShapeOnlyRecutsPosterAndLandscapeRows() {
    // Poster and landscape rows follow the option; Top 10, hero, logo and collection tiles keep their own form.
    #expect(CardLayout.tileKind(style: .poster, row: .other, option: .querformat) == .landscape)
    #expect(CardLayout.tileKind(style: .landscape, row: .other, option: .poster) == .poster)
    #expect(CardLayout.tileKind(style: .landscape, row: .continueWatching, option: .mischung) == .landscape)
    #expect(CardLayout.tileKind(style: .poster, row: .other, option: .mischung) == .poster)
    for style in [RowStyle.top10, .hero, .logoTiles, .collectionTiles] {
        for option in LookCardShape.allCases {
            #expect(CardLayout.tileKind(style: style, row: .other, option: option) == PosterSize.kind(for: style))
        }
    }
    #expect(HomeRowKind(isContinueWatching: true) == .continueWatching)
    #expect(HomeRowKind(isContinueWatching: false) == .other)
}

@Test func cardFrameFollowsSizeFactorAndRoundsToPoints() {
    #expect(CardLayout.frame(shape: .landscape, size: .gross, expanded: false) == CGSize(width: 528, height: 298))
    #expect(CardLayout.frame(shape: .landscape, size: .mittel, expanded: false) == CGSize(width: 440, height: 248))
    #expect(CardLayout.frame(shape: .poster, size: .klein, expanded: false) == CGSize(width: 204, height: 306))
    #expect(CardLayout.frame(shape: .poster, size: .gross, expanded: false) == CGSize(width: 288, height: 432))
    // A landscape card does not expand.
    #expect(CardLayout.frame(shape: .landscape, size: .gross, expanded: true) == CGSize(width: 528, height: 298))
}

@Test func expandedPosterWidthIs16by9() {
    for size in LookCardSize.allCases {
        let f = CardLayout.frame(shape: .poster, size: size, expanded: true)
        let poster = CardLayout.frame(shape: .poster, size: size, expanded: false)
        #expect(f.height == poster.height)
        #expect(abs(f.width - (poster.height * 16 / 9).rounded()) < 0.001)
    }
    #expect(CardLayout.frame(shape: .poster, size: .mittel, expanded: true) == CGSize(width: 640, height: 360))
}

@Test func focusTitleModeKeepsRowHeight() {
    func height(_ t: LookCardTitles) -> CGFloat {
        CardLayout.row(kind: .landscape, home: home { $0.cardTitles = t }, badgeBand: 0, titleLine: 36)
            .rowHeight(heading: 46, headingSpacing: 12)
    }
    #expect(height(.fokus) == height(.immer))
    #expect(height(.aus) < height(.immer))
    // Title space: gap 12 plus one line; "aus" drops it for the whole row.
    let g = CardLayout.row(kind: .poster, home: home(), badgeBand: 0, titleLine: 36)
    #expect(g.titleStrip == 48)
    #expect(CardLayout.row(kind: .poster, home: home { $0.cardTitles = .aus }, badgeBand: 0, titleLine: 36).titleStrip == 0)
    // Opacity: "fokus" shows the title only on the focused card, "immer" always.
    #expect(CardLayout.titleOpacity(.fokus, focused: false) == 0)
    #expect(CardLayout.titleOpacity(.fokus, focused: true) == 1)
    #expect(CardLayout.titleOpacity(.immer, focused: false) == 1)
    #expect(CardLayout.titleOpacity(.aus, focused: true) == 0)
}

@Test func titleStripOnlyOnListCards() {
    // Hero, logo and collection tiles carry their own name; Top 10 shows its rank instead.
    #expect(CardLayout.showsTitleStrip(style: .poster))
    #expect(CardLayout.showsTitleStrip(style: .landscape))
    for style in [RowStyle.top10, .hero, .logoTiles, .collectionTiles] { #expect(!CardLayout.showsTitleStrip(style: style)) }
}

@Test func glowKeepsTodaysSystemCardRoom() {
    // With glow the system card style lifts (1.15, shadow 12): exactly the room of Build 4, so the home page's hero
    // collapse (which still measures with these factors) stays right for the default look.
    let lift = FocusHeadroom.lift(home())
    #expect(lift == FocusHeadroom.CardLift(scale: FocusHeadroom.systemCardScale, reach: FocusHeadroom.systemCardShadow,
                                           side: 8))
    let g = CardLayout.row(kind: .poster, home: home { $0.cardSize = .mittel }, badgeBand: 0, titleLine: 36)
    #expect(g.padding == FocusHeadroom.rowPadding(height: 360, scale: 1.15, shadow: 12, minimum: 32))
}

@Test func cardGapIsAtLeastTheLookSpacing() {
    // Narrow posters: the look's gap wins; wide landscape cards: the lift room wins (23.11.: never cover a neighbour).
    let poster = CardLayout.row(kind: .poster, home: home { $0.cardSize = .mittel }, badgeBand: 0, titleLine: 36)
    #expect(poster.cardGap == 32)
    let eng = CardLayout.row(kind: .poster, home: home { $0.cardSize = .mittel; $0.rowSpacing = .eng },
                             badgeBand: 0, titleLine: 36)
    #expect(eng.cardGap == FocusHeadroom.tileSpacing(width: 240, scale: 1.15, clearance: 8, minimum: 16))
    let wide = CardLayout.row(kind: .landscape, home: home(), badgeBand: 0, titleLine: 36)
    #expect(wide.cardGap == FocusHeadroom.tileSpacing(width: 528, scale: 1.15, clearance: 8, minimum: 32))
    #expect(CardLayout.rowGap(.eng) == 36 && CardLayout.rowGap(.normal) == 48 && CardLayout.rowGap(.luftig) == 64)
}

@Test func expandPostersOffUnderReduceMotion() {
    var v = LookPreset.values(.appleTV)
    v.home.expandPosters = true
    #expect(CardLayout.expands(v, reduceMotion: false))
    #expect(!CardLayout.expands(v, reduceMotion: true))
    v.home.expandPosters = false
    #expect(!CardLayout.expands(v, reduceMotion: false))
}

@Test func cardAccessibilityValueNamesYearProgressAndWatched() {
    #expect(CardLayout.accessibilityValue(year: "2024", fraction: 0.42, watched: false) == "2024, 42 % gesehen")
    #expect(CardLayout.accessibilityValue(year: nil, fraction: nil, watched: true) == "gesehen")
    #expect(CardLayout.accessibilityValue(year: "2019", fraction: 0, watched: false) == "2019")
    #expect(CardLayout.accessibilityValue(year: " ", fraction: nil, watched: false) == "")
}

// MARK: Focus room, 3 scales × 3 sizes (9): a lifted card never reaches into the neighbouring row or card.

private struct LiftCase: CustomTestStringConvertible, Sendable {
    let scale: LookFocusScale
    let size: LookCardSize
    var testDescription: String { "\(scale.rawValue)/\(size.rawValue)" }
}

private let liftCases: [LiftCase] = LookFocusScale.allCases.flatMap { s in
    LookCardSize.allCases.map { LiftCase(scale: s, size: $0) }
}

@Test(arguments: liftCases)
private func focusLiftStaysInsideItsRow(_ c: LiftCase) {
    for shape in [CardShape.poster, .landscape] {
        for shadow in LookFocusShadow.allCases {
            for border in LookFocusBorder.allCases {
                let h = home {
                    $0.focusGlow = false; $0.focusScale = c.scale; $0.cardSize = c.size
                    $0.focusShadow = shadow; $0.focusBorder = border
                }
                let kind: TileKind = shape == .poster ? .poster : .landscape
                let g = CardLayout.row(kind: kind, home: h, badgeBand: 42, titleLine: 36)
                let lift = FocusHeadroom.lift(h)
                // Vertical: the lifted card (picture + badge band) stays inside its row's padding, above and below
                // (the title strip moves down by the same growth and ends inside the padding too).
                let card = g.tile.height + g.below
                let extent = FocusHeadroom.liftedExtent(minY: 0, maxY: card, scale: lift.scale, shadow: lift.reach)
                #expect(extent.lowerBound >= -g.padding - 0.001, "\(shape) \(shadow) \(border) top")
                #expect(extent.upperBound + g.titleStrip <= card + g.titleStrip + g.padding + 0.001,
                        "\(shape) \(shadow) \(border) bottom")
                #expect(g.titleShift + g.titleStrip <= g.titleStrip + g.padding + 0.001)
                // Horizontal: the focused card grows sideways by less than the gap to its neighbour.
                let grow = g.tile.width * max(0, lift.scale - 1) / 2 + lift.side
                #expect(grow <= g.cardGap + 0.001, "\(shape) \(shadow) \(border) side")
            }
        }
    }
}
