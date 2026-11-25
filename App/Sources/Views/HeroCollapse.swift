import SwiftUI
import UIKit
import PlayerCore

/// P2 (Build 4 follow-up 2): collapsing hero info, Apple TV app style. With the focus on the hero buttons (or at the
/// page top) the layout is as before. While the focus is in the rows (`HomeFocus.inRows`) the info shows only the
/// logo (or title) and the meta line, and the list top moves up so the page's tallest row fits between the list's
/// top and its visible bottom (PlayerCore `HeroInfoCollapse`). The list frame (`HeroListFrame`) and the info
/// (`HeroLayer`) read this one object, so both change in the same animated transaction.
@MainActor @Observable final class HeroCollapse {
    /// Applied state (changed with the theme's expand animation by `HeroListFrame`).
    fileprivate(set) var collapsed = false
    /// Logo (or title) height of the collapsed info, from the current layout.
    fileprivate(set) var compactLogo: CGFloat = HeroMetrics.logoHeight
    /// The button below the rows ("Reihen & Collections") holds the focus. F-A-12 ends `inRows` there after 300 ms;
    /// expanding then would shrink the list from the top and push the focused button below its bottom, so the info
    /// stays collapsed while the focus is there (it is not at the page top either).
    var belowRows = false

    /// Height of one heading line of the home rows (`Theme.TextRole.sectionTitle` in the theme's type), from the
    /// UIKit metrics of the same font: today's style is `title3`, the plan's type scale a system font of its size.
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

/// P2: frame of the hero home list. Top: expanded `HeroMetrics.listTop`, collapsed from `HeroInfoCollapse` (tallest
/// row, measured page top, lift band above, room below). Bottom: the lift room of wave F-m, unchanged.
/// The heading snap (`HeadingSnap`) works in list content coordinates (row top against the scroll offset), so it
/// follows the new list top by itself; its first check (0.4 s) runs after the collapse animation (≤ 0.3 s).
struct HeroListFrame: ViewModifier {
    let focus: HomeFocus
    let collapse: HeroCollapse
    /// Tile kinds of the rows, card size factor and quality strip below posters (as `listEdgeBand`).
    let kinds: [TileKind]
    let cardScale: CGFloat
    let posterStrip: CGFloat
    /// Room below the list (`listBottomRoom`) and lift band above it (`listEdgeBand`).
    let bottomRoom: CGFloat
    let edgeBand: CGFloat
    @Environment(\.theme) private var theme
    /// Top of the page in the window (safe area and tab bar; device log: 157).
    @State private var pageTop: CGFloat = 0

    func body(content: Content) -> some View {
        let layout = currentLayout
        let wanted = focus.inRows || collapse.belowRows
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
            .onChange(of: wanted, initial: true) { _, c in apply(c, layout: layout) }
    }

    private var currentLayout: HeroInfoCollapse.Layout {
        let row = HeroInfoCollapse.tallestRow(kinds, cardScale: cardScale, posterExtra: posterStrip,
                                              heading: HeroCollapse.headingLine(theme.type),
                                              headingSpacing: Theme.Space.s, liftScale: Theme.Focus.cardLiftScale,
                                              shadow: Theme.Focus.cardLiftShadow, minimumPadding: Theme.Space.l * cardScale)
        return HeroInfoCollapse.layout(screenHeight: Theme.Screen.bounds.height, pageTop: pageTop,
                                       bottomRoom: bottomRoom, rowHeight: row, expandedTop: HeroMetrics.listTop,
                                       edgeBand: edgeBand, info: HeroMetrics.compactInfo)
    }

    /// One `nav` line per change: "Info eingeklappt|ausgeklappt: Liste <top>…<bottom>, höchste Reihe <h>".
    private func apply(_ c: Bool, layout: HeroInfoCollapse.Layout) {
        guard c != collapse.collapsed else { return }
        // Theme motion "expand" (standard 0.3 s, dezent 0.25 s; 0 = motion off or reduced: no animation).
        let d: Double = theme.motion.expand
        let animation: Animation? = d > 0 ? Animation.easeInOut(duration: d) : nil
        withAnimation(animation) { collapse.collapsed = c }
        RemoteLog.info("nav", HeroInfoCollapse.line(collapsed: c, layout: layout))
    }
}
