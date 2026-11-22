import Foundation

/// Wo die Hauptnavigation sitzt.
public enum NavigationStyle: String, Codable, Sendable, CaseIterable { case sidebar, top }

/// Akzentfarbe; die Farbzuordnung liegt in der App.
public enum AccentChoice: String, Codable, Sendable, CaseIterable { case blue, purple, pink, orange, green, white }

/// Kachelgröße der Reihen.
public enum CardSize: String, Codable, Sendable, CaseIterable {
    case small, medium, large

    public var scale: CGFloat {
        switch self {
        case .small: 0.85
        case .medium: 1.0
        case .large: 1.2
        }
    }
}

/// Aussehen-Einstellungen eines Profils.
public struct Appearance: Codable, Sendable, Hashable {
    public var navigation: NavigationStyle
    public var accent: AccentChoice
    public var cardSize: CardSize
    public var heroEnabled: Bool
    /// Reihe, deren Titel im Hero laufen; nil = automatisch.
    public var heroRowID: UUID?
    public var expandPosters: Bool
    /// Quellen vorladen, wenn der Fokus 350 ms auf einer Kachel ruht.
    public var prefetchStreams: Bool
    /// Qualitäts-Plaketten: welche Typen, Text oder Logo, auf Postern (Task 8).
    public var badges: BadgeSettings
    /// Welle E-a: Plaketten auf Postern, Bewertungsauswahl, Bilder vom Metadaten-Addon.
    public var titles: TitleDisplaySettings
    /// Wave F-o: "Ton bei Kachel-Animation" – a focus video with a sound track plays its sound once per focus.
    /// Default off.
    public var tileAnimationSound: Bool

    public init(navigation: NavigationStyle = .sidebar, accent: AccentChoice = .blue, cardSize: CardSize = .medium,
                heroEnabled: Bool = true, heroRowID: UUID? = nil, expandPosters: Bool = true, prefetchStreams: Bool = true,
                badges: BadgeSettings = BadgeSettings(), titles: TitleDisplaySettings = TitleDisplaySettings(),
                tileAnimationSound: Bool = false) {
        self.navigation = navigation; self.accent = accent; self.cardSize = cardSize
        self.heroEnabled = heroEnabled; self.heroRowID = heroRowID; self.expandPosters = expandPosters
        self.prefetchStreams = prefetchStreams
        self.badges = badges
        self.titles = titles
        self.tileAnimationSound = tileAnimationSound
    }

    enum CodingKeys: String, CodingKey {
        case navigation, accent, cardSize, heroEnabled, heroRowID, expandPosters, prefetchStreams, badges, titles, tileAnimationSound
    }

    /// Fehlende Felder bekommen Standardwerte.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Appearance()
        navigation = try c.decodeIfPresent(NavigationStyle.self, forKey: .navigation) ?? d.navigation
        accent = try c.decodeIfPresent(AccentChoice.self, forKey: .accent) ?? d.accent
        cardSize = try c.decodeIfPresent(CardSize.self, forKey: .cardSize) ?? d.cardSize
        heroEnabled = try c.decodeIfPresent(Bool.self, forKey: .heroEnabled) ?? d.heroEnabled
        heroRowID = try c.decodeIfPresent(UUID.self, forKey: .heroRowID)
        expandPosters = try c.decodeIfPresent(Bool.self, forKey: .expandPosters) ?? d.expandPosters
        prefetchStreams = try c.decodeIfPresent(Bool.self, forKey: .prefetchStreams) ?? d.prefetchStreams
        badges = try c.decodeIfPresent(BadgeSettings.self, forKey: .badges) ?? d.badges
        titles = try c.decodeIfPresent(TitleDisplaySettings.self, forKey: .titles) ?? d.titles
        tileAnimationSound = try c.decodeIfPresent(Bool.self, forKey: .tileAnimationSound) ?? d.tileAnimationSound
    }
}

extension HomeLayout {
    /// Reihe, deren Titel im Hero laufen: explizit gewählt, sonst erste Hero-Reihe,
    /// sonst erste Liste außer Weiterschauen und „Heute neu“; nil, wenn der Hero aus ist.
    public func heroSource(_ a: Appearance) -> HomeRow? {
        guard a.heroEnabled else { return nil }
        if let id = a.heroRowID, let r = rows.first(where: { $0.id == id }) { return r }
        if let r = rows.first(where: { $0.style == .hero }) { return r }
        return rows.first { row in
            if case .list(let s) = row.content, s.kind != .continueWatching, s.kind != .upcoming { return true }
            return false
        }
    }

    /// Alle Reihen unter dem Hero; eine Hero-Reihe, die selbst Hero-Quelle ist, entfällt.
    public func rowsBelowHero(_ a: Appearance) -> [HomeRow] {
        guard let src = heroSource(a), src.style == .hero else { return rows }
        return rows.filter { $0.id != src.id }
    }
}
