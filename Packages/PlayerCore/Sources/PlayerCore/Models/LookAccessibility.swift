import Foundation

/// Task 5.5 (D-3, Q-28): the pure rules behind the system settings "reduce transparency" and "reduce motion", and the
/// fixed-size glyphs of the other screens (profile letters, pairing codes, list symbols), so no view outside the
/// design layer needs `.font(.system(size:))`.
extension LookTheme {
    /// White at `opacity` mixed opaquely over `base` (0xRRGGBB), per channel, rounded.
    public static func opaqueWhite(_ opacity: Double, over base: UInt32) -> UInt32 {
        let a = min(max(opacity, 0), 1)
        func channel(_ shift: UInt32) -> UInt32 {
            let c = Double(base >> shift & 0xFF)
            return UInt32((255 * a + c * (1 - a)).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    /// The surface the opaque mixes sit on: `bg.surface` of the look; at the preset background today's surface
    /// (white 7 % over black = 0x121212, `Theme.Palette.surface`).
    public static func opaqueSurface(_ v: LookValues) -> UInt32 {
        usesPlanBackground(v) ? background(v.global.background).surface : 0x121212
    }

    /// Posters expand on focus only while the system does not reduce motion (deploy check "kein Aufklappen").
    /// Integration build 5: the one rule (Task 5.1 had the same as `CardLayout.expands`).
    public static func expandsPosters(_ v: LookValues, reduceMotion: Bool) -> Bool {
        expandsPosters(v.home, reduceMotion: reduceMotion)
    }

    /// Same rule on the home options alone (the app's `ThemeValues.cards`).
    public static func expandsPosters(_ home: LookHome, reduceMotion: Bool) -> Bool {
        home.expandPosters && !reduceMotion
    }

    /// Glyphs with a fixed size outside the text roles.
    public enum Glyph: String, Sendable, CaseIterable {
        /// Initial letter in the profile circle and on a person without a photo (90, bold).
        case monogram
        /// Pairing code on the login page (90, bold, monospaced).
        case code
        /// List symbol next to a row title (32 = `Theme.Layout.iconSize`, regular).
        case symbol
    }

    public struct GlyphSpec: Sendable, Hashable {
        public var size: CGFloat
        /// CSS 100–900 like `TypeRole.weight`.
        public var weight: Int
        public var monospaced: Bool
    }

    /// Size already multiplied by `typeScale` (1.0 at the preset, so today's sizes stay).
    public static func glyph(_ g: Glyph, scale: LookTypeScale) -> GlyphSpec {
        let base: GlyphSpec = switch g {
        case .monogram: GlyphSpec(size: 90, weight: 700, monospaced: false)
        case .code: GlyphSpec(size: 90, weight: 700, monospaced: true)
        case .symbol: GlyphSpec(size: 32, weight: 400, monospaced: false)
        }
        var s = base
        s.size = base.size * LookMetrics.typeScale(scale)
        return s
    }
}

extension TileMotion {
    /// Task 5.5 (Q-28): with the system's "reduce motion" a focused tile keeps its still (no focus video, no GIF).
    public static func of(_ f: Folder, reduceMotion: Bool) -> TileMotion {
        reduceMotion ? .still : of(f)
    }
}
