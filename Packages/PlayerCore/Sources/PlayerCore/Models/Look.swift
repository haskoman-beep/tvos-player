import Foundation

/// Task 4.2 (D-28): schema version of `Look`. A hint, not a lock: a higher version is read like a known one and
/// unknown fields are ignored. Only a rename or a change of meaning raises it (then `LookMigration.upgrade`).
public enum LookSchema {
    public static let current = 1
}

/// The presets the app knows. User decision 23.11.: exactly one, "Mein Look", with the values of the configurator
/// preset "appletv". Any other raw value (`edel`, `infuse`, `kino`, `streaming`, unknown) decodes to `.appleTV`
/// and is noted in the `DecodeReport`.
public enum LookPresetID: String, Codable, Sendable, Hashable, CaseIterable {
    case appleTV = "appletv"

    public var title: String {
        switch self {
        case .appleTV: "Mein Look"
        }
    }
}

/// Task 4.2: the look of a profile, stored as preset plus only the deviations from it. A missing override means
/// "the preset decides", so a preset sharpened in a later build reaches every profile that did not touch the value.
public struct Look: Codable, Sendable, Hashable {
    public var version: Int
    public var preset: LookPresetID
    public var overrides: LookOverrides

    public init(version: Int = LookSchema.current, preset: LookPresetID = .appleTV,
                overrides: LookOverrides = LookOverrides()) {
        self.version = version; self.preset = preset; self.overrides = overrides
    }

    /// The preset, overlaid with the overrides. Complete, no optionals.
    public func resolved() -> LookValues { overrides.applied(to: LookPreset.values(preset)) }

    enum CodingKeys: String, CodingKey { case version, preset, overrides }

    /// Never throws because of one value: unreadable fields fall back (version → current, preset → `.appleTV`,
    /// overrides → none) and are noted in the `DecodeReport`; unknown keys are ignored.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let r = DecodeReportBox.of(decoder)
        version = c.decodeLenient(Int.self, forKey: .version, default: LookSchema.current, report: r)
        preset = c.decodeLenient(LookPresetID.self, forKey: .preset, default: .appleTV, report: r)
        overrides = c.decodeLenient(LookOverrides.self, forKey: .overrides, default: LookOverrides(), report: r)
    }

    /// Writes `LookSchema.current`, not the version read: what this build writes is its own shape (unknown keys and
    /// values were dropped while reading), so a later build must treat it as this version.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(LookSchema.current, forKey: .version)
        try c.encode(preset, forKey: .preset)
        try c.encode(overrides, forKey: .overrides)
    }

    /// Same preset and overrides; the schema version read does not count.
    func sameStyle(as other: Look) -> Bool { preset == other.preset && overrides == other.overrides }
}

// MARK: - Complete values

/// All 35 configurator options, complete. Encodes with the configurator's key names (`values` of `export.json`).
public struct LookValues: Encodable, Sendable, Hashable {
    public var global: LookGlobal
    public var home: LookHome
    public var detail: LookDetail
    public var player: LookPlayer

    public init(global: LookGlobal, home: LookHome, detail: LookDetail, player: LookPlayer) {
        self.global = global; self.home = home; self.detail = detail; self.player = player
    }
}

public struct LookGlobal: Encodable, Sendable, Hashable {
    public var navigation: LookNavigation
    public var clock: Bool
    public var settingsLayout: LookSettingsLayout
    public var accent: LookAccent
    public var background: LookBackground
    public var typeScale: LookTypeScale
    public var typeCharacter: LookTypeCharacter
    public var motion: LookMotion

    public init(navigation: LookNavigation, clock: Bool, settingsLayout: LookSettingsLayout, accent: LookAccent,
                background: LookBackground, typeScale: LookTypeScale, typeCharacter: LookTypeCharacter,
                motion: LookMotion) {
        self.navigation = navigation; self.clock = clock; self.settingsLayout = settingsLayout; self.accent = accent
        self.background = background; self.typeScale = typeScale; self.typeCharacter = typeCharacter
        self.motion = motion
    }
}

public struct LookHome: Encodable, Sendable, Hashable {
    public var heroStyle: LookHeroStyle
    public var heroInfo: LookHeroInfo
    public var heroTitle: LookHeroTitle
    public var backdropFollowsFocus: Bool
    public var cardShape: LookCardShape
    public var cardSize: LookCardSize
    public var corners: LookCorners
    public var rowSpacing: LookRowSpacing
    public var rowTitle: LookRowTitle
    public var cardTitles: LookCardTitles
    public var expandPosters: Bool
    public var focusScale: LookFocusScale
    public var focusBorder: LookFocusBorder
    public var focusShadow: LookFocusShadow
    public var focusGlow: Bool

    public init(heroStyle: LookHeroStyle, heroInfo: LookHeroInfo, heroTitle: LookHeroTitle, backdropFollowsFocus: Bool,
                cardShape: LookCardShape, cardSize: LookCardSize, corners: LookCorners, rowSpacing: LookRowSpacing,
                rowTitle: LookRowTitle, cardTitles: LookCardTitles, expandPosters: Bool, focusScale: LookFocusScale,
                focusBorder: LookFocusBorder, focusShadow: LookFocusShadow, focusGlow: Bool) {
        self.heroStyle = heroStyle; self.heroInfo = heroInfo; self.heroTitle = heroTitle
        self.backdropFollowsFocus = backdropFollowsFocus; self.cardShape = cardShape; self.cardSize = cardSize
        self.corners = corners; self.rowSpacing = rowSpacing; self.rowTitle = rowTitle; self.cardTitles = cardTitles
        self.expandPosters = expandPosters; self.focusScale = focusScale; self.focusBorder = focusBorder
        self.focusShadow = focusShadow; self.focusGlow = focusGlow
    }
}

public struct LookDetail: Encodable, Sendable, Hashable {
    public var layout: LookDetailLayout
    public var descriptionLines: LookDescriptionLines
    public var cast: LookCast
    public var badgeStyle: LookBadgeStyle
    public var ratingStyle: LookRatingStyle
    public var sourceList: LookSourceList

    public init(layout: LookDetailLayout, descriptionLines: LookDescriptionLines, cast: LookCast,
                badgeStyle: LookBadgeStyle, ratingStyle: LookRatingStyle, sourceList: LookSourceList) {
        self.layout = layout; self.descriptionLines = descriptionLines; self.cast = cast
        self.badgeStyle = badgeStyle; self.ratingStyle = ratingStyle; self.sourceList = sourceList
    }
}

public struct LookPlayer: Encodable, Sendable, Hashable {
    public var controlBar: LookControlBar
    public var badges: LookPlayerBadges
    public var timeDisplay: LookTimeDisplay
    public var trackPanel: LookTrackPanel
    public var upNext: LookUpNext
    public var stillWatching: LookStillWatching

    public init(controlBar: LookControlBar, badges: LookPlayerBadges, timeDisplay: LookTimeDisplay,
                trackPanel: LookTrackPanel, upNext: LookUpNext, stillWatching: LookStillWatching) {
        self.controlBar = controlBar; self.badges = badges; self.timeDisplay = timeDisplay
        self.trackPanel = trackPanel; self.upNext = upNext; self.stillWatching = stillWatching
    }
}

// MARK: - Overrides

/// The deviations from the preset; every field optional. Encodes only what is set (no overrides → `{}`).
/// Decodes leniently: an unknown raw value or wrong type becomes `nil` and is noted, unknown keys are ignored.
/// The same shape as `values` of a configurator export, so Task 4.3 can read an export through this type.
public struct LookOverrides: Codable, Sendable, Hashable {
    public var global = Global()
    public var home = Home()
    public var detail = Detail()
    public var player = Player()

    public init() {}

    /// Number of overridden options ("Mein Look · angepasst", reset per option).
    public var count: Int { global.count + home.count + detail.count + player.count }
    public var isEmpty: Bool { count == 0 }

    /// `base`, overlaid with these overrides.
    public func applied(to base: LookValues) -> LookValues {
        var v = base
        global.apply(to: &v.global)
        home.apply(to: &v.home)
        detail.apply(to: &v.detail)
        player.apply(to: &v.player)
        return v
    }

    /// The overrides that turn `base` into `values` (only fields that differ).
    public static func difference(_ values: LookValues, from base: LookValues) -> LookOverrides {
        var o = LookOverrides()
        o.global = Global(values.global, base.global)
        o.home = Home(values.home, base.home)
        o.detail = Detail(values.detail, base.detail)
        o.player = Player(values.player, base.player)
        return o
    }

    enum CodingKeys: String, CodingKey { case global, home, detail, player }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let r = DecodeReportBox.of(decoder)
        global = c.decodeLenient(Global.self, forKey: .global, default: Global(), report: r)
        home = c.decodeLenient(Home.self, forKey: .home, default: Home(), report: r)
        detail = c.decodeLenient(Detail.self, forKey: .detail, default: Detail(), report: r)
        player = c.decodeLenient(Player.self, forKey: .player, default: Player(), report: r)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if global.count > 0 { try c.encode(global, forKey: .global) }
        if home.count > 0 { try c.encode(home, forKey: .home) }
        if detail.count > 0 { try c.encode(detail, forKey: .detail) }
        if player.count > 0 { try c.encode(player, forKey: .player) }
    }

    public struct Global: Codable, Sendable, Hashable {
        public var navigation: LookNavigation?
        public var clock: Bool?
        public var settingsLayout: LookSettingsLayout?
        public var accent: LookAccent?
        public var background: LookBackground?
        public var typeScale: LookTypeScale?
        public var typeCharacter: LookTypeCharacter?
        public var motion: LookMotion?

        public init() {}

        init(_ v: LookGlobal, _ b: LookGlobal) {
            navigation = differing(v.navigation, b.navigation); clock = differing(v.clock, b.clock)
            settingsLayout = differing(v.settingsLayout, b.settingsLayout); accent = differing(v.accent, b.accent)
            background = differing(v.background, b.background); typeScale = differing(v.typeScale, b.typeScale)
            typeCharacter = differing(v.typeCharacter, b.typeCharacter); motion = differing(v.motion, b.motion)
        }

        var count: Int {
            let all: [Any?] = [navigation, clock, settingsLayout, accent, background, typeScale, typeCharacter, motion]
            return all.compactMap { $0 }.count
        }

        func apply(to v: inout LookGlobal) {
            overlay(navigation, &v.navigation); overlay(clock, &v.clock); overlay(settingsLayout, &v.settingsLayout)
            overlay(accent, &v.accent); overlay(background, &v.background); overlay(typeScale, &v.typeScale)
            overlay(typeCharacter, &v.typeCharacter); overlay(motion, &v.motion)
        }

        enum CodingKeys: String, CodingKey {
            case navigation, clock, settingsLayout, accent, background, typeScale, typeCharacter, motion
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let r = DecodeReportBox.of(decoder)
            navigation = c.lenientOption(.navigation, r); clock = c.lenientOption(.clock, r)
            settingsLayout = c.lenientOption(.settingsLayout, r); accent = c.lenientOption(.accent, r)
            background = c.lenientOption(.background, r); typeScale = c.lenientOption(.typeScale, r)
            typeCharacter = c.lenientOption(.typeCharacter, r); motion = c.lenientOption(.motion, r)
        }
    }

    public struct Home: Codable, Sendable, Hashable {
        public var heroStyle: LookHeroStyle?
        public var heroInfo: LookHeroInfo?
        public var heroTitle: LookHeroTitle?
        public var backdropFollowsFocus: Bool?
        public var cardShape: LookCardShape?
        public var cardSize: LookCardSize?
        public var corners: LookCorners?
        public var rowSpacing: LookRowSpacing?
        public var rowTitle: LookRowTitle?
        public var cardTitles: LookCardTitles?
        public var expandPosters: Bool?
        public var focusScale: LookFocusScale?
        public var focusBorder: LookFocusBorder?
        public var focusShadow: LookFocusShadow?
        public var focusGlow: Bool?

        public init() {}

        init(_ v: LookHome, _ b: LookHome) {
            heroStyle = differing(v.heroStyle, b.heroStyle); heroInfo = differing(v.heroInfo, b.heroInfo)
            heroTitle = differing(v.heroTitle, b.heroTitle)
            backdropFollowsFocus = differing(v.backdropFollowsFocus, b.backdropFollowsFocus)
            cardShape = differing(v.cardShape, b.cardShape); cardSize = differing(v.cardSize, b.cardSize)
            corners = differing(v.corners, b.corners); rowSpacing = differing(v.rowSpacing, b.rowSpacing)
            rowTitle = differing(v.rowTitle, b.rowTitle); cardTitles = differing(v.cardTitles, b.cardTitles)
            expandPosters = differing(v.expandPosters, b.expandPosters)
            focusScale = differing(v.focusScale, b.focusScale); focusBorder = differing(v.focusBorder, b.focusBorder)
            focusShadow = differing(v.focusShadow, b.focusShadow); focusGlow = differing(v.focusGlow, b.focusGlow)
        }

        var count: Int {
            let all: [Any?] = [heroStyle, heroInfo, heroTitle, backdropFollowsFocus, cardShape, cardSize, corners,
                               rowSpacing, rowTitle, cardTitles, expandPosters, focusScale, focusBorder, focusShadow,
                               focusGlow]
            return all.compactMap { $0 }.count
        }

        func apply(to v: inout LookHome) {
            overlay(heroStyle, &v.heroStyle); overlay(heroInfo, &v.heroInfo); overlay(heroTitle, &v.heroTitle)
            overlay(backdropFollowsFocus, &v.backdropFollowsFocus); overlay(cardShape, &v.cardShape)
            overlay(cardSize, &v.cardSize); overlay(corners, &v.corners); overlay(rowSpacing, &v.rowSpacing)
            overlay(rowTitle, &v.rowTitle); overlay(cardTitles, &v.cardTitles)
            overlay(expandPosters, &v.expandPosters); overlay(focusScale, &v.focusScale)
            overlay(focusBorder, &v.focusBorder); overlay(focusShadow, &v.focusShadow)
            overlay(focusGlow, &v.focusGlow)
        }

        enum CodingKeys: String, CodingKey {
            case heroStyle, heroInfo, heroTitle, backdropFollowsFocus, cardShape, cardSize, corners, rowSpacing
            case rowTitle, cardTitles, expandPosters, focusScale, focusBorder, focusShadow, focusGlow
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let r = DecodeReportBox.of(decoder)
            heroStyle = c.lenientOption(.heroStyle, r); heroInfo = c.lenientOption(.heroInfo, r)
            heroTitle = c.lenientOption(.heroTitle, r)
            backdropFollowsFocus = c.lenientOption(.backdropFollowsFocus, r)
            cardShape = c.lenientOption(.cardShape, r); cardSize = c.lenientOption(.cardSize, r)
            corners = c.lenientOption(.corners, r); rowSpacing = c.lenientOption(.rowSpacing, r)
            rowTitle = c.lenientOption(.rowTitle, r); cardTitles = c.lenientOption(.cardTitles, r)
            expandPosters = c.lenientOption(.expandPosters, r); focusScale = c.lenientOption(.focusScale, r)
            focusBorder = c.lenientOption(.focusBorder, r); focusShadow = c.lenientOption(.focusShadow, r)
            focusGlow = c.lenientOption(.focusGlow, r)
        }
    }

    public struct Detail: Codable, Sendable, Hashable {
        public var layout: LookDetailLayout?
        public var descriptionLines: LookDescriptionLines?
        public var cast: LookCast?
        public var badgeStyle: LookBadgeStyle?
        public var ratingStyle: LookRatingStyle?
        public var sourceList: LookSourceList?

        public init() {}

        init(_ v: LookDetail, _ b: LookDetail) {
            layout = differing(v.layout, b.layout)
            descriptionLines = differing(v.descriptionLines, b.descriptionLines)
            cast = differing(v.cast, b.cast); badgeStyle = differing(v.badgeStyle, b.badgeStyle)
            ratingStyle = differing(v.ratingStyle, b.ratingStyle); sourceList = differing(v.sourceList, b.sourceList)
        }

        var count: Int {
            let all: [Any?] = [layout, descriptionLines, cast, badgeStyle, ratingStyle, sourceList]
            return all.compactMap { $0 }.count
        }

        func apply(to v: inout LookDetail) {
            overlay(layout, &v.layout); overlay(descriptionLines, &v.descriptionLines); overlay(cast, &v.cast)
            overlay(badgeStyle, &v.badgeStyle); overlay(ratingStyle, &v.ratingStyle)
            overlay(sourceList, &v.sourceList)
        }

        enum CodingKeys: String, CodingKey { case layout, descriptionLines, cast, badgeStyle, ratingStyle, sourceList }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let r = DecodeReportBox.of(decoder)
            layout = c.lenientOption(.layout, r); descriptionLines = c.lenientOption(.descriptionLines, r)
            cast = c.lenientOption(.cast, r); badgeStyle = c.lenientOption(.badgeStyle, r)
            ratingStyle = c.lenientOption(.ratingStyle, r); sourceList = c.lenientOption(.sourceList, r)
        }
    }

    public struct Player: Codable, Sendable, Hashable {
        public var controlBar: LookControlBar?
        public var badges: LookPlayerBadges?
        public var timeDisplay: LookTimeDisplay?
        public var trackPanel: LookTrackPanel?
        public var upNext: LookUpNext?
        public var stillWatching: LookStillWatching?

        public init() {}

        init(_ v: LookPlayer, _ b: LookPlayer) {
            controlBar = differing(v.controlBar, b.controlBar); badges = differing(v.badges, b.badges)
            timeDisplay = differing(v.timeDisplay, b.timeDisplay); trackPanel = differing(v.trackPanel, b.trackPanel)
            upNext = differing(v.upNext, b.upNext); stillWatching = differing(v.stillWatching, b.stillWatching)
        }

        var count: Int {
            let all: [Any?] = [controlBar, badges, timeDisplay, trackPanel, upNext, stillWatching]
            return all.compactMap { $0 }.count
        }

        func apply(to v: inout LookPlayer) {
            overlay(controlBar, &v.controlBar); overlay(badges, &v.badges); overlay(timeDisplay, &v.timeDisplay)
            overlay(trackPanel, &v.trackPanel); overlay(upNext, &v.upNext); overlay(stillWatching, &v.stillWatching)
        }

        enum CodingKeys: String, CodingKey { case controlBar, badges, timeDisplay, trackPanel, upNext, stillWatching }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let r = DecodeReportBox.of(decoder)
            controlBar = c.lenientOption(.controlBar, r); badges = c.lenientOption(.badges, r)
            timeDisplay = c.lenientOption(.timeDisplay, r); trackPanel = c.lenientOption(.trackPanel, r)
            upNext = c.lenientOption(.upNext, r); stillWatching = c.lenientOption(.stillWatching, r)
        }
    }
}

/// `value` if it differs from `base`, else `nil`.
private func differing<T: Equatable>(_ value: T, _ base: T) -> T? { value == base ? nil : value }

/// Overwrites `value` with `override` when one is set.
private func overlay<T>(_ override: T?, _ value: inout T) { if let override { value = override } }

extension KeyedDecodingContainer {
    /// One optional override: missing or `null` → `nil`; unreadable → `nil`, path noted. Never throws.
    fileprivate func lenientOption<T: Decodable>(_ key: Key, _ report: DecodeReportBox) -> T? {
        decodeLenient(T?.self, forKey: key, default: nil, report: report)
    }
}
