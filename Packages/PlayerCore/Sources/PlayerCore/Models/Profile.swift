import Foundation

public enum AppLanguage: String, Codable, Sendable, CaseIterable { case de, en }

/// Wo Fortschritt/Gesehen als Hauptquelle liegt. Lokal wird immer mitgeschrieben.
public enum ProgressSource: String, Codable, Sendable, CaseIterable { case local, trakt, simkl }

/// Automatische Untertitel beim Start: aus, nur erzwungene (Schilder/fremdsprachige Stellen) oder immer.
public enum SubtitleMode: String, Codable, Sendable, CaseIterable { case off, forcedOnly, always }

public struct Profile: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var language: AppLanguage
    /// Sprachcodes in Vorrang-Reihenfolge; "orig" = Originalspur.
    public var audioPriority: [String]
    /// Ersetzt das alte `subtitlesEnabled` (true → `.always`, sonst Standard `.forcedOnly`).
    public var subtitleMode: SubtitleMode
    public var subtitleLanguage: String
    public var progressSource: ProgressSource
    public var addons: [InstalledAddon]
    public var collections: [MediaCollection]
    public var home: HomeLayout
    /// z. B. "tmdb", "mdblist", "tvdb". Liegt bewusst im Profil (Export enthält sie, Gerät ist privat).
    public var apiKeys: [String: String]
    /// Nächste Folge automatisch starten.
    public var autoplayNext: Bool
    /// „Noch da?“ nach so vielen automatisch gestarteten Folgen ohne Tastendruck (0 = aus, Standard 3).
    public var stillWatchingAfter: Int
    /// Anmeldungen bei "trakt" / "simkl".
    public var syncTokens: [String: SyncToken]
    /// Aussehen (Navigation, Akzent, Kachelgröße, Hero).
    public var appearance: Appearance
    /// Plattencache für den laufenden Film (Standard aus).
    public var diskCache: DiskCacheSettings
    /// Welle C-a: Zeitgrenze je Addon bei der Quellensuche in Sekunden (Standard `AddonSearch.defaultTimeout`).
    public var addonTimeout: Double = AddonSearch.defaultTimeout
    /// Ton: Nachtmodus, Dialog, Lautheit, Versatz, Brücke (Standard alles aus).
    public var audioShaping: AudioShapingSettings
    /// Bildmodus: Dolby-Vision-Angabe, FEL, HDMI-Modus zwischen Folgen halten (Welle C-c).
    public var displayMode: DisplayModeSettings
    /// Quellen-Sortierung und Extras (Welle C-d).
    public var sources: SourceSettings = SourceSettings()
    /// Welle D-a: Spur-Wahl je Serie merken, Bildschirmschoner in der Pause.
    public var player: PlayerComfortSettings = PlayerComfortSettings()
    /// Welle F-e: am Handy ausgeblendete Reihen, vollständig (Stil, ID für den Hero-Bezug), neueste zuletzt,
    /// höchstens `HomeLayout.hiddenLimit`. „Wieder einblenden“ hängt sie unverändert unten an.
    public var hiddenRows: [HomeRow] = []
    /// Wave U: look of text subtitles, with its own brightness for HDR/DV (default = the look before wave U).
    public var subtitleStyle: SubtitleStyle = SubtitleStyle()

    public init(id: UUID = UUID(), name: String, language: AppLanguage = .de, audioPriority: [String] = ["de", "en", "orig"],
                subtitleMode: SubtitleMode = .forcedOnly, subtitleLanguage: String = "de", progressSource: ProgressSource = .local,
                addons: [InstalledAddon] = [], collections: [MediaCollection] = [], home: HomeLayout = HomeLayout(),
                apiKeys: [String: String] = [:], autoplayNext: Bool = true, stillWatchingAfter: Int = StillWatchingCounter.defaultLimit, syncTokens: [String: SyncToken] = [:],
                appearance: Appearance = Appearance(), diskCache: DiskCacheSettings = DiskCacheSettings(),
                audioShaping: AudioShapingSettings = AudioShapingSettings(),
                displayMode: DisplayModeSettings = DisplayModeSettings()) {
        self.id = id; self.name = name; self.language = language; self.audioPriority = audioPriority
        self.subtitleMode = subtitleMode; self.subtitleLanguage = subtitleLanguage
        self.progressSource = progressSource; self.addons = addons; self.collections = collections
        self.home = home; self.apiKeys = apiKeys; self.autoplayNext = autoplayNext
        self.stillWatchingAfter = stillWatchingAfter
        self.syncTokens = syncTokens; self.appearance = appearance
        self.diskCache = diskCache
        self.audioShaping = audioShaping
        self.displayMode = displayMode
    }

    enum CodingKeys: String, CodingKey {
        case id, name, language, audioPriority, subtitleMode, subtitleLanguage, progressSource
        case addons, collections, home, apiKeys, autoplayNext, stillWatchingAfter, syncTokens, appearance
        case diskCache, audioShaping, displayMode
        case addonTimeout
        case sources
        case player
        case hiddenRows
        case subtitleStyle
    }
    /// Nur zum Lesen alter Profile.
    private enum LegacyKeys: String, CodingKey { case subtitlesEnabled }

    /// Fehlende Felder (ältere Sicherungen, neue Einstellungen) bekommen Standardwerte statt das Profil zu verwerfen.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Profile(name: "")
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Profil"
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? d.language
        audioPriority = try c.decodeIfPresent([String].self, forKey: .audioPriority) ?? d.audioPriority
        if let mode = try? c.decodeIfPresent(SubtitleMode.self, forKey: .subtitleMode) {
            subtitleMode = mode
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            let wasOn = (try? legacy.decodeIfPresent(Bool.self, forKey: .subtitlesEnabled)) ?? nil
            subtitleMode = wasOn == true ? .always : d.subtitleMode
        }
        subtitleLanguage = try c.decodeIfPresent(String.self, forKey: .subtitleLanguage) ?? d.subtitleLanguage
        progressSource = try c.decodeIfPresent(ProgressSource.self, forKey: .progressSource) ?? d.progressSource
        addons = try c.decodeIfPresent([InstalledAddon].self, forKey: .addons) ?? []
        collections = try c.decodeIfPresent([MediaCollection].self, forKey: .collections) ?? []
        home = try c.decodeIfPresent(HomeLayout.self, forKey: .home) ?? d.home
        apiKeys = try c.decodeIfPresent([String: String].self, forKey: .apiKeys) ?? [:]
        autoplayNext = try c.decodeIfPresent(Bool.self, forKey: .autoplayNext) ?? d.autoplayNext
        stillWatchingAfter = try c.decodeIfPresent(Int.self, forKey: .stillWatchingAfter) ?? d.stillWatchingAfter
        syncTokens = try c.decodeIfPresent([String: SyncToken].self, forKey: .syncTokens) ?? [:]
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? d.appearance
        diskCache = try c.decodeIfPresent(DiskCacheSettings.self, forKey: .diskCache) ?? d.diskCache
        addonTimeout = try c.decodeIfPresent(Double.self, forKey: .addonTimeout) ?? d.addonTimeout
        audioShaping = try c.decodeIfPresent(AudioShapingSettings.self, forKey: .audioShaping) ?? d.audioShaping
        displayMode = try c.decodeIfPresent(DisplayModeSettings.self, forKey: .displayMode) ?? d.displayMode
        sources = (try? c.decodeIfPresent(SourceSettings.self, forKey: .sources)) ?? nil ?? d.sources
        player = (try? c.decodeIfPresent(PlayerComfortSettings.self, forKey: .player)) ?? nil ?? d.player
        hiddenRows = (try? c.decodeIfPresent([HomeRow].self, forKey: .hiddenRows)) ?? nil ?? []
        subtitleStyle = (try? c.decodeIfPresent(SubtitleStyle.self, forKey: .subtitleStyle)) ?? nil ?? d.subtitleStyle
    }

    public static func makeDefault(name: String = "Ich") -> Profile {
        Profile(name: name, home: HomeLayout(rows: [HomeRow(content: .list(.continueWatching), style: .landscape)]))
    }
}
