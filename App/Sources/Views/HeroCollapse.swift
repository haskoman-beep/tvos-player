import SwiftUI
import UIKit
import PlayerCore

/// P2 (Build 4 follow-up 2): collapsing hero info, Apple TV app style. With the focus on the hero buttons (the top
/// edge of the page) the layout is as before. Once the focus enters a row (`HomeFocus.inRows` turns true: card,
/// placeholder, status tile) the info moves up and gets more compact (device test 1, user decision: logo about 100
/// instead of 140, tighter gaps; meta line, ratings and overview stay), and the list top moves up so the page's
/// tallest row fits between the list's top and its visible bottom (PlayerCore `HeroInfoCollapse`).
/// The list frame (`HeroListFrame`) and the info (`HeroLayout`) read this one object, so both change in the same
/// animated transaction.
/// Fix round (user decision 25.11., review M2): the collapse is a latch. It does not follow the F-A-12 rest check:
/// leaving the rows for the tab bar, the sidebar or the button below the rows keeps it collapsed; only the hero
/// buttons expand it. Slideshow and backdrop keep following `inRows` as before.
@MainActor @Observable final class HeroCollapse {
    /// Applied state (changed with the theme's expand animation by `HeroListFrame`).
    fileprivate(set) var collapsed = false
    /// Logo (or title) height of the collapsed info, from the current layout.
    fileprivate(set) var compactLogo: CGFloat = HeroMetrics.compactLogoHeight
    /// Task 5.2: list top of the collapsed state (banner and carousel end their card above it).
    fileprivate(set) var collapsedTop: CGFloat = HeroMetrics.listTop
    /// The hero buttons (Abspielen/Details) hold the focus; set by `HomeView` from `HeroButtons`. Turning true
    /// expands the info.
    var heroButtonsFocused = false

    /// Height of one heading line of the home rows (`Theme.TextRole.sectionTitle` in the theme's type), from the
    /// UIKit metrics of the same font: today's style is `title3`, the plan's type scale a system font of its size.
    /// The heading is one line (`lineLimit(1)` in `HomeRowView`).
    static func headingLine(_ type: ThemeValues.TypeScale) -> CGFloat {
        let font: UIFont
        if type.isToday {
            font = UIFont.preferredFont(forTextStyle: .title3)
        } else {
            let r = LookTheme.type(ThemeValues.TypeScale.tableRole(.sectionTitle), scale: type.scale,
                                   character: type.character)
            font = UIFont.systemFont(ofSize: r.size)
        }
        return font.lineHeight.rounded(.up)
    }
}

/// P2: frame of the hero home list. Top: expanded `HomeTopEdge.rowsTop` (Task 5.2; full screen standard 470), collapsed from `HeroInfoCollapse` (tallest
/// row, measured page top, room below). Bottom: the lift room of wave F-m, unchanged.
/// The heading snap (`HeadingSnap`) works in list content coordinates (row top against the scroll offset), so it
/// follows the new list top by itself; its first check (0.4 s) runs after the collapse animation (≤ 0.3 s).
struct HeroListFrame: ViewModifier {
    let focus: HomeFocus
    let collapse: HeroCollapse
    /// Integration build 5 (review b5a1 I1): the rows with the card options (`theme.cards.home`) and „alte Karte“,
    /// measured by `CardLayout.tallestHomeRow` (title strip, row title, lift); quality strip below posters as
    /// `listEdgeBand`.
    let rows: [HomeRow]
    let home: LookHome
    let oldCard: Bool
    let posterStrip: CGFloat
    /// Room below the list (`listBottomRoom`).
    let bottomRoom: CGFloat
    /// Task 5.2: hero style and info level (list tops and collapsed info per style, PlayerCore `HeroInfoMetrics`).
    let style: LookHeroStyle
    let level: LookHeroInfo
    @Environment(\.theme) private var theme
    /// Top of the page in the window (safe area and tab bar; device log: 157).
    @State private var pageTop: CGFloat = 0

    func body(content: Content) -> some View {
        let layout = currentLayout
        content
            .padding(.top, layout.top(collapsed: collapse.collapsed))
            // Wave F-m: build 198 photo: the list reached the screen edge, focus scrolling stopped the card's frame
            // there and its lift was cut. The list ends above the edge by that lift and draws into the room.
            .padding(.bottom, bottomRoom)
            .ignoresSafeArea(edges: .bottom)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { pageTop = $0 }
            .onChange(of: layout.compactLogo, initial: true) { _, logo in
                if collapse.compactLogo != logo { collapse.compactLogo = logo }
            }
            .onChange(of: layout.collapsedTop, initial: true) { _, top in
                if collapse.collapsedTop != top { collapse.collapsedTop = top }
            }
            // Latch: focus into a row collapses, focus on the hero buttons expands; nothing else changes it.
            .onChange(of: focus.inRows) { _, inRows in
                if inRows { apply(true, layout: layout) }
            }
            .onChange(of: collapse.heroButtonsFocused) { _, onButtons in
                if onButtons { apply(false, layout: layout) }
            }
    }

    private var currentLayout: HeroInfoCollapse.Layout {
        // „alte Karte“ draws the standard heading (`HomeRowView`), so its estimate is Build 4's.
        let size: LookRowTitle = oldCard ? .standard : home.rowTitle
        let heading: CGFloat = size == .standard ? HeroCollapse.headingLine(theme.type) : RowHeading.line(size, theme.type)
        let row = CardLayout.tallestHomeRow(rows, home: home, oldCard: oldCard, badgeBand: posterStrip,
                                            heading: heading, headingSpacing: Theme.Space.s,
                                            titleLine: CardTitleMetrics.line(theme.type))
        return HeroInfoCollapse.layout(screenHeight: Theme.Screen.bounds.height, pageTop: pageTop,
                                       bottomRoom: bottomRoom, rowHeight: row, expandedTop: expandedTop,
                                       info: HeroMetrics.infoMetrics.compactInfo(style, level: level))
    }

    /// Task 5.2: expanded list top per style and info (full screen standard: `HeroMetrics.listTop`, 470).
    private var expandedTop: CGFloat {
        HomeTopEdge.rowsTop(style: style, info: level, metrics: HeroMetrics.infoMetrics)
    }

    /// One `nav` line per change: "Info eingeklappt|ausgeklappt: Liste <top>…<bottom>, höchste Reihe <h>" (collapsed:
    /// plus ", Logo <n>").
    private func apply(_ c: Bool, layout: HeroInfoCollapse.Layout) {
        guard c != collapse.collapsed else { return }
        // Theme motion "expand" (standard 0.3 s, dezent 0.25 s; 0 = motion off or reduced: no animation).
        let d: Double = theme.motion.expand
        let animation: Animation? = d > 0 ? Animation.easeInOut(duration: d) : nil
        withAnimation(animation) { collapse.collapsed = c }
        RemoteLog.info("nav", HeroInfoCollapse.line(collapsed: c, layout: layout))
    }
}
