import Foundation

// P2 (Build 4 follow-up 2): on the home page with hero the list starts below the hero info (page top + 470). A poster
// row (heading, tile, lift room) is taller than the list's visible height there, so with its heading at the list's
// top edge the row's bottom was off screen (device log 25.11.: list 627…1035, row 580 pt). Like the Apple TV app,
// the info collapses while the focus is in the rows and the list top moves up so the tallest row fits between the
// list's top and its visible bottom. Device test 1 (user decision): the collapsed info keeps everything (logo, meta
// line, ratings, two-line overview), only moved up and more compact (smaller logo, tighter gaps), and it may reach
// down to the collapsed list top. Pure maths; the tokens come from the app.

public enum HeroInfoCollapse {
    /// The collapsed info, top to bottom (points): inset above the logo, logo (or title), meta line, ratings and the
    /// two-line overview, with `spacing` between each of the four.
    public struct CompactInfo: Hashable, Sendable {
        public var topInset: CGFloat
        /// Logo height of the collapsed info when there is room (it never grows past it).
        public var logoMax: CGFloat
        /// Smallest collapsed logo (sets the floor of the collapsed list top); ratings and overview never go.
        public var logoMin: CGFloat
        /// Gap between logo, meta line, ratings and overview.
        public var spacing: CGFloat
        public var metaLine: CGFloat
        /// Ratings line (`InfoBadges`).
        public var ratings: CGFloat
        /// Overview, two lines of its font.
        public var overview: CGFloat
        /// Task 5.2: number of gaps below the logo (one per shown part; Build 4: meta, ratings, overview = 3).
        public var gaps: Int
        /// Task 5.2: quality badge line (`heroInfo` ausführlich), 0 when not shown.
        public var badges: CGFloat
        /// Task 5.2: room below the info inside the hero (banner / carousel card inset and gap to the list).
        public var bottomInset: CGFloat

        public init(topInset: CGFloat, logoMax: CGFloat, logoMin: CGFloat, spacing: CGFloat, metaLine: CGFloat,
                    ratings: CGFloat, overview: CGFloat, gaps: Int = 3, badges: CGFloat = 0,
                    bottomInset: CGFloat = 0) {
            self.gaps = max(0, gaps)
            self.badges = badges
            self.bottomInset = bottomInset
            self.topInset = topInset
            self.logoMax = logoMax
            self.logoMin = min(logoMin, logoMax)
            self.spacing = spacing
            self.metaLine = metaLine
            self.ratings = ratings
            self.overview = overview
        }

        /// Height of the collapsed info with a logo of `logo` points.
        func height(logo: CGFloat) -> CGFloat {
            let parts = max(0, metaLine) + max(0, ratings) + max(0, overview) + max(0, badges)
            return max(0, topInset) + max(0, logo) + CGFloat(gaps) * max(0, spacing) + parts + max(0, bottomInset)
        }
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
        /// Lowest collapsed top: room for the collapsed info with its smallest logo.
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
    /// the screen bottom (`FocusHeadroom.listBottomRoom`); `slack`: room kept below the row.
    /// `collapsedTop = min(expandedTop, max(floor, needed))`, with `needed` the top that leaves the tallest row plus
    /// `slack` above the list bottom (whole points, rounded so the row fits). The collapsed info fills the room above
    /// the collapsed top (device test 1: the list's edge band is not kept clear of it any more; with the row at the
    /// list top the band holds only the row gap and the lift room of the row above). The collapsed top is never a
    /// larger y than the expanded top, so the floor (room for the collapsed info with `logoMin`) holds only while it
    /// is smaller than the expanded top; above that the expanded top wins and the logo is clamped to `logoMin`. When
    /// the floor wins over `needed`, the row may not fit (`fits` false).
    public static func layout(screenHeight: CGFloat, pageTop: CGFloat, bottomRoom: CGFloat, rowHeight: CGFloat,
                              expandedTop: CGFloat, info: CompactInfo, slack: CGFloat = fitSlack) -> Layout {
        let page = max(0, pageTop)
        let listBottom = max(0, screenHeight - page - max(0, bottomRoom))
        let row = max(0, rowHeight)
        let needed = (listBottom - row - max(0, slack)).rounded(.down)
        let floor = info.height(logo: info.logoMin).rounded(.up)
        let top = min(expandedTop, max(floor, needed))
        let logo = min(info.logoMax, max(info.logoMin, top - info.height(logo: 0)))
        return Layout(expandedTop: expandedTop, collapsedTop: top, floor: floor, compactLogo: logo.rounded(.down),
                      rowHeight: row, listBottom: listBottom, pageTop: page)
    }

    /// `nav` line per collapse / expand: "Info eingeklappt: Liste 451…1035, höchste Reihe 580, Logo 100" (window
    /// coordinates: list top … visible list bottom, as the heading lines print the list frame; the collapsed logo
    /// height only when collapsed).
    public static func line(collapsed: Bool, layout l: Layout) -> String {
        let top = l.pageTop + l.top(collapsed: collapsed)
        let bottom = l.pageTop + l.listBottom
        let state = collapsed ? "eingeklappt" : "ausgeklappt"
        let logo = collapsed ? ", Logo \(pt(l.compactLogo))" : ""
        let tight = collapsed && !l.fits ? " (passt nicht, Untergrenze der Info)" : ""
        return "Info \(state): Liste \(pt(top))…\(pt(bottom)), höchste Reihe \(pt(l.rowHeight))\(logo)\(tight)"
    }

    private static func pt(_ v: CGFloat) -> String { "\(Int(v.rounded()))" }
}
