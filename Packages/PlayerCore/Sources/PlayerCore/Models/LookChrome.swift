import Foundation

/// Task 5.6 (D-19, D-28): what the main navigation, the clock and the settings layout take from the look
/// (`global.navigation`, `global.clock`, `global.settingsLayout`). Pure values so the app only draws them.
public struct LookChrome: Sendable, Hashable {
    public var navigation: LookNavigation
    public var clock: Bool
    public var settingsLayout: LookSettingsLayout
    public var typeScale: LookTypeScale
    public var corners: LookCorners

    public init(_ v: LookValues) {
        navigation = v.global.navigation
        clock = v.global.clock
        settingsLayout = v.global.settingsLayout
        typeScale = v.global.typeScale
        corners = v.home.corners
    }

    // MARK: Navigation

    /// The old field the tab view and the tab bar guards still take (`Appearance.navigation`).
    public var navigationStyle: NavigationStyle { navigation == .seitenleiste ? .sidebar : .top }

    /// Leading inset of the content next to the navigation (seitenleiste 150, oben 80).
    public var contentLeading: CGFloat { LookMetrics.contentLeading(navigation) }

    /// How much further in than the top-bar layout the content starts (pages lay out at the top-bar edge of 80).
    public var leadingExtra: CGFloat { contentLeading - LookMetrics.contentLeading(.oben) }

    // MARK: Clock

    /// Clock on (top right of every tab page; the player covers it).
    public var showsClock: Bool { clock }

    /// `meta` role of the configurator: 27 pt × typeScale, weight 500, white 75 %, at right 80 / top 56.
    public var clockFontSize: CGFloat { 27 * LookMetrics.typeScale(typeScale) }
    public static let clockWeight = 500
    public static let clockOpacity = 0.75
    public static let clockTrailing: CGFloat = 80
    public static let clockTop: CGFloat = 56

    /// Hours and minutes in the locale's order and separators, always on the 24-hour clock.
    public static func clockText(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        clockFormatter(locale: locale, timeZone: timeZone).string(from: date)
    }

    /// The formatter behind `clockText` (the app keeps one and refreshes it once a minute).
    public static func clockFormatter(locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        // "HH" asks for the 24-hour clock whatever the locale prefers; the template keeps its separator.
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "HHmm", options: 0, locale: locale) ?? "HH:mm"
        return f
    }

    // MARK: Settings tiles

    public static let tileColumns = 4
    public static let tileSpacing: CGFloat = 26
    public static let tileHeight: CGFloat = 230
    /// Tile radius: the card radius of `home.corners` plus 6.
    public var tileRadius: CGFloat { LookMetrics.cornerRadius(corners) + 6 }
    /// Width of the single centred column of the `liste` layout (configurator: 460 free on each side of 1920).
    public static let listWidth: CGFloat = 1000
}

/// Task 5.6: the entries of the settings root in each layout. All three show the same phone entry and the same
/// categories (same rows below them); they differ only in the headers.
public enum SettingsLayoutTree {
    public enum Entry: Hashable, Sendable {
        /// „Am Handy einrichten“.
        case phone
        /// Group header (or gap for System) of the two-column layout.
        case group(SettingsGroup)
        case category(SettingsCategory)
    }

    public static func entries(_ layout: LookSettingsLayout) -> [Entry] {
        var out: [Entry] = [.phone]
        for c in SettingsCategory.allCases {
            if layout == .spalten, c.startsGroup { out.append(.group(c.group)) }
            out.append(.category(c))
        }
        return out
    }

    public static func categories(_ entries: [Entry]) -> [SettingsCategory] {
        entries.compactMap { if case .category(let c) = $0 { c } else { nil } }
    }

    /// The layout the settings root draws. A change waits while a subpage is open: the link it was pushed from
    /// would leave the root and pop it under the user. `latched` is the layout the root drew last.
    public static func shown(latched: LookSettingsLayout?, current: LookSettingsLayout,
                             rootVisible: Bool) -> LookSettingsLayout {
        guard let latched, !rootVisible else { return current }
        return latched
    }
}
