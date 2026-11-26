import Foundation

/// Task 4.4: the pure tables behind the runtime theme (plan Task 4.4, `07-design-analyse.md` §3). Colors are
/// 24-bit RGB numbers (`0xRRGGBB`) so they can be tested here; the app turns them into `Color`.
public enum LookTheme {
    /// `accent` / `accent.on` per `global.accent`.
    public struct AccentColors: Sendable, Hashable {
        public var accent: UInt32
        public var onAccent: UInt32
    }

    /// `bg.base` / `bg.surface` / `bg.raised` per `global.background`.
    public struct BackgroundColors: Sendable, Hashable {
        public var base: UInt32
        public var surface: UInt32
        public var raised: UInt32
    }

    public static func accent(_ a: LookAccent) -> AccentColors {
        switch a {
        case .champagner: AccentColors(accent: 0xD4B87A, onAccent: 0x17140C)
        case .weiss: AccentColors(accent: 0xF2F1EC, onAccent: 0x111111)
        case .eisblau: AccentColors(accent: 0x8FC7FF, onAccent: 0x06121D)
        case .blau: AccentColors(accent: 0x3B82F6, onAccent: 0xFFFFFF)
        case .rot: AccentColors(accent: 0xE5383B, onAccent: 0xFFFFFF)
        case .koralle: AccentColors(accent: 0xFF7A59, onAccent: 0x1D0A04)
        case .salbei: AccentColors(accent: 0x9FC5A8, onAccent: 0x0B160E)
        case .violett: AccentColors(accent: 0xA78BFA, onAccent: 0x120A26)
        }
    }

    /// `bg.raised` is `bg.surface` with 5 % white on top; for graphit the value from `07` §3.1.
    public static func background(_ b: LookBackground) -> BackgroundColors {
        switch b {
        case .schwarz: BackgroundColors(base: 0x000000, surface: 0x131314, raised: 0x1F1F20)
        case .graphit: BackgroundColors(base: 0x0B0C0E, surface: 0x17191D, raised: 0x22252B)
        case .tinte: BackgroundColors(base: 0x070B14, surface: 0x111827, raised: 0x1E2432)
        case .warm: BackgroundColors(base: 0x0E0B08, surface: 0x1C1713, raised: 0x27231F)
        }
    }

    /// Text roles of the plan table.
    public enum Role: String, Sendable, CaseIterable {
        case display, pageTitle, title, sectionTitle, sectionLabel, sectionLarge, body, bodyEmphasis, meta, badge
    }

    /// One text role: size in points (before `typeScale`), weight (CSS 100–900), tracking as a fraction of the size
    /// (−0.01 = −1 %), line height as a multiple of the size.
    public struct TypeRole: Sendable, Hashable {
        public var size: CGFloat
        public var weight: Int
        public var tracking: CGFloat
        public var lineHeight: CGFloat
    }

    /// The role for `character`, size already multiplied by `typeScale`.
    public static func type(_ role: Role, scale: LookTypeScale, character: LookTypeCharacter) -> TypeRole {
        let c = character
        func pick<T>(_ n: T, _ e: T, _ t: T) -> T {
            switch c {
            case .neutral: n
            case .editorial: e
            case .technisch: t
            }
        }
        let r: TypeRole = switch role {
        case .display: TypeRole(size: 76, weight: pick(700, 300, 800), tracking: pick(-0.01, -0.025, 0), lineHeight: 1.02)
        case .pageTitle: TypeRole(size: 48, weight: pick(600, 500, 700), tracking: pick(0, 0.005, 0.01), lineHeight: 1.1)
        case .title: TypeRole(size: 38, weight: pick(600, 500, 700), tracking: pick(0, 0.005, 0.01), lineHeight: 1.15)
        case .sectionTitle: TypeRole(size: 34, weight: 600, tracking: 0, lineHeight: 1.15)
        case .sectionLabel: TypeRole(size: 27, weight: 500, tracking: 0.02, lineHeight: 1.2)
        case .sectionLarge: TypeRole(size: 44, weight: 700, tracking: -0.01, lineHeight: 1.1)
        case .body: TypeRole(size: 29, weight: 400, tracking: 0, lineHeight: 1.32)
        case .bodyEmphasis: TypeRole(size: 29, weight: 600, tracking: 0, lineHeight: 1.32)
        case .meta: TypeRole(size: 26, weight: 500, tracking: pick(0.01, 0.03, 0.05), lineHeight: 1.25)
        case .badge: TypeRole(size: 23, weight: 700, tracking: 0.04, lineHeight: 1)
        }
        var scaled = r
        scaled.size = r.size * LookMetrics.typeScale(scale)
        return scaled
    }

    // MARK: Plan table or today's design

    /// Task 4.4: the theme keeps today's design for a token as long as the look keeps the "Mein Look" preset value
    /// there (`ThemeValues.standard`); only a different value switches that token to the plan table. These three
    /// decisions are the whole "no visible change" guarantee of Build 4, so they live here with tests.
    public static func usesPlanBackground(_ v: LookValues) -> Bool {
        v.global.background != LookPreset.values(.appleTV).global.background
    }

    public static func usesPlanType(scale: LookTypeScale, character: LookTypeCharacter) -> Bool {
        let p = LookPreset.values(.appleTV).global
        return scale != p.typeScale || character != p.typeCharacter
    }

    /// System "reduce motion" always switches to the table (all times zero).
    public static func usesPlanMotion(_ v: LookValues, reduceMotion: Bool) -> Bool {
        reduceMotion || v.global.motion != LookPreset.values(.appleTV).global.motion
    }

    /// Motion times, all zero when the system asks to reduce motion (Q-28).
    public static func motion(_ m: LookMotion, reduceMotion: Bool) -> LookMotionTimes {
        LookMetrics.motion(reduceMotion ? .aus : m)
    }
}

extension Profile {
    /// Task 4.4, controller ruling for Build 4 (round 2): until Task 4.5 lets the user edit the look directly, the
    /// look the theme is built from is derived at runtime. Every key without an old field comes from the stored look
    /// (preset plus overrides). For a key that still has an old field (navigation, accent, cardSize, heroStyle on/off
    /// via heroEnabled, expandPosters, detail badgeStyle, player trackPanel) the stored look's value wins while
    /// `LookMigration.oldValues(for: stored)` maps to the current old field value (e.g. an imported champagner or
    /// umriss, which the old fields can only approximate). Once the user changes the old field in the old settings it
    /// no longer matches, and the value derived from the old field wins. So the old settings stay authoritative and
    /// a stale look can never override them; an import is shown with its exact values.
    public var themeLook: LookValues {
        let old = Look.migrated(from: appearance, player: player, sources: sources).resolved()
        var v = look.resolved()
        let stored = LookMigration.oldValues(for: v)
        if stored.navigation != appearance.navigation { v.global.navigation = old.global.navigation }
        if !stored.accents.contains(appearance.accent) { v.global.accent = old.global.accent }
        if stored.cardSize != appearance.cardSize { v.home.cardSize = old.home.cardSize }
        // heroEnabled only says on/off: off → aus; on keeps a stored style other than aus (else the preset's).
        if !appearance.heroEnabled { v.home.heroStyle = .aus }
        else if v.home.heroStyle == .aus { v.home.heroStyle = LookPreset.values(look.preset).home.heroStyle }
        if stored.expandPosters != appearance.expandPosters { v.home.expandPosters = old.home.expandPosters }
        if stored.badgeStyle != appearance.badges.style { v.detail.badgeStyle = old.detail.badgeStyle }
        if stored.trackPanelStyle != player.trackPanelStyle { v.player.trackPanel = old.player.trackPanel }
        return v
    }

    /// Integration build 5 (user decision 26.11.): the old rows „Plaketten-Stil“ (Aussehen) and „Titelbild oben“
    /// (Startseite) are gone, only the look rows `badgeStyle` and `heroStyle` remain. An old value that differs from
    /// its default and that the stored look does not map to moves into the look (runs on every load, a no-op once
    /// moved). The old fields stay as they are, so the profile JSON keeps its format. Returns the moved look keys.
    @discardableResult
    public mutating func adoptOldLookRows() -> [String] {
        var v = look.resolved()
        let stored = LookMigration.oldValues(for: v)
        let d = Appearance()
        var keys: [String] = []
        if appearance.heroEnabled != d.heroEnabled, stored.heroEnabled != appearance.heroEnabled {
            v.home.heroStyle = .aus   // the default is on, so only „off“ can differ
            keys.append("heroStyle")
        }
        if appearance.badges.style != d.badges.style, stored.badgeStyle != appearance.badges.style {
            v.detail.badgeStyle = appearance.badges.style == .logo ? .logos : .text
            keys.append("badgeStyle")
        }
        guard !keys.isEmpty else { return [] }
        look = Look(preset: look.preset, overrides: LookOverrides.difference(v, from: LookPreset.values(look.preset)))
        return keys
    }
}
