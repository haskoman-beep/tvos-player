import Foundation

/// Task 5.1: the two card forms of a home row.
public enum CardShape: String, Sendable, Hashable, CaseIterable {
    case poster, landscape
}

/// Task 5.1: what the card form option needs to know about a row ("Weiterschauen" or any other).
public enum HomeRowKind: Sendable, Hashable {
    case continueWatching, other

    public init(isContinueWatching: Bool) { self = isContinueWatching ? .continueWatching : .other }
}

/// Task 5.1 (D-6, D-16, D-23, D-24): card form, size, title strip, gaps and focus room of a home row, from the
/// look (`LookHome`). Pure maths; the app draws `ThemeCard` and `Strip` from it.
public enum CardLayout {
    /// `poster` → always poster; `querformat` → always landscape; `mischung` → landscape for "Weiterschauen",
    /// poster for the rest.
    public static func shape(for row: HomeRowKind, option: LookCardShape) -> CardShape {
        switch option {
        case .poster: .poster
        case .querformat: .landscape
        case .mischung: row == .continueWatching ? .landscape : .poster
        }
    }

    /// Tile form of a row of `style`: poster and landscape rows follow the card form option; Top 10 (rank + poster),
    /// hero, logo and collection tiles keep their own form.
    public static func tileKind(style: RowStyle, row: HomeRowKind, option: LookCardShape) -> TileKind {
        switch style {
        case .poster, .landscape: shape(for: row, option: option) == .poster ? .poster : .landscape
        case .top10, .hero, .logoTiles, .collectionTiles: PosterSize.kind(for: style)
        }
    }

    /// Size factor of `cardSize` (0.85 / 1.0 / 1.2, as `CardSize.scale`).
    public static func factor(_ size: LookCardSize) -> CGFloat {
        switch size {
        case .klein: 0.85
        case .mittel: 1.0
        case .gross: 1.2
        }
    }

    /// Picture size of a card from `LookMetrics.cardSize`, rounded to whole points (landscape large = 528 × 298).
    /// An expanded poster is `height × 16/9` wide; a landscape card does not expand.
    public static func frame(shape: CardShape, size: LookCardSize, expanded: Bool) -> CGSize {
        let base = LookMetrics.cardSize(size, shape: shape == .poster ? .poster : .querformat)
        let h = base.height.rounded()
        guard shape == .poster, expanded else { return CGSize(width: base.width.rounded(), height: h) }
        return CGSize(width: LookMetrics.expandedWidth(height: h).rounded(), height: h)
    }

    /// Picture size of a tile of `kind` (hero stays fixed).
    public static func tileSize(_ kind: TileKind, size: LookCardSize) -> CGSize {
        switch kind {
        case .poster: frame(shape: .poster, size: size, expanded: false)
        case .landscape: frame(shape: .landscape, size: size, expanded: false)
        case .logo, .hero: PosterSize.tileSize(kind, scale: factor(size))
        }
    }

    /// Rows whose cards get the title strip below (`cardTitles`): film and series cards. Top 10 shows its rank,
    /// hero, logo and collection tiles carry their name in the picture.
    public static func showsTitleStrip(style: RowStyle) -> Bool { style == .poster || style == .landscape }

    /// Gap between the card and its title.
    public static let titleGap: CGFloat = 12

    /// Opacity of the title below a card: "fokus" fades it in on the focused card only (the room stays).
    public static func titleOpacity(_ mode: LookCardTitles, focused: Bool) -> Double {
        switch mode {
        case .immer: 1
        case .fokus: focused ? 1 : 0
        case .aus: 0
        }
    }

    /// Row ↔ row gap of `rowSpacing` (36 / 48 / 64).
    public static func rowGap(_ s: LookRowSpacing) -> CGFloat { LookMetrics.rowSpacing(s).row }

    /// Whether a focused poster expands: the option, never while the system reduces motion.
    /// 5c5-merge: `LookTheme.expandsPosters(_:reduceMotion:)` (b5c-5.5) is the same rule; keep one of them.
    public static func expands(_ v: LookValues, reduceMotion: Bool) -> Bool { v.home.expandPosters && !reduceMotion }

    /// VoiceOver value of a card: year, progress ("42 % gesehen") or "gesehen", joined by ", ".
    public static func accessibilityValue(year: String?, fraction: Double?, watched: Bool) -> String {
        var parts: [String] = []
        if let y = year?.trimmingCharacters(in: .whitespaces), !y.isEmpty { parts.append(y) }
        if watched {
            parts.append("gesehen")
        } else if let f = fraction, f > 0 {
            parts.append("\(Int((min(1, f) * 100).rounded())) % gesehen")
        }
        return parts.joined(separator: ", ")
    }

    /// Everything about one row of cards. `badgeBand`: quality strip below a poster (0 when off), `titleLine`: line
    /// height of the title font, `showsTitles`: the row has title strips at all (`showsTitleStrip`).
    public static func row(kind: TileKind, home: LookHome, badgeBand: CGFloat, titleLine: CGFloat,
                           showsTitles: Bool = true) -> CardRowGeometry {
        let tile = tileSize(kind, size: home.cardSize)
        let below = kind == .poster ? max(0, badgeBand) : 0
        let titled = showsTitles && home.cardTitles != .aus && (kind == .poster || kind == .landscape)
        let strip: CGFloat = titled ? titleGap + max(0, titleLine).rounded(.up) : 0
        let lift = FocusHeadroom.lift(home)
        let f = factor(home.cardSize)
        let card = tile.height + below
        let pad = FocusHeadroom.rowPadding(height: card, scale: lift.scale, shadow: lift.reach, minimum: 32 * f)
        let shift = FocusHeadroom.perSide(height: card, scale: lift.scale, shadow: 0)
        let gap: CGFloat = kind == .hero ? 20 * f
            : FocusHeadroom.tileSpacing(width: tile.width, scale: lift.scale, clearance: lift.side,
                                        minimum: LookMetrics.rowSpacing(home.rowSpacing).card)
        return CardRowGeometry(kind: kind, tile: tile, below: below, titleStrip: strip, titleShift: shift,
                               padding: pad, cardGap: gap)
    }
}

/// Task 5.1: geometry of one row of cards (`CardLayout.row`).
public struct CardRowGeometry: Hashable, Sendable {
    public var kind: TileKind
    /// Picture size.
    public var tile: CGSize
    /// Quality strip below a poster picture (part of the lifted card).
    public var below: CGFloat
    /// Room for the title below the card (gap + one line); the same for "immer" and "fokus", 0 for "aus".
    public var titleStrip: CGFloat
    /// How far the title moves down while its card is lifted (the card's growth below its edge).
    public var titleShift: CGFloat
    /// Room above and below the cards for the focus lift (at least 32 × size factor, as in Build 4).
    public var padding: CGFloat
    /// Card ↔ card gap: the look's spacing, at least the sideways lift room.
    public var cardGap: CGFloat

    /// Row height: heading line and its gap (none for a hero row), the card, its title strip and the lift padding
    /// above and below.
    public func rowHeight(heading: CGFloat, headingSpacing: CGFloat) -> CGFloat {
        let head: CGFloat = kind == .hero ? 0 : max(0, heading) + max(0, headingSpacing)
        return head + tile.height + below + titleStrip + 2 * padding
    }
}
