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

    /// Band above a clipping list edge (home list under the hero info): the headroom of the tallest tile plus the
    /// soft fade above it, so the lifted card stays fully opaque and only the band's top edge fades.
    public static func edgeBand(height: CGFloat, scale: CGFloat, shadow: CGFloat, fade: CGFloat) -> CGFloat {
        perSide(height: height, scale: scale, shadow: shadow) + max(0, fade)
    }

    /// Height of the tallest tile among `kinds` at the card size factor `cardScale` (hero stays fixed).
    /// `posterExtra`: strip below a poster picture (quality badges “below”), part of the lifted card. 0 without kinds.
    public static func tallest(_ kinds: [TileKind], cardScale: CGFloat, posterExtra: CGFloat = 0) -> CGFloat {
        kinds.reduce(0) { h, kind in
            max(h, PosterSize.tileSize(kind, scale: cardScale).height + (kind == .poster ? max(0, posterExtra) : 0))
        }
    }
}
