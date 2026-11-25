import Foundation

// Task 5.2 (F-A-4, F-A-12, D-9): the four hero styles of the home page as pure maths and rules. Points at
// 1920 × 1080 in page coordinates (below the page's top: safe area and tab bar), like `HeroInfoCollapse`. The app
// passes its measured text metrics (`HeroInfoMetrics`); `standard` holds today's tokens.

/// Parts of the hero info besides the logo (or title), per `heroInfo` level.
public struct HeroInfoParts: Hashable, Sendable {
    /// Meta line: year · runtime · certification · genre.
    public var meta: Bool
    /// Ratings line (`ratingStyle`).
    public var ratings: Bool
    /// Overview, two lines.
    public var overview: Bool
    /// Quality badges (4K, Dolby Vision, Atmos, channels) in `badgeStyle`.
    public var badges: Bool

    public init(meta: Bool, ratings: Bool, overview: Bool, badges: Bool) {
        self.meta = meta; self.ratings = ratings; self.overview = overview; self.badges = badges
    }

    /// minimal: logo and buttons; standard: plus meta line, ratings, overview; ausfuehrlich: plus badges.
    public static func of(_ level: LookHeroInfo) -> HeroInfoParts {
        switch level {
        case .minimal: HeroInfoParts(meta: false, ratings: false, overview: false, badges: false)
        case .standard: HeroInfoParts(meta: true, ratings: true, overview: true, badges: false)
        case .ausfuehrlich: HeroInfoParts(meta: true, ratings: true, overview: true, badges: true)
        }
    }

    /// The parts while the focus is in the rows (collapsed info). Full screen keeps every part of the level, only
    /// moved up and more compact (user decision 25.11.). Banner and carousel: the card shrinks to the room above the
    /// collapsed list, so it keeps logo and meta line (Task 5.2 decision: a strip like the Apple TV app's).
    public static func collapsed(_ level: LookHeroInfo, style: LookHeroStyle) -> HeroInfoParts {
        let all = of(level)
        guard HeroInfoMetrics.isCard(style) else { return all }
        return HeroInfoParts(meta: all.meta, ratings: false, overview: false, badges: false)
    }

    /// Number of parts below the logo (one gap above each).
    var count: Int { [meta, ratings, overview, badges].filter { $0 }.count }
}

/// Heights of the hero pieces (points). `standard` is today's tokens; the app replaces `overview` with the measured
/// two lines of its font.
public struct HeroInfoMetrics: Hashable, Sendable {
    /// Inset above the full-screen info (`Theme.Space.s`).
    public var topInset: CGFloat = 12
    /// Logo of the full-screen info (`HeroMetrics.logoHeight`).
    public var logo: CGFloat = 140
    /// Logo of the info inside a banner or carousel card.
    public var cardLogo: CGFloat = 100
    /// Collapsed logo when there is room, and its smallest size (`HeroMetrics.compactLogo…`).
    public var compactLogo: CGFloat = 100
    public var compactLogoMin: CGFloat = 80
    /// Gap between the info parts (`Theme.Space.m`), collapsed and in a card `Theme.Space.s`.
    public var spacing: CGFloat = 20
    public var compactSpacing: CGFloat = 12
    public var metaLine: CGFloat = 30
    /// Ratings and badge lines (`ThemeBadge.TechSize.detail`).
    public var ratings: CGFloat = 34
    public var badges: CGFloat = 34
    /// Two lines of the overview (app: `.callout` line height × 2).
    public var overview: CGFloat = 74
    /// Button row Abspielen/Details: button (`rowMinHeight` 80) plus its vertical padding (2 × 12).
    public var buttonRow: CGFloat = 104
    /// Top padding of the list content above the button row.
    public var listPadding: CGFloat = 24
    /// Full screen: list top with standard info (device-verified, `HeroMetrics.listTop`), and how much higher it
    /// starts with minimal info (plan: first row 640 instead of 700).
    public var fullscreenListTop: CGFloat = 470
    public var minimalLift: CGFloat = 60
    /// Banner and carousel card: top, smallest height (plan 460), insets of the info (plan: 56 leading, 44 bottom;
    /// 32 top), gap between card and list when collapsed.
    public var frameTop: CGFloat = 12
    public var cardMinHeight: CGFloat = 460
    public var cardInnerTop: CGFloat = 32
    public var cardInnerBottom: CGFloat = 44
    public var cardInnerLeading: CGFloat = 56
    public var frameGap: CGFloat = 20
    /// Carousel: card width 1320, gap 32 to the cut-off next title, info scaled by 0.8 at a width of 700.
    public var carouselWidth: CGFloat = 1320
    public var carouselGap: CGFloat = 32
    public var carouselInfoScale: CGFloat = 0.8

    public init() {}

    public static let standard = HeroInfoMetrics()

    /// Banner and carousel draw a card; full screen fills the screen behind the rows.
    public static func isCard(_ style: LookHeroStyle) -> Bool { style == .banner || style == .karussell }

    /// Scale of the info of `style` (carousel 0.8).
    public func infoScale(_ style: LookHeroStyle) -> CGFloat { style == .karussell ? carouselInfoScale : 1 }

    /// Height of the info with `parts`, a logo of `logo` and `gap` between the parts (unscaled).
    public func infoHeight(_ parts: HeroInfoParts, logo: CGFloat, gap: CGFloat) -> CGFloat {
        var h = max(0, logo) + CGFloat(parts.count) * max(0, gap)
        if parts.meta { h += metaLine }
        if parts.ratings { h += ratings }
        if parts.overview { h += overview }
        if parts.badges { h += badges }
        return h
    }

    /// Expanded info of `style` (logo and gap as drawn, scaled).
    public func expandedInfoHeight(_ style: LookHeroStyle, level: LookHeroInfo) -> CGFloat {
        let card = Self.isCard(style)
        let h = infoHeight(.of(level), logo: card ? cardLogo : logo, gap: card ? compactSpacing : spacing)
        return h * infoScale(style)
    }

    /// Full screen: bottom of the expanded info below the page top.
    public func infoBottom(_ style: LookHeroStyle, level: LookHeroInfo) -> CGFloat {
        topInset + expandedInfoHeight(style, level: level)
    }

    /// Height of the banner or carousel card: expanded at least `cardMinHeight` and tall enough for the info, a gap
    /// and the button row inside its bottom; collapsed (`collapsedTop` given) it ends `frameGap` above the list top,
    /// never taller than expanded. 0 for full screen and `aus`.
    public func cardHeight(_ style: LookHeroStyle, level: LookHeroInfo, collapsedTop: CGFloat?) -> CGFloat {
        guard Self.isCard(style) else { return 0 }
        let content = cardInnerTop + expandedInfoHeight(style, level: level) + spacing + buttonRow + cardInnerBottom
        let open = max(cardMinHeight, content.rounded(.up))
        guard let top = collapsedTop else { return open }
        return min(open, max(0, top - frameGap - frameTop))
    }

    /// The collapsed info of `style` as `HeroInfoCollapse` places it. Full screen standard is exactly the
    /// collapsed info of Build 4 follow-up 2; a card adds its insets and the gap to the list.
    public func compactInfo(_ style: LookHeroStyle, level: LookHeroInfo) -> HeroInfoCollapse.CompactInfo {
        let p = HeroInfoParts.collapsed(level, style: style)
        let card = Self.isCard(style)
        return HeroInfoCollapse.CompactInfo(topInset: card ? frameTop + cardInnerTop : topInset,
                                            logoMax: compactLogo, logoMin: compactLogoMin, spacing: compactSpacing,
                                            metaLine: p.meta ? metaLine : 0, ratings: p.ratings ? ratings : 0,
                                            overview: p.overview ? overview : 0, gaps: p.count,
                                            badges: p.badges ? badges : 0,
                                            bottomInset: card ? cardInnerBottom + frameGap : 0)
    }
}

extension HomeTopEdge {
    /// Where focus goes from the first row up.
    public enum AboveFirstRow: Hashable, Sendable {
        /// The hero's button row („Abspielen“, own focus section with that default).
        case heroButton
        /// The navigation (tab bar or sidebar): no hero above the rows.
        case navigation
    }

    /// Task 5.2: a hero shows when the style is not `aus` and a list row feeds it (`HomeLayout.heroSource`).
    public static func showsHero(_ style: LookHeroStyle, hasHeroSource: Bool) -> Bool {
        style != .aus && hasHeroSource
    }

    /// `topmost` for a hero style: full screen, banner and carousel put the button row on top; `aus` the first row.
    public static func topmost(heroStyle: LookHeroStyle, hasHeroSource: Bool, rowCount: Int,
                               layoutEmpty: Bool) -> HomeTopEdge {
        topmost(hasHero: showsHero(heroStyle, hasHeroSource: hasHeroSource), rowCount: rowCount,
                layoutEmpty: layoutEmpty)
    }

    public static func aboveFirstRow(heroStyle: LookHeroStyle, hasHeroSource: Bool) -> AboveFirstRow {
        showsHero(heroStyle, hasHeroSource: hasHeroSource) ? .heroButton : .navigation
    }

    /// Task 5.2: top of the home list (button row, then the rows) below the page top, per hero style and info.
    /// Full screen: 470 (device-verified) with standard and detailed info, 60 higher with minimal; never so high that
    /// the info reaches the buttons. Banner and carousel: the buttons sit in the card's bottom, so the list starts
    /// that far above the card's bottom. `aus`: 0 (no hero; the page without hero has its own list).
    public static func rowsTop(style: LookHeroStyle, info: LookHeroInfo,
                               metrics m: HeroInfoMetrics = .standard) -> CGFloat {
        switch style {
        case .aus:
            return 0
        case .vollbild:
            let base = info == .minimal ? m.fullscreenListTop - m.minimalLift : m.fullscreenListTop
            return max(base, (m.infoBottom(style, level: info) + m.spacing - m.listPadding).rounded(.up))
        case .banner, .karussell:
            let card = m.cardHeight(style, level: info, collapsedTop: nil)
            return m.frameTop + card - m.cardInnerBottom - m.buttonRow - m.listPadding
        }
    }
}

/// Task 5.2: carousel steps (left/right on the hero button), wrapping at both ends.
public enum HeroCarousel {
    public static func step(_ index: Int, count: Int, forward: Bool) -> Int {
        guard count > 1 else { return 0 }
        let i = min(max(0, index), count - 1)
        return forward ? (i + 1) % count : (i + count - 1) % count
    }
}

/// Task 5.2 (`backdropFollowsFocus`): at most one backdrop request per focus rest. Each focus on a card gets a
/// token; only the latest token's rest asks for the picture, once. Back on the card shown: nothing to ask.
public struct HeroBackdropFollow: Sendable {
    /// ID the backdrop shows for the rows (nil: still the slide).
    public private(set) var shown: String?
    private var serial = 0
    private var waiting: (token: Int, id: String)?

    public init() {}

    /// A card got the focus. Returns the token to wait the backdrop rest for; nil when no picture will be asked for
    /// (option off, or the backdrop already shows this card). Any earlier waiting stop is dropped.
    public mutating func focus(_ id: String, follows: Bool) -> Int? {
        serial += 1
        waiting = nil
        guard follows, id != shown else { return nil }
        waiting = (serial, id)
        return serial
    }

    /// The rest after `token` is over: the ID to show now, once; nil when a newer focus or `leave` came between.
    public mutating func rested(_ token: Int) -> String? {
        guard let w = waiting, w.token == token else { return nil }
        waiting = nil
        shown = w.id
        return w.id
    }

    /// Focus left the rows: a waiting stop is dropped; what is shown stays for a return.
    public mutating func leave() {
        serial += 1
        waiting = nil
    }
}
