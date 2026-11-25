import SwiftUI
import PlayerCore

/// Task 4.4: the runtime theme. Views read it through `@Environment(\.theme)`; `Theme`'s static API stays as the
/// forwarding layer for views that are not moved yet (they keep today's values, which equal `standard`).
///
/// `standard` is exactly today's design: it is built from the `Theme` constants, so nothing changes visibly.
/// `make` starts from `standard` and replaces a token by the plan table (PlayerCore `LookTheme`, `LookMetrics`)
/// only where the look's value differs from the preset "Mein Look" (or the system asks to reduce motion or
/// transparency). The accent is the exception: it always follows the look; since Task 4.5 the root tint
/// (`PlayerApp`) and the settings' accent dots draw `color.accent`.
struct ThemeValues: Equatable {
    var color: Colors
    var type: TypeScale
    var space: Spacing
    var radius: Radii
    var elevation: Elevation
    var focus: FocusStyle
    var motion: Motion
    /// Task 5.5 (Q-28): the system accessibility settings the theme was made with. Views that run their own motion
    /// (carousel, autoplay, expanding posters) or draw `Material` read this instead of the environment again.
    var system = SystemSettings()

    struct SystemSettings: Equatable {
        var reduceMotion = false
        var reduceTransparency = false
    }

    /// Task 5.3: the detail page options (`detail.*`, layout, badges, ratings, cast, source list). Always the
    /// profile's values (like the accent); `standard` carries the baseline (today's defaults).
    var detail: LookDetail = LookPreset.baseline.detail

    /// Task 5.3: `detail.badgeStyle` (ThemeBadge reads it; the player falls back `logos` → `gefuellt`).
    var badgeStyle: LookBadgeStyle { detail.badgeStyle }

    /// Task 5.6: main navigation, clock and settings layout (`global.*`). Always the profile's values (like the
    /// accent); `standard` carries the baseline (today's defaults).
    var chrome = LookChrome(LookPreset.baseline)

    struct Colors: Equatable {
        var base: Color
        var surface: Color
        var raised: Color
        var row: Color
        var rowFocused: Color
        var scrim: Color
        var overlayCard: Color
        var primary: Color
        var secondary: Color
        var primaryOnFocus: Color
        var secondaryOnFocus: Color
        var badgeFill: Color
        var accent: Color
        var onAccent: Color

        /// Foreground by focus of the row (same rule as `Theme.Palette.foreground`).
        func foreground(secondary isSecondary: Bool, focused: Bool) -> Color {
            switch (isSecondary, focused) {
            case (false, false): primary
            case (true, false): secondary
            case (false, true): primaryOnFocus
            case (true, true): secondaryOnFocus
            }
        }
    }

    /// Type: `scale` and `character` of the look. At `.standard` / `.neutral` the roles keep today's tvOS text
    /// styles; any other choice draws the plan's role table (sizes × scale, weight and tracking per character).
    struct TypeScale: Equatable {
        var scale: LookTypeScale
        var character: LookTypeCharacter

        /// Decision in PlayerCore (`LookTheme.usesPlanType`, tested): the preset's scale and character keep today's styles.
        var isToday: Bool { !LookTheme.usesPlanType(scale: scale, character: character) }

        func font(_ role: Theme.TextRole) -> Font {
            guard !isToday else { return role.font }
            let r = LookTheme.type(Self.tableRole(role), scale: scale, character: character)
            return .system(size: r.size, weight: Self.weight(r.weight))
        }

        /// Task 5.5 (D-3): fixed-size glyphs (profile letter, pairing code, list symbol), sized by `scale`
        /// (PlayerCore `LookTheme.glyph`, tested; the preset keeps today's sizes).
        func glyph(_ g: LookTheme.Glyph) -> Font {
            let spec = LookTheme.glyph(g, scale: scale)
            let design: Font.Design = spec.monospaced ? .monospaced : .default
            return .system(size: spec.size, weight: Self.weight(spec.weight), design: design)
        }

        /// Tracking in points (0 for today's styles).
        func tracking(_ role: Theme.TextRole) -> CGFloat {
            guard !isToday else { return 0 }
            let r = LookTheme.type(Self.tableRole(role), scale: scale, character: character)
            return r.size * r.tracking
        }

        /// Today's roles onto the plan table; sizes stay as today (sectionTitle 38 = `title`, rowDetail 29 = `body`).
        static func tableRole(_ role: Theme.TextRole) -> LookTheme.Role {
            switch role {
            case .display: .display
            case .pageTitle: .pageTitle
            case .sectionTitle: .title
            case .rowTitle: .body
            case .rowTitleEmphasis: .bodyEmphasis
            case .rowDetail: .body
            case .badge: .badge
            }
        }

        static func weight(_ css: Int) -> Font.Weight {
            switch css {
            case ..<150: .ultraLight
            case ..<250: .thin
            case ..<350: .light
            case ..<450: .regular
            case ..<550: .medium
            case ..<650: .semibold
            case ..<750: .bold
            case ..<850: .heavy
            default: .black
            }
        }
    }

    struct Spacing: Equatable {
        /// 4: new (D-27), replaces `Space.xs / 2` and the literals 2 and 4.
        var xxs: CGFloat
        var xs: CGFloat
        var s: CGFloat
        var m: CGFloat
        var l: CGFloat
        var xl: CGFloat
        /// 64: new, row ↔ row at "luftig".
        var xxl: CGFloat
        /// One safe-area rule for all pages and the player (D-15).
        var edge: CGFloat
        var edgeVertical: CGFloat
    }

    struct Radii: Equatable {
        var badge: CGFloat
        var row: CGFloat
        var panel: CGFloat
        /// `nil`: cards keep the system style `.buttonStyle(.card)` with its own radius (Build 4).
        var card: CGFloat?
    }

    struct Shadow: Equatable {
        var opacity: Double
        var radius: CGFloat
        var y: CGFloat
    }

    /// Three levels instead of ten single values (D-9).
    struct Elevation: Equatable {
        /// Focused row / button.
        var focus: Shadow
        /// Dialogs and cards over video.
        var overlay: Shadow
    }

    struct FocusStyle: Equatable {
        var scale: CGFloat
        var tileScale: CGFloat
        var pressedScale: CGFloat
        /// Task 4.5: the card's focus border (`LookOptionCatalog.effectiveFocusBorder`: white when the look shows
        /// no other focus sign). No view draws it before Build 5a.
        var border: LookFocusBorder
    }

    struct Motion: Equatable {
        var focus: Double
        var press: Double
        var fade: Double
        var backdrop: Double
        var expand: Double

        /// Animation of a focus change (`nil` when motion is off).
        var focusAnimation: Animation? { focus > 0 ? .easeOut(duration: focus) : nil }
        var pressAnimation: Animation? { press > 0 ? .easeOut(duration: press) : nil }
    }

    /// Today's values, taken from the `Theme` constants (so both stay equal by construction).
    /// `make(defaultProfile.themeLook, false, false)` equals this **except `color.accent` / `onAccent`**: `standard`
    /// carries the preset's accent (weiss), while `make` always takes the profile's accent, and the old default
    /// accent (blue) maps to blau (test `defaultThemeLookUsesNoPlanTokens`). Since Task 4.5 the root tint is
    /// `color.accent` of `make`, never of `standard`; do not compare a theme with `.standard`
    /// to mean "unstyled" — compare the look (`LookTheme.usesPlan…`) instead.
    static let standard = ThemeValues(
        color: Colors(base: Theme.Palette.base, surface: Theme.Palette.surface, raised: Theme.Palette.overlayCard,
                      row: Theme.Palette.row, rowFocused: Theme.Palette.rowFocused, scrim: Theme.Palette.scrim,
                      overlayCard: Theme.Palette.overlayCard, primary: Theme.Palette.primary,
                      secondary: Theme.Palette.secondary, primaryOnFocus: Theme.Palette.primaryOnFocus,
                      secondaryOnFocus: Theme.Palette.secondaryOnFocus, badgeFill: Theme.Palette.badgeFill,
                      accent: rgb(LookTheme.accent(.weiss).accent), onAccent: rgb(LookTheme.accent(.weiss).onAccent)),
        type: TypeScale(scale: .standard, character: .neutral),
        space: Spacing(xxs: 4, xs: Theme.Space.xs, s: Theme.Space.s, m: Theme.Space.m, l: Theme.Space.l,
                       xl: Theme.Space.xl, xxl: 64, edge: Theme.Space.edge, edgeVertical: Theme.Space.edgeVertical),
        radius: Radii(badge: Theme.Radius.badge, row: Theme.Radius.row, panel: Theme.Radius.overlayCard, card: nil),
        elevation: Elevation(
            focus: Shadow(opacity: Theme.Focus.shadowOpacity, radius: Theme.Focus.shadowRadius, y: Theme.Focus.shadowY),
            overlay: Shadow(opacity: 0.5, radius: 30, y: 12)),
        focus: FocusStyle(scale: Theme.Focus.scale, tileScale: Theme.Focus.tileScale,
                          pressedScale: Theme.Focus.pressedScale, border: .keiner),
        motion: Motion(focus: Theme.Focus.duration, press: Theme.Focus.pressDuration, fade: 0.38, backdrop: 0.7,
                       expand: 0.3))

    /// The theme for a profile's look (`Profile.themeLook`, see the ruling there) and the system settings.
    static func make(_ values: LookValues, reduceMotion: Bool, reduceTransparency: Bool) -> ThemeValues {
        var t = standard
        let accent = LookTheme.accent(values.global.accent)
        t.color.accent = rgb(accent.accent)
        t.color.onAccent = rgb(accent.onAccent)
        if LookTheme.usesPlanBackground(values) {
            let bg = LookTheme.background(values.global.background)
            t.color.base = rgb(bg.base)
            t.color.surface = rgb(bg.surface)
            t.color.raised = rgb(bg.raised)
            t.color.overlayCard = rgb(bg.raised)
            // Gradients and the scrim run out in the background tone, never in pure black (07 §3.1).
            t.color.scrim = rgb(bg.base).opacity(0.78)
        }
        if reduceTransparency {
            // Task 5.5 (Q-28): no see-through surfaces: the scrim covers fully, rows and badges are opaque mixes of
            // their white share over the surface (PlayerCore `LookTheme.opaqueWhite`, tested).
            let surface = LookTheme.opaqueSurface(values)
            t.color.scrim = t.color.base
            t.color.row = rgb(LookTheme.opaqueWhite(0.10, over: surface))
            t.color.badgeFill = rgb(LookTheme.opaqueWhite(0.18, over: surface))
        }
        t.system = SystemSettings(reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
        t.type = TypeScale(scale: values.global.typeScale, character: values.global.typeCharacter)
        t.focus.border = LookOptionCatalog.effectiveFocusBorder(values)
        t.detail = values.detail
        t.chrome = LookChrome(values)
        if LookTheme.usesPlanMotion(values, reduceMotion: reduceMotion) {
            let m = LookTheme.motion(values.global.motion, reduceMotion: reduceMotion)
            t.motion = Motion(focus: m.focus, press: m.focus == 0 ? 0 : t.motion.press, fade: m.fade,
                              backdrop: m.backdrop, expand: m.expand)
        }
        return t
    }

    static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
