import Foundation
import Testing
@testable import PlayerCore

// MARK: Collapsing hero info (Build 4 follow-up 2, P2: row cut off at the bottom)

/// Lift tokens of the system card style (`Theme.Focus.cardLiftScale` / `cardLiftShadow`).
private let lift: CGFloat = 1.15
private let shadow: CGFloat = 12
/// Collapsed info of the app (device test 1, user decision: everything stays): inset 12 above the logo, logo 80…100,
/// gaps 12, meta line 30, ratings 34, overview 2 × 37.5. Without the logo: 12 + 3·12 + 30 + 34 + 75 = 187.
private let info = HeroInfoCollapse.CompactInfo(topInset: 12, logoMax: 100, logoMin: 80, spacing: 12, metaLine: 30,
                                                ratings: 34, overview: 75)

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
    // Device: page top 157 (safe area + tab bar), room below the list 45.
    // Fix round (review M1): 4 pt slack below the row, 878 − 580 − 4 = 294.
    let l = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 45, rowHeight: 580, expandedTop: 470,
                                    info: info)
    #expect(HeroInfoCollapse.fitSlack == 4)
    #expect(l.listBottom == 878)
    #expect(l.collapsedTop == 294)
    #expect(l.collapsedTop + l.rowHeight + HeroInfoCollapse.fitSlack <= l.listBottom)
    #expect(l.fits)
    // Device test 1: the whole info (12 + 100 + 3·12 + 30 + 34 + 75 = 287) fits above the list top 294 with the
    // collapsed logo of 100 (294 − 187 = 107 would allow more; 100 is its largest).
    #expect(l.floor == 267)
    #expect(l.compactLogo == 100)
    #expect(info.height(logo: l.compactLogo) <= l.collapsedTop)
    #expect(l.top(collapsed: false) == 470)
    #expect(l.top(collapsed: true) == 294)
    #expect(l.overviewLines == 2)   // the two-line overview fits
}

@Test func collapsedInfoKeepsRatingsAndOverview() {
    // User decision (device test 1): ratings and the two-line overview stay in the collapsed info while they fit.
    #expect(info.height(logo: 0) == 187)
    #expect(info.height(logo: 100) == 287)
    // A fractional overview (two callout lines) still gives a whole-point floor that leaves room for all of it:
    // 12 + 80 + 36 + 30 + 34 + 74.3 = 266.3 → 267 (row 600: 878 − 600 − 4 = 274 leaves room for it).
    let fine = HeroInfoCollapse.CompactInfo(topInset: 12, logoMax: 100, logoMin: 80, spacing: 12, metaLine: 30,
                                            ratings: 34, overview: 74.3)
    let l = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 45, rowHeight: 600, expandedTop: 470,
                                    info: fine)
    #expect(l.floor == 267)
    #expect(l.overviewLines == 2)
    #expect(fine.height(logo: fine.logoMin) <= l.floor)
    // Row 700 (878 − 700 − 4 = 174): one line, 12 + 80 + 36 + 30 + 34 + 37.15 = 229.15 → 230; ratings stay.
    let one = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 45, rowHeight: 700, expandedTop: 470,
                                      info: fine)
    #expect(one.overviewLines == 1)
    #expect(one.floor == 230)
    #expect(fine.oneLineOverview.height(logo: fine.logoMin) <= one.floor)
    #expect(fine.oneLineOverview.ratings == 34 && fine.oneLineOverview.overview == 37.15)
}

@Test func tallerRowShrinksTheCollapsedLogoTowardsItsMinimum() {
    // 878 − 594 − 4 = 280: the logo gets 280 − 187 = 93, above the minimum 80.
    let l = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 45, rowHeight: 594, expandedTop: 470,
                                    info: info)
    #expect(l.collapsedTop == 280)
    #expect(l.fits)
    #expect(l.compactLogo == 93)
}

@Test func slackLeavesRoomBelowTheRowAndZeroSlackFitsExactly() {
    // Review M1: without slack the row ended exactly at the visible bottom (455 + 580 = 1035 in the window).
    let exact = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 45, rowHeight: 580,
                                        expandedTop: 470, info: info, slack: 0)
    #expect(exact.collapsedTop == 298)
    #expect(exact.fits)
    // The two-line floor (12 + 80 + 3·12 + 30 + 34 + 75 = 267) is above 878 − 609 − 4 = 265: since 26.11. the
    // overview gets one line (floor 230), the list top is 265 with the full slack and the logo keeps 100.
    let tight = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 45, rowHeight: 609,
                                        expandedTop: 470, info: info)
    #expect(tight.overviewLines == 1)
    #expect(tight.floor == 230)
    #expect(tight.collapsedTop == 265)
    #expect(tight.fits)
    #expect(tight.compactLogo == 100)
}

@Test func floorAboveTheExpandedTopKeepsTheExpandedTop() {
    // Review M3: the collapsed top never goes below the expanded top; the floor applies only up to it.
    let l = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 45, rowHeight: 580, expandedTop: 200,
                                    info: info)
    #expect(l.floor == 267)
    #expect(l.collapsedTop == 200)
    #expect(l.compactLogo == 80)
}

@Test func collapsedTopIsWholePointsAndNeverTooLow() {
    // Heading line 45.6: row 579.6 → 878 − 579.6 − 4 = 294.4 is rounded down, so the row still fits.
    let l = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 45, rowHeight: 579.6, expandedTop: 470,
                                    info: info)
    #expect(l.collapsedTop == 294)
    #expect(l.fits)
}

@Test func qualityStripShortensTheOverviewToOneLine() {
    // Large cards with the strip below the posters: row 628, room 48. 875 − 628 − 4 = 243 fits the row, but the
    // two-line info needs 267 even with the 80 pt logo (Build 5 cut the row's bottom 20 pt). User decision 26.11.:
    // the overview drops to one line (12 + 80 + 36 + 30 + 34 + 37.5 = 229.5 → floor 230), the list top is 243 and
    // the logo gets 243 − 149.5 = 93.5 → 93, close to its 100.
    let l = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 48, rowHeight: 628, expandedTop: 470,
                                    info: info)
    #expect(l.overviewLines == 1)
    #expect(l.floor == 230)
    #expect(l.collapsedTop == 243)
    #expect(l.fits)
    #expect(l.compactLogo == 93)
    #expect(info.oneLineOverview.height(logo: l.compactLogo) <= l.collapsedTop)
    #expect(HeroInfoCollapse.line(collapsed: true, layout: l)
        == "Info eingeklappt: Liste 400…1032, höchste Reihe 628, Logo 93, Beschreibung 1 Zeile")
    // Without an overview nothing can shorten: the floor stays that of the full info.
    var bare = info; bare.overview = 0
    let b = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 48, rowHeight: 700, expandedTop: 470,
                                    info: bare)
    #expect(b.overviewLines == 2)
    #expect(b.floor == 192)   // 12 + 80 + 36 + 30 + 34
}

@Test func smallRowsNeverMoveTheListDown() {
    let l = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 35, rowHeight: 300, expandedTop: 470,
                                    info: info)
    #expect(l.collapsedTop == 470)
    #expect(l.fits)
    #expect(l.compactLogo == 100)
}

@Test func floorKeepsRoomForTheCollapsedInfo() {
    // Hero-style row (738) does not fit below the collapsed info even with a one-line overview: the floor
    // (12 + 80 + 36 + 30 + 34 + 37.5 = 229.5 → 230) wins.
    let l = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 59, rowHeight: 738, expandedTop: 470,
                                    info: info)
    #expect(l.overviewLines == 1)
    #expect(l.floor == 230)
    #expect(l.collapsedTop == 230)
    #expect(!l.fits)
    #expect(l.compactLogo == 80)
}

@Test func collapseLogLinesInWindowCoordinates() {
    let l = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 45, rowHeight: 579.6, expandedTop: 470,
                                    info: info)
    #expect(HeroInfoCollapse.line(collapsed: true, layout: l) == "Info eingeklappt: Liste 451…1035, höchste Reihe 580, Logo 100")
    #expect(HeroInfoCollapse.line(collapsed: false, layout: l) == "Info ausgeklappt: Liste 627…1035, höchste Reihe 580")
    let tight = HeroInfoCollapse.layout(screenHeight: 1080, pageTop: 157, bottomRoom: 59, rowHeight: 738, expandedTop: 470,
                                        info: info)
    #expect(HeroInfoCollapse.line(collapsed: true, layout: tight)
        == "Info eingeklappt: Liste 387…1021, höchste Reihe 738, Logo 80, Beschreibung 1 Zeile (passt nicht, Untergrenze der Info)")
}
