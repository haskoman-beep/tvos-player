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

    /// Fehlende oder unlesbare Felder bekommen Standardwerte (unlesbare stehen im `DecodeReport`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let r = DecodeReportBox.of(decoder)
        let d = Appearance()
        navigation = c.decodeLenient(NavigationStyle.self, forKey: .navigation, default: d.navigation, report: r)
        accent = c.decodeLenient(AccentChoice.self, forKey: .accent, default: d.accent, report: r)
        cardSize = c.decodeLenient(CardSize.self, forKey: .cardSize, default: d.cardSize, report: r)
        heroEnabled = c.decodeLenient(Bool.self, forKey: .heroEnabled, default: d.heroEnabled, report: r)
        heroRowID = c.decodeLenient(UUID?.self, forKey: .heroRowID, default: nil, report: r)
        expandPosters = c.decodeLenient(Bool.self, forKey: .expandPosters, default: d.expandPosters, report: r)
        prefetchStreams = c.decodeLenient(Bool.self, forKey: .prefetchStreams, default: d.prefetchStreams, report: r)
        badges = c.decodeLenient(BadgeSettings.self, forKey: .badges, default: d.badges, report: r)
        titles = c.decodeLenient(TitleDisplaySettings.self, forKey: .titles, default: d.titles, report: r)
        tileAnimationSound = c.decodeLenient(Bool.self, forKey: .tileAnimationSound, default: d.tileAnimationSound, report: r)
    }
}

extension HomeLayout {
    /// Reihe, deren Titel im Hero laufen: explizit gewählt, sonst erste Hero-Reihe,
    /// sonst erste Liste außer Weiterschauen und „Heute neu“; nil, wenn der Hero aus ist.
    public func heroSource(_ a: Appearance) -> HomeRow? {
        guard a.heroEnabled else { return nil }
        // Task 4.1a round 2 (M2): only list rows can feed the hero (a collection holds folders, nothing to play);
        // a stored choice or hero style on a collection falls through to the next rule.
        func isList(_ r: HomeRow) -> Bool { if case .list = r.content { true } else { false } }
        if let id = a.heroRowID, let r = rows.first(where: { $0.id == id }), isList(r) { return r }
        if let r = rows.first(where: { $0.style == .hero && isList($0) }) { return r }
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
