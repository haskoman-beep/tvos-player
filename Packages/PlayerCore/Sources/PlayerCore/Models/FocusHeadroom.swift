import Foundation

/// Wave F-k: room a focused tile needs around itself so its focus lift (a scale around the tile's centre) and the
/// shadow are never cut by a scroll view edge or covered by the neighbouring row. Pure maths; the factors are
/// design tokens in the app (`Theme.Focus`).
public enum FocusHeadroom {
    /// Growth of one edge when a tile of `height` points is scaled by `scale` around its centre, plus `shadow` points
    /// that shadow and tilt reach beyond the scaled edge. Rounded up to whole points; a scale of 1 or below grows
    /// nothing, a negative shadow counts as 0.
    public static func perSide(height: CGFloat, scale: CGFloat, shadow: CGFloat) -> CGFloat {
        let growth = max(0, height) * max(0, scale - 1) / 2
        // Tolerance: 1.15 − 1 is not exact in binary, 27 pt must not become 28.
        return max(0, (growth + max(0, shadow) - 1e-6).rounded(.up))
    }

    /// Vertical padding of a tile row: the headroom, but at least `minimum` (rows that already had enough room keep
    /// their spacing, so only rows that were too tight grow).
    public static func rowPadding(height: CGFloat, scale: CGFloat, shadow: CGFloat, minimum: CGFloat) -> CGFloat {
        max(minimum, perSide(height: height, scale: scale, shadow: shadow))
    }

    /// Gap between tiles in one row: the focused tile grows sideways by half its extra width and must not cover its
    /// neighbour, so the gap is that growth plus `clearance`, but at least `minimum` (rows that had room stay as they are).
    public static func tileSpacing(width: CGFloat, scale: CGFloat, clearance: CGFloat, minimum: CGFloat) -> CGFloat {
        max(minimum, perSide(height: width, scale: scale, shadow: clearance))
    }

    /// Band above a clipping list edge (home list under the hero info): the headroom of the tallest tile plus the
    /// soft fade above it, so the lifted card stays fully opaque and only the band's top edge fades.
    public static func edgeBand(height: CGFloat, scale: CGFloat, shadow: CGFloat, fade: CGFloat) -> CGFloat {
        perSide(height: height, scale: scale, shadow: shadow) + max(0, fade)
    }

    /// Wave F-m: room between the bottom edge of a vertical tile list and the screen edge. Focus scrolling keeps only
    /// the focused card's frame inside the list's bounds, so a card in the lowest visible row ends exactly at that
    /// edge and its lift reaches below it (build 198 photo: list down to the screen edge, lift cut off). The list ends
    /// this far above the screen edge and draws into the room (no clipping), so the lifted card fits on screen.
    public static func listBottomRoom(height: CGFloat, scale: CGFloat, shadow: CGFloat) -> CGFloat {
        perSide(height: height, scale: scale, shadow: shadow)
    }

    /// Wave F-m: vertical extent of a card lifted around its centre, plus shadow (for checks against list edges).
    public static func liftedExtent(minY: CGFloat, maxY: CGFloat, scale: CGFloat, shadow: CGFloat) -> ClosedRange<CGFloat> {
        let grow = max(0, maxY - minY) * max(0, scale - 1) / 2 + max(0, shadow)
        return (minY - grow)...(maxY + grow)
    }

    /// Height of the tallest tile among `kinds` at the card size factor `cardScale` (hero stays fixed).
    /// `posterExtra`: strip below a poster picture (quality badges “below”), part of the lifted card. 0 without kinds.
    public static func tallest(_ kinds: [TileKind], cardScale: CGFloat, posterExtra: CGFloat = 0) -> CGFloat {
        kinds.reduce(0) { h, kind in
            max(h, PosterSize.tileSize(kind, scale: cardScale).height + (kind == .poster ? max(0, posterExtra) : 0))
        }
    }
}

// MARK: Task 5.1: room for the look's focus effect

extension FocusHeadroom {
    /// Lift of the system card style (`.buttonStyle(.card)`, used with `focusGlow`). tvOS does not publish the factor;
    /// device photos (build 187) showed about 12 % including the tilt, rounded up (wave F-k). Same values as the app's
    /// `Theme.Focus.cardLiftScale` / `cardLiftShadow`.
    public static let systemCardScale: CGFloat = 1.15
    public static let systemCardShadow: CGFloat = 12
    /// Sideways clearance of a lifted card to its neighbour (wave F-k, 23.11.).
    public static let sideClearance: CGFloat = 8

    /// How a focused card grows: `scale` around its centre, `reach` points beyond the scaled edge above and below
    /// (shadow, border), `side` points beyond it to the left and right (border plus clearance; a soft shadow may
    /// overlap the neighbour's gap, as on Apple TV).
    public struct CardLift: Hashable, Sendable {
        public var scale: CGFloat
        public var reach: CGFloat
        public var side: CGFloat

        public init(scale: CGFloat, reach: CGFloat, side: CGFloat) {
            self.scale = scale; self.reach = reach; self.side = side
        }
    }

    /// The lift of the look's focus options (`LookMetrics`). Glow: the system card style, the three other values do
    /// not apply. Otherwise scale `focusScale`; border 4 pt at 4 pt distance (white when the look would show no focus
    /// sign, `LookOptionCatalog.effectiveFocusBorder`); the visible part of the shadow is its offset plus half its
    /// blur radius (on the dark background the outer half of the blur cannot be seen).
    public static func lift(_ home: LookHome) -> CardLift {
        guard !home.focusGlow else { return CardLift(scale: systemCardScale, reach: systemCardShadow, side: sideClearance) }
        let border: CGFloat = effectiveBorder(home) == .keiner ? 0 : LookMetrics.focusBorderWidth + LookMetrics.focusBorderGap
        let shadow: CGFloat = LookMetrics.focusShadow(home.focusShadow).map { $0.y + $0.radius / 2 } ?? 0
        return CardLift(scale: LookMetrics.focusScale(home.focusScale), reach: border + shadow, side: sideClearance + border)
    }

    /// `LookOptionCatalog.effectiveFocusBorder` for the home part of a look.
    public static func effectiveBorder(_ home: LookHome) -> LookFocusBorder {
        let noSign = home.focusScale == .keine && home.focusBorder == .keiner && home.focusShadow == .keiner
            && !home.focusGlow
        return noSign ? .weiss : home.focusBorder
    }
}
