import Foundation
import Testing
@testable import PlayerCore

// MARK: Collapsing hero info (Build 4 follow-up 2, P2: row cut off at the bottom)

/// Lift tokens of the system card style (`Theme.Focus.cardLiftScale` / `cardLiftShadow`).
private let lift: CGFloat = 1.15
private let shadow: CGFloat = 12
/// Compact info of the app: inset 12 above the logo, logo 80…140, gap 20, meta line 30.
private let info = HeroInfoCollapse.CompactInfo(topInset: 12, logoMax: 140, logoMin: 80, spacing: 20, metaLine: 30)

@Test func rowHeightMatchesTheDeviceLog() {
    // Device log 25.11.: card size large (1.2), no quality strip, heading line 46 (title3 38 pt), gap 12.
    // Poster row "Reihe 1283…1863" = 580, collection row "Reihe 4273…4705" = 432.
    let poster = HeroInfoCollapse.rowHeight(.poster, cardScale: 1.2, posterExtra: 0, heading: 46, headingSpacing: 12,
                                            liftScale: lift, shadow: shadow, minimumPadding: 32 * 1.2)
    #expect(poster == 580)
    let landscape = HeroInfoCollapse.rowHeight(.landscape, cardScale: 1.2, posterExtra: 0, heading: 46, headingSpacing: 12,
                                               liftScale: lift, shadow: shadow, minimumPadding: 32 * 1.2)
    #expect(abs(landscape - 432.4) < 0.001)
}

@Test func tallestRowTakesTheTallestKindAndTheQualityStrip() {
    let kinds: [TileKind] = [.landscape, .poster, .logo]
    let plain = HeroInfoCollapse.tallestRow(kinds, cardScale: 1.2, posterExtra: 0, heading: 46, headingSpacing: 12,
                                            liftScale: lift, shadow: shadow, minimumPadding: 32 * 1.2)
    #expect(plain == 580)
    // Quality strip below the poster (26 + 2·8 = 42): tile 474, padding 48 → 46 + 12 + 474 + 96.
    let strip = HeroInfoCollapse.tallestRow(kinds, cardScale: 1.2, posterExtra: 42, heading: 46, headingSpacing: 12,
                                            liftScale: lift, shadow: shadow, minimumPadding: 32 * 1.2)
    #expect(strip == 628)
    // Medium cards: 46 + 12 + 360 + 2·39.
    let medium = HeroInfoCollapse.tallestRow(kinds, cardScale: 1, posterExtra: 0, heading: 46, headingSpacing: 12,
                                             liftScale: lift, shadow: shadow, minimumPadding: 32)
    #expect(medium == 496)
    #expect(HeroInfoCollapse.tallestRow([], cardScale: 1, posterExtra: 0, heading: 46, headingSpacing: 12,
                                        liftScale: lift, shadow: shadow, minimumPadding: 32) == 0)
}

@Test func heroStyleRowHasNoHeading() {
    // `HomeRowView` draws no title above a hero-style row: 620 + 2·59, independent of the card size.
    let hero = HeroInfoCollapse.rowHeight(.hero, cardScale: 1.2, posterExtra: 42, heading: 46, headingSpacing: 12,
                                          liftScale: lift, shadow: shadow, minimumPadding: 32 * 1.2)
    #expect(hero == 738)
}

@Test func collapsedListFitsTheTallestRowOnTheDevice() {
    // Device: page top 157 (safe area + tab bar), room below the list 45, band above it 45 + 24.
    // Fix round (review M1): 4 pt slack below the row, 878 − 580 − 4 = 294.
    let l = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 45, rowHeight: 580, expandedTop: 470,
                                    edgeBand: 69, info: info)
    #expect(HeroInfoCollapse.fitSlack == 4)
    #expect(l.listBottom == 878)
    #expect(l.collapsedTop == 294)
    #expect(l.collapsedTop + l.rowHeight + HeroInfoCollapse.fitSlack <= l.listBottom)
    #expect(l.fits)
    // Enough room: the compact info keeps the full logo height.
    #expect(l.compactLogo == 140)
    #expect(l.top(collapsed: false) == 470)
    #expect(l.top(collapsed: true) == 294)
}

@Test func slackLeavesRoomBelowTheRowAndZeroSlackFitsExactly() {
    // Review M1: without slack the row ended exactly at the visible bottom (455 + 580 = 1035 in the window).
    let exact = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 45, rowHeight: 580,
                                        expandedTop: 470, edgeBand: 69, info: info, slack: 0)
    #expect(exact.collapsedTop == 298)
    #expect(exact.fits)
    // The floor (69 + 12 + 80 + 20 + 30 = 211) wins over 878 − 665 − 4 = 209: only 2 pt are left below the row,
    // but the row itself still fits, so `fits` stays true.
    let tight = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 45, rowHeight: 665,
                                        expandedTop: 470, edgeBand: 69, info: info)
    #expect(tight.floor == 211)
    #expect(tight.collapsedTop == 211)
    #expect(tight.fits)
}

@Test func floorAboveTheExpandedTopKeepsTheExpandedTop() {
    // Review M3: the collapsed top never goes below the expanded top; the floor applies only up to it.
    let l = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 45, rowHeight: 580, expandedTop: 200,
                                    edgeBand: 69, info: info)
    #expect(l.floor == 211)
    #expect(l.collapsedTop == 200)
    #expect(l.compactLogo == 80)
}

@Test func collapsedTopIsWholePointsAndNeverTooLow() {
    // Heading line 45.6: row 579.6 → 878 − 579.6 − 4 = 294.4 is rounded down, so the row still fits.
    let l = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 45, rowHeight: 579.6, expandedTop: 470,
                                    edgeBand: 69, info: info)
    #expect(l.collapsedTop == 294)
    #expect(l.fits)
}

@Test func qualityStripShrinksTheCompactLogo() {
    // Large cards with the strip below the posters: row 628, room 48, band 48 + 24.
    let l = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 48, rowHeight: 628, expandedTop: 470,
                                    edgeBand: 72, info: info)
    #expect(l.collapsedTop == 243)
    #expect(l.fits)
    // 875 − 628 − 4 = 243; 243 − band 72 − (12 + 20 + 30) = 109.
    #expect(l.compactLogo == 109)
}

@Test func smallRowsNeverMoveTheListDown() {
    let l = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 35, rowHeight: 300, expandedTop: 470,
                                    edgeBand: 59, info: info)
    #expect(l.collapsedTop == 470)
    #expect(l.fits)
    #expect(l.compactLogo == 140)
}

@Test func floorKeepsRoomForTheCompactInfo() {
    // Hero-style row (738) does not fit below the compact info: the floor (band + 12 + 80 + 20 + 30) wins.
    let l = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 59, rowHeight: 738, expandedTop: 470,
                                    edgeBand: 83, info: info)
    #expect(l.floor == 225)
    #expect(l.collapsedTop == 225)
    #expect(!l.fits)
    #expect(l.compactLogo == 80)
}

@Test func collapseLogLinesInWindowCoordinates() {
    let l = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 45, rowHeight: 579.6, expandedTop: 470,
                                    edgeBand: 69, info: info)
    #expect(HeroInfoCollapse.line(collapsed: true, layout: l) == "Info eingeklappt: Liste 451…1035, höchste Reihe 580")
    #expect(HeroInfoCollapse.line(collapsed: false, layout: l) == "Info ausgeklappt: Liste 627…1035, höchste Reihe 580")
    let tight = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 59, rowHeight: 738, expandedTop: 470,
                                        edgeBand: 83, info: info)
    #expect(HeroInfoCollapse.line(collapsed: true, layout: tight)
        == "Info eingeklappt: Liste 382…1021, höchste Reihe 738 (passt nicht, Untergrenze der Info)")
}
