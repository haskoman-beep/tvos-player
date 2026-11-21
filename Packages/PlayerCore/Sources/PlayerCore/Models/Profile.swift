import Foundation

public enum AppLanguage: String, Codable, Sendable, CaseIterable { case de, en }

/// Wo Fortschritt/Gesehen als Hauptquelle liegt. Lokal wird immer mitgeschrieben.
public enum ProgressSource: String, Codable, Sendable, CaseIterable { case local, trakt, simkl }

public struct Profile: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var language: AppLanguage
    /// Sprachcodes in Vorrang-Reihenfolge; "orig" = Originalspur.
    public var audioPriority: [String]
    public var subtitlesEnabled: Bool
    public var subtitleLanguage: String
    public var progressSource: ProgressSource
    public var addons: [InstalledAddon]
    public var collections: [MediaCollection]
    public var home: HomeLayout
    /// z. B. "tmdb", "mdblist", "tvdb". Liegt bewusst im Profil (Export enthält sie, Gerät ist privat).
    public var apiKeys: [String: String]
    /// Nächste Folge automatisch starten.
    public var autoplayNext: Bool
    /// Anmeldungen bei "trakt" / "simkl".
    public var syncTokens: [String: SyncToken]
    /// Aussehen (Navigation, Akzent, Kachelgröße, Hero).
    public var appearance: Appearance

    public init(id: UUID = UUID(), name: String, language: AppLanguage = .de, audioPriority: [String] = ["de", "en", "orig"],
                subtitlesEnabled: Bool = false, subtitleLanguage: String = "de", progressSource: ProgressSource = .local,
                addons: [InstalledAddon] = [], collections: [MediaCollection] = [], home: HomeLayout = HomeLayout(),
                apiKeys: [String: String] = [:], autoplayNext: Bool = true, syncTokens: [String: SyncToken] = [:],
                appearance: Appearance = Appearance()) {
        self.id = id; self.name = name; self.language = language; self.audioPriority = audioPriority
        self.subtitlesEnabled = subtitlesEnabled; self.subtitleLanguage = subtitleLanguage
        self.progressSource = progressSource; self.addons = addons; self.collections = collections
        self.home = home; self.apiKeys = apiKeys; self.autoplayNext = autoplayNext
        self.syncTokens = syncTokens; self.appearance = appearance
    }

    enum CodingKeys: String, CodingKey {
        case id, name, language, audioPriority, subtitlesEnabled, subtitleLanguage, progressSource
        case addons, collections, home, apiKeys, autoplayNext, syncTokens, appearance
    }

    /// Fehlende Felder (ältere Sicherungen, neue Einstellungen) bekommen Standardwerte statt das Profil zu verwerfen.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Profile(name: "")
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Profil"
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? d.language
        audioPriority = try c.decodeIfPresent([String].self, forKey: .audioPriority) ?? d.audioPriority
        subtitlesEnabled = try c.decodeIfPresent(Bool.self, forKey: .subtitlesEnabled) ?? d.subtitlesEnabled
        subtitleLanguage = try c.decodeIfPresent(String.self, forKey: .subtitleLanguage) ?? d.subtitleLanguage
        progressSource = try c.decodeIfPresent(ProgressSource.self, forKey: .progressSource) ?? d.progressSource
        addons = try c.decodeIfPresent([InstalledAddon].self, forKey: .addons) ?? []
        collections = try c.decodeIfPresent([MediaCollection].self, forKey: .collections) ?? []
        home = try c.decodeIfPresent(HomeLayout.self, forKey: .home) ?? d.home
        apiKeys = try c.decodeIfPresent([String: String].self, forKey: .apiKeys) ?? [:]
        autoplayNext = try c.decodeIfPresent(Bool.self, forKey: .autoplayNext) ?? d.autoplayNext
        syncTokens = try c.decodeIfPresent([String: SyncToken].self, forKey: .syncTokens) ?? [:]
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? d.appearance
    }

    public static func makeDefault(name: String = "Ich") -> Profile {
        Profile(name: name, home: HomeLayout(rows: [HomeRow(content: .list(.continueWatching), style: .landscape)]))
    }
}
