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
    public var appearance: Appearance {
        didSet { followOldFields(oldAppearance: oldValue, oldPlayer: player) }
    }
    /// Plattencache für den laufenden Film (Standard aus).
    public var diskCache: DiskCacheSettings
    /// Welle C-a: Zeitgrenze je Addon bei der Quellensuche in Sekunden (Standard `AddonSearch.defaultTimeout`).
    public var addonTimeout: Double = AddonSearch.defaultTimeout
    // Wave S round 2: sound shaping (`audioShaping`) and picture mode (`displayMode`) moved to `DeviceSettings`.
    // Old profiles that still hold the keys decode fine; the keys are ignored and no longer written.
    /// Quellen-Sortierung und Extras (Welle C-d).
    public var sources: SourceSettings = SourceSettings()
    /// Welle D-a: Spur-Wahl je Serie merken, Bildschirmschoner in der Pause.
    public var player: PlayerComfortSettings = PlayerComfortSettings() {
        didSet { followOldFields(oldAppearance: appearance, oldPlayer: oldValue) }
    }
    /// Welle F-e: am Handy ausgeblendete Reihen, vollständig (Stil, ID für den Hero-Bezug), neueste zuletzt,
    /// höchstens `HomeLayout.hiddenLimit`. „Wieder einblenden“ hängt sie unverändert unten an.
    public var hiddenRows: [HomeRow] = []
    /// Task 1.2: hidden rows this build cannot read (newer build), kept as raw JSON and written back after `hiddenRows`.
    public var unknownHiddenRows: [JSONValue] = []
    /// Phase 0a: addons, collections, API keys and logins this build cannot read, kept as raw JSON and written back
    /// (lists after the readable entries). Before, they were skipped on load and the next save lost them for good.
    public var unknownAddons: [JSONValue] = []
    public var unknownCollections: [JSONValue] = []
    public var unknownApiKeys: [String: JSONValue] = [:]
    public var unknownSyncTokens: [String: JSONValue] = [:]
    /// Wave U: look of text subtitles, with its own brightness for HDR/DV (default = the look before wave U).
    public var subtitleStyle: SubtitleStyle = SubtitleStyle()
    /// Wave P-a: skip action per segment type and the card after a movie.
    public var skip: SkipSettings = SkipSettings()
    /// Task 4.2: the look (preset "Mein Look" plus overrides). Missing in older profiles: built once from
    /// `appearance`, `player` and `sources` (`Look.migrated`). The old fields keep being written so going back to the
    /// previous build loses nothing.
    public var look: Look = Look()
    /// Task 5.3 (ruling 24.11.): the detail options outside the look (`episodes`, `titleArt`). Missing in older
    /// profiles: defaults; written only when changed, so Build 4 reads the same bytes it wrote.
    public var detailExtras: LookDetailExtras = LookDetailExtras()
    /// Phase 0a.1: whole fields this build cannot read (start page, appearance, look, settings objects …), as raw JSON
    /// by coding key (`"home"`). The field itself holds a stand-in (its default) that the user may edit. While the
    /// stand-in is untouched, the raw value is written back under its own key; once it was changed, the raw value is
    /// written under `keptUnreadable` instead (see `LenientDecoding.swift`). Empty for every readable profile.
    public var keptUnreadable: [String: JSONValue] = [:]

    /// Default audio order of a new profile.
    public static let defaultAudioPriority = ["de", "en", "orig"]

    public init(id: UUID = UUID(), name: String, language: AppLanguage = .de, audioPriority: [String] = Profile.defaultAudioPriority,
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
        self.look = Look.migrated(from: appearance, player: player, sources: sources)
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
        case look
        case detailExtras
        case keptUnreadable
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
        // Phase 0a.1: objects and lists holding user work keep their raw value when unreadable (`decodeKeeping`).
        var kept: [String: JSONValue] = [:]
        id = try c.decode(UUID.self, forKey: .id)
        name = c.decodeLenient(String.self, forKey: .name, default: "Profil", report: r)
        language = c.decodeLenient(AppLanguage.self, forKey: .language, default: d.language, report: r)
        audioPriority = c.decodeKeeping([String].self, forKey: .audioPriority, default: d.audioPriority, report: r, kept: &kept)
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
        (addons, unknownAddons) = c.decodeSalvagedList(InstalledAddon.self, forKey: .addons, report: r)
        (collections, unknownCollections) = c.decodeSalvagedList(MediaCollection.self, forKey: .collections, report: r)
        home = c.decodeKeeping(HomeLayout.self, forKey: .home, default: d.home, report: r, kept: &kept)
        (apiKeys, unknownApiKeys) = c.decodeSalvagedMap(String.self, forKey: .apiKeys, report: r)
        autoplayNext = c.decodeLenient(Bool.self, forKey: .autoplayNext, default: d.autoplayNext, report: r)
        stillWatchingAfter = c.decodeLenient(Int.self, forKey: .stillWatchingAfter, default: d.stillWatchingAfter, report: r)
        (syncTokens, unknownSyncTokens) = c.decodeSalvagedMap(SyncToken.self, forKey: .syncTokens, report: r)
        appearance = c.decodeKeeping(Appearance.self, forKey: .appearance, default: d.appearance, report: r, kept: &kept)
        diskCache = c.decodeKeeping(DiskCacheSettings.self, forKey: .diskCache, default: d.diskCache, report: r, kept: &kept)
        addonTimeout = c.decodeLenient(Double.self, forKey: .addonTimeout, default: d.addonTimeout, report: r)
        sources = c.decodeKeeping(SourceSettings.self, forKey: .sources, default: d.sources, report: r, kept: &kept)
        player = c.decodeKeeping(PlayerComfortSettings.self, forKey: .player, default: d.player, report: r, kept: &kept)
        (hiddenRows, unknownHiddenRows) = Salvaged.split(
            c.decodeKeeping([Salvaged<HomeRow>].self, forKey: .hiddenRows, default: [], report: r, kept: &kept))
        subtitleStyle = c.decodeKeeping(SubtitleStyle.self, forKey: .subtitleStyle, default: d.subtitleStyle, report: r, kept: &kept)
        skip = c.decodeKeeping(SkipSettings.self, forKey: .skip, default: d.skip, report: r, kept: &kept)
        let migratedLook = Look.migrated(from: appearance, player: player, sources: sources)
        look = c.decodeKeeping(Look.self, forKey: .look, default: migratedLook, report: r, kept: &kept)
        detailExtras = c.decodeKeeping(LookDetailExtras.self, forKey: .detailExtras, default: d.detailExtras, report: r, kept: &kept)
        c.decodeKeptUnreadable(forKey: .keptUnreadable, into: &kept, report: r)
        keptUnreadable = kept
        adoptOldLookRows()   // integration build 5: the old rows „Plaketten-Stil“ and „Titelbild oben“ are gone
    }

    /// Same keys, order and format as the former synthesized encoding; only `hiddenRows` gets the raw leftovers
    /// (`unknownHiddenRows`) appended. Phase 0a.1: a field with a raw value in `keptUnreadable` writes that raw value
    /// while the field is still its stand-in (the default); otherwise the field is written and the raw value goes
    /// under `keptUnreadable` (written only when not empty, so readable profiles keep their bytes).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        var aside = keptUnreadable
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(language, forKey: .language)
        try c.encodeKeeping(audioPriority, untouched: audioPriority == Self.defaultAudioPriority, keeping: &aside,
                            forKey: .audioPriority)
        try c.encode(subtitleMode, forKey: .subtitleMode)
        try c.encode(subtitleLanguage, forKey: .subtitleLanguage)
        try c.encode(progressSource, forKey: .progressSource)
        try c.encodeSalvaged(addons, raw: unknownAddons, forKey: .addons)
        try c.encodeSalvaged(collections, raw: unknownCollections, forKey: .collections)
        try c.encodeKeeping(home, untouched: home == HomeLayout(), keeping: &aside, forKey: .home)
        try c.encodeSalvaged(apiKeys, raw: unknownApiKeys, forKey: .apiKeys)
        try c.encode(autoplayNext, forKey: .autoplayNext)
        try c.encode(stillWatchingAfter, forKey: .stillWatchingAfter)
        try c.encodeSalvaged(syncTokens, raw: unknownSyncTokens, forKey: .syncTokens)
        try c.encodeKeeping(appearance, untouched: appearance == Appearance(), keeping: &aside, forKey: .appearance)
        try c.encodeKeeping(diskCache, untouched: diskCache == DiskCacheSettings(), keeping: &aside, forKey: .diskCache)
        try c.encode(addonTimeout, forKey: .addonTimeout)
        try c.encodeKeeping(sources, untouched: sources == SourceSettings(), keeping: &aside, forKey: .sources)
        try c.encodeKeeping(player, untouched: player == PlayerComfortSettings(), keeping: &aside, forKey: .player)
        if hiddenRows.isEmpty, unknownHiddenRows.isEmpty,
           let raw = aside.removeValue(forKey: CodingKeys.hiddenRows.stringValue) {
            try c.encode(raw, forKey: .hiddenRows)
        } else {
            var hidden = c.nestedUnkeyedContainer(forKey: .hiddenRows)
            for row in hiddenRows { try hidden.encode(row) }
            for raw in unknownHiddenRows { try hidden.encode(raw) }
        }
        try c.encodeKeeping(subtitleStyle, untouched: subtitleStyle == SubtitleStyle(), keeping: &aside, forKey: .subtitleStyle)
        try c.encodeKeeping(skip, untouched: skip == SkipSettings(), keeping: &aside, forKey: .skip)
        // Task 4.2: a look that only mirrors the old fields is not written; reading rebuilds the same one. So a
        // profile nobody restyled keeps its exact Build 3 bytes (export and round-trip tests compare them).
        // Phase 0a.1: such a look is the stand-in of an unreadable one, whose raw value is written back instead.
        if !look.sameStyle(as: Look.migrated(from: appearance, player: player, sources: sources)) {
            try c.encode(look, forKey: .look)
        } else if let raw = aside.removeValue(forKey: CodingKeys.look.stringValue) {
            try c.encode(raw, forKey: .look)
        }
        if detailExtras != LookDetailExtras() {
            try c.encode(detailExtras, forKey: .detailExtras)
        } else if let raw = aside.removeValue(forKey: CodingKeys.detailExtras.stringValue) {
            try c.encode(raw, forKey: .detailExtras)
        }
        try c.encodeKeptUnreadable(aside, forKey: .keptUnreadable)
    }

    /// Phase 0a.1: whether a start page this build cannot read is kept. The app shows the stand-in in `home` (empty
    /// at first) until a build that can read it is installed again; nothing of it is lost on save.
    public var hasUnreadableHome: Bool { keptUnreadable[CodingKeys.home.stringValue] != nil }

    /// Task 4.2 fix round 1: while `look` only mirrors the old fields (the app still edits `appearance`/`player`),
    /// it follows them; once restyled it stays as set. `sources` is not part of the migration, so it needs no observer.
    private mutating func followOldFields(oldAppearance: Appearance, oldPlayer: PlayerComfortSettings) {
        if look.sameStyle(as: Look.migrated(from: oldAppearance, player: oldPlayer, sources: sources)) {
            look = Look.migrated(from: appearance, player: player, sources: sources)
        }
    }

    /// Task 4.3 fix round 1: takes a look imported from the configurator. The old fields it maps to are written
    /// first (each assigned once, so the observers run on whole values), the look last, so `followOldFields` can
    /// never replace it.
    public mutating func applyImportedLook(_ l: Look) {
        var a = appearance, pl = player
        l.writeOldFields(appearance: &a, player: &pl)
        appearance = a
        player = pl
        look = l
    }

    public static func makeDefault(name: String = "Ich") -> Profile {
        Profile(name: name, home: HomeLayout(rows: [HomeRow(content: .list(.continueWatching), style: .landscape)]))
    }
}
