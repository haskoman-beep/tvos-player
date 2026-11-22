import Foundation

/// Welle F-a: Zusammenfassungen der Einstellungs-Kategorien (Kopf rechts, eine Zeile) und Wertetexte der Zeilen.
/// Reine Logik, damit jede Kombination testbar ist und die Views nur noch Texte einsetzen.
public enum SettingsSummary {
    // MARK: Zählwörter

    /// „Kein Addon“, „1 Addon“, „3 Addons“.
    public static func count(_ n: Int, one: String, many: String, zero: String) -> String {
        switch n {
        case ..<1: zero
        case 1: "1 \(one)"
        default: "\(n) \(many)"
        }
    }

    public static func addons(_ n: Int) -> String { count(n, one: "Addon", many: "Addons", zero: "Kein Addon") }
    public static func rows(_ n: Int) -> String { count(n, one: "Reihe", many: "Reihen", zero: "Keine Reihen") }
    public static func collections(_ n: Int) -> String {
        count(n, one: "Collection", many: "Collections", zero: "Keine Collections")
    }
    public static func catalogs(_ n: Int) -> String { count(n, one: "Katalog", many: "Kataloge", zero: "Keine Kataloge") }
    public static func profiles(_ n: Int) -> String { count(n, one: "Profil", many: "Profile", zero: "Kein Profil") }

    /// Status eines Schlüssels, der nur am Handy eingetragen wird (E7): „Gespeichert“ / „Fehlt · am Handy“.
    public static func keyValue(_ stored: String?) -> String {
        (stored ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Fehlt · am Handy" : "Gespeichert"
    }

    // MARK: Konten

    /// Zustand eines Kontos (Trakt, Simkl) auf dem Fernseher.
    public enum AccountState: Equatable, Sendable {
        case connected
        /// Client ID ist da, noch nicht angemeldet.
        case connectable
        /// Client ID fehlt: nur am Handy eintragbar.
        case missingClient

        public static func of(hasClient: Bool, connected: Bool) -> AccountState {
            !hasClient ? .missingClient : connected ? .connected : .connectable
        }

        public var valueText: String {
            switch self {
            case .connected: "Verbunden"
            case .connectable: "Verbinden"
            case .missingClient: "Client ID fehlt · am Handy"
            }
        }
    }

    // MARK: Kategorien

    /// „Ich · Trakt verbunden“, „Ich · Trakt und Simkl verbunden“, „Ich · kein Konto verbunden“.
    public static func profile(name: String, trakt: Bool, simkl: Bool) -> String {
        let accounts: String
        switch (trakt, simkl) {
        case (true, true): accounts = "Trakt und Simkl verbunden"
        case (true, false): accounts = "Trakt verbunden"
        case (false, true): accounts = "Simkl verbunden"
        case (false, false): accounts = "kein Konto verbunden"
        }
        return DesignText.metaLine([name, accounts])
    }

    /// Kennzahlen der Profil-Statuskarte: „3 Addons · 24 Reihen“, „Fortschritt: Lokal“.
    public static func profileMetrics(addons n: Int, rows r: Int, progress: ProgressSource) -> [String] {
        [DesignText.metaLine([addons(n), rows(r)]), "Fortschritt: " + progressName(progress)]
    }

    /// „1 Addon · Smart sortiert“, „3 Addons · Wie Addon sortiert“.
    public static func addons(count n: Int, order: StreamOrderMode) -> String {
        DesignText.metaLine([addons(n), n == 0 ? nil : orderName(order) + " sortiert"])
    }

    /// „24 Reihen · Fusion-Kit an“.
    public static func home(rows r: Int, fusionKit: Bool) -> String {
        DesignText.metaLine([rows(r), "Fusion-Kit " + (fusionKit ? "an" : "aus")])
    }

    /// „Seitenleiste · Blau“ (Welle F-f: die Postergröße steht jetzt unter Startseite).
    public static func appearance(navigation: NavigationStyle, accent: AccentChoice) -> String {
        DesignText.metaLine([navigationName(navigation), accentName(accent)])
    }

    /// „Nächste Folge automatisch · Cache aus“, „Nächste Folge von Hand · Cache 8 GB“.
    public static func playback(autoplayNext: Bool, diskCache: DiskCacheSettings) -> String {
        DesignText.metaLine([autoplayNext ? "Nächste Folge automatisch" : "Nächste Folge von Hand",
                             diskCacheChoice(diskCache) == 0 ? "Cache aus" : "Cache " + diskCacheValue(diskCache)])
    }

    /// „Deutsch → Englisch · Nur erzwungene Untertitel“.
    public static func audio(audioPriority: [String], subtitles: SubtitleMode) -> String {
        DesignText.metaLine([AudioLanguageChoice.shortText(audioPriority), subtitleSummary(subtitles)])
    }

    /// Stand des Updates für die System-Zusammenfassung.
    public enum UpdateStatus: Equatable, Sendable {
        /// Noch nicht gesucht oder Suche ohne Ergebnis.
        case unknown
        case upToDate
        /// Neuer Build installierbar (Nummer, falls bekannt).
        case available(build: Int?)
        /// Installiert ist neuer als main.
        case newerInstalled

        public static func of(_ state: UpdateState?) -> UpdateStatus {
            switch state {
            case .upToDate?: .upToDate
            case .available(let r, _)?: .available(build: r.number)
            case .newerInstalled?: .newerInstalled
            case .notPublished?, nil: .unknown
            }
        }
    }

    /// „Build 35 · aktuell“, „Build 35 · Update: Build 36“, „Build 35“.
    public static func system(build: Int?, update: UpdateStatus) -> String {
        let b = "Build " + (build.map(String.init) ?? "?")
        switch update {
        case .unknown: return b
        case .upToDate: return DesignText.metaLine([b, "aktuell"])
        case .available(let n): return DesignText.metaLine([b, "Update: Build " + (n.map(String.init) ?? "?")])
        case .newerInstalled: return DesignText.metaLine([b, "neuer als veröffentlicht"])
        }
    }

    // MARK: Wertetexte

    public static func progressName(_ p: ProgressSource) -> String {
        switch p {
        case .local: "Lokal"
        case .trakt: "Trakt"
        case .simkl: "Simkl"
        }
    }

    public static func orderName(_ o: StreamOrderMode) -> String {
        switch o {
        case .addon: "Wie Addon"
        case .smart: "Smart"
        }
    }

    public static func navigationName(_ n: NavigationStyle) -> String {
        switch n {
        case .sidebar: "Seitenleiste"
        case .top: "Obere Leiste"
        }
    }

    public static func accentName(_ a: AccentChoice) -> String {
        switch a {
        case .blue: "Blau"
        case .purple: "Lila"
        case .pink: "Pink"
        case .orange: "Orange"
        case .green: "Grün"
        case .white: "Weiß"
        }
    }

    public static func cardSizeName(_ c: CardSize) -> String {
        switch c {
        case .small: "Klein"
        case .medium: "Mittel"
        case .large: "Groß"
        }
    }

    public static func languageName(_ l: AppLanguage) -> String {
        switch l {
        case .de: "Deutsch"
        case .en: "English"
        }
    }

    /// Wert der Zeile „Untertitel“.
    public static func subtitleModeName(_ m: SubtitleMode) -> String {
        switch m {
        case .off: "Aus"
        case .forcedOnly: "Nur erzwungene"
        case .always: "Immer"
        }
    }

    static func subtitleSummary(_ m: SubtitleMode) -> String {
        switch m {
        case .off: "Untertitel aus"
        case .forcedOnly: "Nur erzwungene Untertitel"
        case .always: "Untertitel immer"
        }
    }

    // MARK: Film zwischenspeichern (ein Picker statt Schalter + Picker)

    /// Auswahl „Aus“ (0) oder Größe in GB.
    public static let diskCacheChoices = [0] + DiskCacheSettings.sizeChoices

    public static func diskCacheChoice(_ s: DiskCacheSettings) -> Int {
        s.enabled ? DiskCacheSettings.nearestChoice(s.limitGB) : 0
    }

    /// Wahl übernehmen; „Aus“ behält die zuletzt gewählte Größe für das nächste Einschalten.
    public static func applyDiskCacheChoice(_ gb: Int, to s: DiskCacheSettings) -> DiskCacheSettings {
        var out = s
        if gb <= 0 {
            out.enabled = false
        } else {
            out.enabled = true
            out.limitGB = DiskCacheSettings.nearestChoice(gb)
        }
        return out
    }

    public static func diskCacheChoiceName(_ gb: Int) -> String { gb <= 0 ? "Aus" : "\(gb) GB" }

    public static func diskCacheValue(_ s: DiskCacheSettings) -> String { diskCacheChoiceName(diskCacheChoice(s)) }

    // MARK: Ton

    /// „Lautstärke angleichen“: Aus / Wie Fernsehen / Etwas lauter / Laut. Die LUFS-Zahl steht nur in der Beschreibung.
    public static func loudnessName(_ lufs: Int) -> String {
        switch lufs {
        case 0: "Aus"
        case -24: "Wie Fernsehen"
        case -20: "Etwas lauter"
        case -16: "Laut"
        default: "\(lufs) LUFS"
        }
    }

    public static func loudnessDetail(_ lufs: Int) -> String {
        lufs == 0
            ? "Hebt leise Filme auf eine gleichmäßige Lautstärke an."
            : "Zielwert \(lufs) LUFS. Hebt leise Filme auf eine gleichmäßige Lautstärke an."
    }

    public static func dialogueName(_ db: Int) -> String { db <= 0 ? "Aus" : "+\(db) dB" }

    public static func delayName(_ ms: Int) -> String {
        ms == 0 ? "0 ms" : ms > 0 ? "+\(ms) ms (Ton später)" : "\(ms) ms (Ton früher)"
    }

    /// „Ton-Anlage“ statt „eARC/AV-Receiver vorhanden“.
    public static func soundSystemName(eARC: Bool) -> String {
        eARC ? "AV-Receiver mit eARC" : "Über Fernseher (optisch/ARC)"
    }

    // MARK: Folgen

    public static func stillWatchingName(_ n: Int) -> String { n <= 0 ? "Aus" : "nach \(n) Folgen" }
}
