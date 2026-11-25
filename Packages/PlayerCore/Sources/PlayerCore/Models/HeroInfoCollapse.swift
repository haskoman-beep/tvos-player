import Foundation

// P2 (Build 4 follow-up 2): on the home page with hero the list starts below the hero info (page top + 470). A poster
// row (heading, tile, lift room) is taller than the list's visible height there, so with its heading at the list's
// top edge the row's bottom was off screen (device log 25.11.: list 627…1035, row 580 pt). Like the Apple TV app,
// the info collapses while the focus is in the rows (logo or title + meta line) and the list top moves up so the
// tallest row fits between the list's top and its visible bottom. Pure maths; the tokens come from the app.

public enum HeroInfoCollapse {
    /// The compact info, top to bottom (points): inset above the logo, logo (or title), gap, meta line.
    public struct CompactInfo: Hashable, Sendable {
        public var topInset: CGFloat
        /// Logo height of the full info; the compact logo never grows past it.
        public var logoMax: CGFloat
        /// Smallest compact logo (sets the floor of the collapsed list top).
        public var logoMin: CGFloat
        public var spacing: CGFloat
        public var metaLine: CGFloat

        public init(topInset: CGFloat, logoMax: CGFloat, logoMin: CGFloat, spacing: CGFloat, metaLine: CGFloat) {
            self.topInset = topInset
            self.logoMax = logoMax
            self.logoMin = min(logoMin, logoMax)
            self.spacing = spacing
            self.metaLine = metaLine
        }

        /// Height of the compact info with a logo of `logo` points.
        func height(logo: CGFloat) -> CGFloat { max(0, topInset) + max(0, logo) + max(0, spacing) + max(0, metaLine) }
    }

    /// Height of one home row of tiles of `kind`: heading line and gap above the tile row, the tile (plus the quality
    /// strip below a poster), and the lift padding above and below it (`FocusHeadroom.rowPadding`, at least
    /// `minimumPadding`, as `Strip` draws it). A hero-style row has no heading (`HomeRowView`).
    public static func rowHeight(_ kind: TileKind, cardScale: CGFloat, posterExtra: CGFloat, heading: CGFloat,
                                 headingSpacing: CGFloat, liftScale: CGFloat, shadow: CGFloat,
                                 minimumPadding: CGFloat) -> CGFloat {
        let tile = FocusHeadroom.tallest([kind], cardScale: cardScale, posterExtra: posterExtra)
        let pad = FocusHeadroom.rowPadding(height: tile, scale: liftScale, shadow: shadow, minimum: minimumPadding)
        let head = kind == .hero ? 0 : max(0, heading) + max(0, headingSpacing)
        return head + tile + 2 * pad
    }

    /// Height of the tallest row among `kinds` (0 without rows).
    public static func tallestRow(_ kinds: [TileKind], cardScale: CGFloat, posterExtra: CGFloat, heading: CGFloat,
                                  headingSpacing: CGFloat, liftScale: CGFloat, shadow: CGFloat,
                                  minimumPadding: CGFloat) -> CGFloat {
        Set(kinds).reduce(0) { h, kind in
            max(h, rowHeight(kind, cardScale: cardScale, posterExtra: posterExtra, heading: heading,
                             headingSpacing: headingSpacing, liftScale: liftScale, shadow: shadow,
                             minimumPadding: minimumPadding))
        }
    }

    /// List tops of both states in page coordinates (below the page's top: safe area and tab bar).
    public struct Layout: Hashable, Sendable {
        /// List top with the full info (today's `HeroMetrics.listTop`).
        public var expandedTop: CGFloat
        /// List top while the info is collapsed.
        public var collapsedTop: CGFloat
        /// Lowest collapsed top: room for the compact info with its smallest logo plus the lift band above the list.
        public var floor: CGFloat
        /// Logo (or title) height of the compact info.
        public var compactLogo: CGFloat
        /// Tallest row of the page.
        public var rowHeight: CGFloat
        /// Visible bottom of the list (screen bottom minus the room below the list), page coordinates.
        public var listBottom: CGFloat
        /// The page's top in the window (for log lines in window coordinates, like the `nav` heading lines).
        public var pageTop: CGFloat

        /// The tallest row fits between the collapsed top and the list's visible bottom (false: the floor won).
        /// The slack is not part of this check: a row that fits with less than the slack still fits.
        public var fits: Bool { collapsedTop + rowHeight <= listBottom + 0.001 }

        public func top(collapsed: Bool) -> CGFloat { collapsed ? collapsedTop : expandedTop }
    }

    /// Review M1 (fix round): room left below the tallest row in the collapsed list, so a few points the model
    /// misses (rounded text metrics, a heading font a little taller than measured) do not cut the row again.
    public static let fitSlack: CGFloat = 4

    /// `screenHeight`: window height; `pageTop`: the page's top in the window; `bottomRoom`: room between the list and
    /// the screen bottom (`FocusHeadroom.listBottomRoom`); `edgeBand`: band above the list top where a lifted card
    /// draws (`FocusHeadroom.edgeBand`), kept clear of the info; `slack`: room kept below the row.
    /// `collapsedTop = min(expandedTop, max(floor, needed))`, with `needed` the top that leaves the tallest row plus
    /// `slack` above the list bottom (whole points, rounded so the row fits). The collapsed top is never a larger y
    /// than the expanded top, so the floor (room for the compact info) holds only while it is smaller than the
    /// expanded top; above that the expanded top wins and the compact logo is clamped to `logoMin`. When the floor
    /// wins over `needed`, the row may not fit (`fits` false).
    public static func layout(screenHeight: CGFloat, pageTop: CGFloat, bottomRoom: CGFloat, rowHeight: CGFloat,
                              expandedTop: CGFloat, edgeBand: CGFloat, info: CompactInfo,
                              slack: CGFloat = fitSlack) -> Layout {
        let page = max(0, pageTop)
        let listBottom = max(0, screenHeight - page - max(0, bottomRoom))
        let row = max(0, rowHeight)
        let band = max(0, edgeBand)
        let needed = (listBottom - row - max(0, slack)).rounded(.down)
        let floor = (band + info.height(logo: info.logoMin)).rounded(.up)
        let top = min(expandedTop, max(floor, needed))
        let logo = min(info.logoMax, max(info.logoMin, top - band - info.height(logo: 0)))
        return Layout(expandedTop: expandedTop, collapsedTop: top, floor: floor, compactLogo: logo.rounded(.down),
                      rowHeight: row, listBottom: listBottom, pageTop: page)
    }

    /// `nav` line per collapse / expand: "Info eingeklappt: Liste 455…1035, höchste Reihe 580" (window coordinates:
    /// list top … visible list bottom, as the heading lines print the list frame).
    public static func line(collapsed: Bool, layout l: Layout) -> String {
        let top = l.pageTop + l.top(collapsed: collapsed)
        let bottom = l.pageTop + l.listBottom
        let state = collapsed ? "eingeklappt" : "ausgeklappt"
        let tight = collapsed && !l.fits ? " (passt nicht, Untergrenze der Info)" : ""
        return "Info \(state): Liste \(pt(top))…\(pt(bottom)), höchste Reihe \(pt(l.rowHeight))\(tight)"
    }

    private static func pt(_ v: CGFloat) -> String { "\(Int(v.rounded()))" }
}
