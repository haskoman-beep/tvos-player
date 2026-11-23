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
    // Wave S round 2: sound shaping (`audioShaping`) and picture mode (`displayMode`) moved to `DeviceSettings`.
    // Old profiles that still hold the keys decode fine; the keys are ignored and no longer written.
    /// Quellen-Sortierung und Extras (Welle C-d).
    public var sources: SourceSettings = SourceSettings()
    /// Welle D-a: Spur-Wahl je Serie merken, Bildschirmschoner in der Pause.
    public var player: PlayerComfortSettings = PlayerComfortSettings()
    /// Welle F-e: am Handy ausgeblendete Reihen, vollständig (Stil, ID für den Hero-Bezug), neueste zuletzt,
    /// höchstens `HomeLayout.hiddenLimit`. „Wieder einblenden“ hängt sie unverändert unten an.
    public var hiddenRows: [HomeRow] = []
    /// Task 1.2: hidden rows this build cannot read (newer build), kept as raw JSON and written back after `hiddenRows`.
    public var unknownHiddenRows: [JSONValue] = []
    /// Wave U: look of text subtitles, with its own brightness for HDR/DV (default = the look before wave U).
    public var subtitleStyle: SubtitleStyle = SubtitleStyle()
    /// Wave P-a: skip action per segment type and the card after a movie.
    public var skip: SkipSettings = SkipSettings()

    public init(id: UUID = UUID(), name: String, language: AppLanguage = .de, audioPriority: [String] = ["de", "en", "orig"],
                subtitleMode: SubtitleMode = .forcedOnly, subtitleLanguage: String = "de", progressSource: ProgressSource = .local,
                addons: [InstalledAddon] = [], collections: [MediaCollection] = [], home: HomeLayout = HomeLayout(),
                apiKeys: [String: String] = [:], autoplayNext: Bool = true, stillWatchingAfter: Int = StillWatchingCounter.defaultLimit, syncTokens: [String: SyncToken] = [:],
                appearance: Appearance = Appearance(), diskCache: DiskCacheSettings = DiskCacheSettings()) {
        self.id = id; self.name = name; self.language = language; self.audioPriority = audioPriority
        self.subtitleMode = subtitleMode; self.subtitleLanguage = subtitleLanguage
        self.progressSource = progressSource; self.addons = addons; self.collections = collections
        self.home = home; self.apiKeys = apiKeys; self.autoplayNext = autoplayNext
        self.stillWatchingAfter = stillWatchingAfter
        self.syncTokens = syncTokens; self.appearance = appearance
        self.diskCache = diskCache
    }

    enum CodingKeys: String, CodingKey {
        case id, name, language, audioPriority, subtitleMode, subtitleLanguage, progressSource
        case addons, collections, home, apiKeys, autoplayNext, stillWatchingAfter, syncTokens, appearance
        case diskCache
        case addonTimeout
        case sources
        case player
        case hiddenRows
        case subtitleStyle
        case skip
    }
    /// Nur zum Lesen alter Profile.
    private enum LegacyKeys: String, CodingKey { case subtitlesEnabled }

    /// Fehlende Felder (ältere Sicherungen, neue Einstellungen) bekommen Standardwerte statt das Profil zu verwerfen.
    /// Task 1.2: ein unlesbarer Wert (unbekannter Enum-Fall eines neueren Builds, falscher Typ) fällt ebenfalls auf
    /// den Standard und steht im `DecodeReport`. Nur ohne lesbare `id` wirft das Profil (`StoredProfiles` überspringt es).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let r = DecodeReportBox.of(decoder)
        let d = Profile(name: "")
        id = try c.decode(UUID.self, forKey: .id)
        name = c.decodeLenient(String.self, forKey: .name, default: "Profil", report: r)
        language = c.decodeLenient(AppLanguage.self, forKey: .language, default: d.language, report: r)
        audioPriority = c.decodeLenient([String].self, forKey: .audioPriority, default: d.audioPriority, report: r)
        if let mode = try? c.decodeIfPresent(SubtitleMode.self, forKey: .subtitleMode) {
            subtitleMode = mode
        } else {
            if c.contains(.subtitleMode), (try? c.decodeNil(forKey: .subtitleMode)) != true {
                r.note(c.codingPath + [CodingKeys.subtitleMode])
            }
            let legacy = try? decoder.container(keyedBy: LegacyKeys.self)
            let wasOn = (try? legacy?.decodeIfPresent(Bool.self, forKey: .subtitlesEnabled)) ?? nil
            subtitleMode = wasOn == true ? .always : d.subtitleMode
        }
        subtitleLanguage = c.decodeLenient(String.self, forKey: .subtitleLanguage, default: d.subtitleLanguage, report: r)
        progressSource = c.decodeLenient(ProgressSource.self, forKey: .progressSource, default: d.progressSource, report: r)
        addons = c.decodeLenientList(InstalledAddon.self, forKey: .addons, report: r)
        collections = c.decodeLenientList(MediaCollection.self, forKey: .collections, report: r)
        home = c.decodeLenient(HomeLayout.self, forKey: .home, default: d.home, report: r)
        apiKeys = c.decodeLenient([String: String].self, forKey: .apiKeys, default: [:], report: r)
        autoplayNext = c.decodeLenient(Bool.self, forKey: .autoplayNext, default: d.autoplayNext, report: r)
        stillWatchingAfter = c.decodeLenient(Int.self, forKey: .stillWatchingAfter, default: d.stillWatchingAfter, report: r)
        syncTokens = c.decodeLenientMap(SyncToken.self, forKey: .syncTokens, report: r)
        appearance = c.decodeLenient(Appearance.self, forKey: .appearance, default: d.appearance, report: r)
        diskCache = c.decodeLenient(DiskCacheSettings.self, forKey: .diskCache, default: d.diskCache, report: r)
        addonTimeout = c.decodeLenient(Double.self, forKey: .addonTimeout, default: d.addonTimeout, report: r)
        sources = c.decodeLenient(SourceSettings.self, forKey: .sources, default: d.sources, report: r)
        player = c.decodeLenient(PlayerComfortSettings.self, forKey: .player, default: d.player, report: r)
        (hiddenRows, unknownHiddenRows) = c.decodeSalvagedList(HomeRow.self, forKey: .hiddenRows, report: r)
        subtitleStyle = c.decodeLenient(SubtitleStyle.self, forKey: .subtitleStyle, default: d.subtitleStyle, report: r)
        skip = c.decodeLenient(SkipSettings.self, forKey: .skip, default: d.skip, report: r)
    }

    /// Same keys, order and format as the former synthesized encoding; only `hiddenRows` gets the raw leftovers
    /// (`unknownHiddenRows`) appended.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(language, forKey: .language)
        try c.encode(audioPriority, forKey: .audioPriority)
        try c.encode(subtitleMode, forKey: .subtitleMode)
        try c.encode(subtitleLanguage, forKey: .subtitleLanguage)
        try c.encode(progressSource, forKey: .progressSource)
        try c.encode(addons, forKey: .addons)
        try c.encode(collections, forKey: .collections)
        try c.encode(home, forKey: .home)
        try c.encode(apiKeys, forKey: .apiKeys)
        try c.encode(autoplayNext, forKey: .autoplayNext)
        try c.encode(stillWatchingAfter, forKey: .stillWatchingAfter)
        try c.encode(syncTokens, forKey: .syncTokens)
        try c.encode(appearance, forKey: .appearance)
        try c.encode(diskCache, forKey: .diskCache)
        try c.encode(addonTimeout, forKey: .addonTimeout)
        try c.encode(sources, forKey: .sources)
        try c.encode(player, forKey: .player)
        var hidden = c.nestedUnkeyedContainer(forKey: .hiddenRows)
        for row in hiddenRows { try hidden.encode(row) }
        for raw in unknownHiddenRows { try hidden.encode(raw) }
        try c.encode(subtitleStyle, forKey: .subtitleStyle)
        try c.encode(skip, forKey: .skip)
    }

    public static func makeDefault(name: String = "Ich") -> Profile {
        Profile(name: name, home: HomeLayout(rows: [HomeRow(content: .list(.continueWatching), style: .landscape)]))
    }
}
