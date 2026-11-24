import Foundation

/// Card and row gaps in points.
public struct LookSpacing: Sendable, Hashable {
    public var card: CGFloat
    public var row: CGFloat
    public init(card: CGFloat, row: CGFloat) { self.card = card; self.row = row }
}

/// Transition durations in seconds for one `motion` setting.
public struct LookMotionTimes: Sendable, Hashable {
    public var focus: Double
    public var fade: Double
    public var backdrop: Double
    public var expand: Double
    public init(focus: Double, fade: Double, backdrop: Double, expand: Double) {
        self.focus = focus; self.fade = fade; self.backdrop = backdrop; self.expand = expand
    }
}

/// How long the focus must rest before something follows it, in seconds (independent of `motion`).
public struct LookRestTimes: Sendable, Hashable {
    public var backdrop: Double
    public var expand: Double
    public var prefetch: Double
    public init(backdrop: Double, expand: Double, prefetch: Double) {
        self.backdrop = backdrop; self.expand = expand; self.prefetch = prefetch
    }
}

/// Shadow below the focused card: black at `opacity`, blur `radius`, offset `y` (points).
public struct LookShadow: Sendable, Hashable {
    public var opacity: Double
    public var radius: CGFloat
    public var y: CGFloat
    public init(opacity: Double, radius: CGFloat, y: CGFloat) { self.opacity = opacity; self.radius = radius; self.y = y }
}

/// Task 4.2: the numbers behind the look options, pure tables in points at 1920 × 1080. The app turns them into
/// `ThemeValues` (Task 4.4); colors stay in the app because `Color` needs SwiftUI.
public enum LookMetrics {
    public static func focusScale(_ s: LookFocusScale) -> CGFloat {
        switch s {
        case .keine: 1.0
        case .dezent: 1.05
        case .kraeftig: 1.12
        }
    }

    /// Card radius.
    public static func cornerRadius(_ c: LookCorners) -> CGFloat {
        switch c {
        case .eckig: 0
        case .leicht: 8
        case .weich: 14
        case .rund: 26
        }
    }

    /// Radius of a row surface (+4).
    public static func rowRadius(_ c: LookCorners) -> CGFloat { cornerRadius(c) + 4 }
    /// Radius of a panel (+8).
    public static func panelRadius(_ c: LookCorners) -> CGFloat { cornerRadius(c) + 8 }

    public static func rowSpacing(_ s: LookRowSpacing) -> LookSpacing {
        switch s {
        case .eng: LookSpacing(card: 16, row: 36)
        case .normal: LookSpacing(card: 24, row: 48)
        case .luftig: LookSpacing(card: 32, row: 64)
        }
    }

    /// Base poster 240 × 360, landscape 440 × 248, times the size factor. `mischung` is chosen per row
    /// (continue watching landscape, the rest poster); its base here is the poster.
    public static func cardSize(_ size: LookCardSize, shape: LookCardShape) -> CGSize {
        let base: CGSize = switch shape {
        case .poster, .mischung: CGSize(width: 240, height: 360)
        case .querformat: CGSize(width: 440, height: 248)
        }
        let f: CGFloat = switch size {
        case .klein: 0.85
        case .mittel: 1.0
        case .gross: 1.2
        }
        return CGSize(width: base.width * f, height: base.height * f)
    }

    /// Width of an expanded poster (16:9 at the card's height).
    public static func expandedWidth(height: CGFloat) -> CGFloat { height * 16 / 9 }

    public static func typeScale(_ s: LookTypeScale) -> CGFloat {
        switch s {
        case .kompakt: 0.9
        case .standard: 1.0
        case .gross: 1.12
        }
    }

    public static func motion(_ m: LookMotion) -> LookMotionTimes {
        switch m {
        case .aus: LookMotionTimes(focus: 0, fade: 0, backdrop: 0, expand: 0)
        case .dezent: LookMotionTimes(focus: 0.18, fade: 0.24, backdrop: 0.5, expand: 0.25)
        case .standard: LookMotionTimes(focus: 0.22, fade: 0.38, backdrop: 0.7, expand: 0.3)
        }
    }

    public static let rest = LookRestTimes(backdrop: 0.35, expand: 0.5, prefetch: 0.7)

    /// `nil` for `keiner`.
    public static func focusShadow(_ s: LookFocusShadow) -> LookShadow? {
        switch s {
        case .keiner: nil
        case .weich: LookShadow(opacity: 0.45, radius: 20, y: 18)
        case .tief: LookShadow(opacity: 0.75, radius: 35, y: 34)
        }
    }

    /// Focus border: 4 pt wide, 4 pt away from the card.
    public static let focusBorderWidth: CGFloat = 4
    public static let focusBorderGap: CGFloat = 4

    /// Leading inset of the content next to the navigation.
    public static func contentLeading(_ n: LookNavigation) -> CGFloat {
        switch n {
        case .seitenleiste: 150
        case .oben: 80
        }
    }

    public static func descriptionLines(_ l: LookDescriptionLines) -> Int { l.rawValue }
}
