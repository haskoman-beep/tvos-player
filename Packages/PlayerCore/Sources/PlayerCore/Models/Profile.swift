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

    public init(id: UUID = UUID(), name: String, language: AppLanguage = .de, audioPriority: [String] = ["de", "en", "orig"],
                subtitlesEnabled: Bool = false, subtitleLanguage: String = "de", progressSource: ProgressSource = .local,
                addons: [InstalledAddon] = [], collections: [MediaCollection] = [], home: HomeLayout = HomeLayout(),
                apiKeys: [String: String] = [:]) {
        self.id = id; self.name = name; self.language = language; self.audioPriority = audioPriority
        self.subtitlesEnabled = subtitlesEnabled; self.subtitleLanguage = subtitleLanguage
        self.progressSource = progressSource; self.addons = addons; self.collections = collections
        self.home = home; self.apiKeys = apiKeys
    }

    public static func makeDefault(name: String = "Ich") -> Profile {
        Profile(name: name, home: HomeLayout(rows: [HomeRow(content: .list(.continueWatching), style: .landscape)]))
    }
}
