import Foundation

/// Texte für die Steuerleiste des Players: Plakettenreihe, Folgenzeile, Endzeit.
/// Regeln: research/vergleich_player_ui.md §7/§8. Nur Formatierung, keine Engine-Abhängigkeit.
extension MediaLabels {

    /// Plaketten in fester Reihenfolge: Auflösung, Dynamik (SDR: nichts), aktive Tonspur, aktiver Untertitel.
    /// `videoFormat` ist der Name des Engine-`VideoFormat`-Falls ("sdr", "hdr10", "dolbyVision" …).
    /// Beispiel Pixels: 1920 breit, sdr, TrueHD-Atmos 8 Kanäle eng → ["1080p", "Englisch · Dolby Atmos (TrueHD) 7.1"].
    public static func infoBadges(videoWidth: Int?, videoFormat: String?,
                                  audio: AudioTrackInfo?, subtitle: AudioTrackInfo?) -> [String] {
        var b: [String] = []
        if let r = resolution(width: videoWidth) { b.append(r) }
        if let d = dynamicRange(videoFormat) { b.append(d) }
        if let a = audio, let t = audioBadge(a) { b.append(t) }
        if let s = subtitle { b.append(subtitleBadge(s)) }
        return b
    }

    /// Tonspur als "Sprache · Format Kanäle" ("Englisch · Dolby Atmos (TrueHD) 7.1").
    /// Unbekannte Sprache oder fehlender Codec fallen weg; ohne alles → nil.
    public static func audioBadge(_ t: AudioTrackInfo) -> String? {
        let name = languageName(t.language)
        let lang = name == "Unbekannt" ? nil : name
        let hasCodec = !(t.codec?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        let format = hasCodec ? audioFormat(codec: t.codec, profile: t.profile, isAtmos: t.isAtmos, isDTSX: t.isDTSX) : nil
        let detail = [format, channels(t.channels, layout: t.channelLayout)].compactMap { $0 }.joined(separator: " ")
        let parts = [lang, detail.isEmpty ? nil : detail].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Aktiver Untertitel als "UT: Deutsch", erzwungene als "UT: Deutsch (erzwungen)".
    /// Ohne bekannte Sprache: aussagekräftiger Spurname, sonst "UT: an".
    public static func subtitleBadge(_ t: AudioTrackInfo) -> String {
        var label = languageName(t.language)
        if label == "Unbekannt" {
            let n = t.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            label = isGenericTrackName(n, language: t.language, codec: t.codec) ? "an" : n
        }
        return "UT: \(label)" + (t.isForced ? " (erzwungen)" : "")
    }

    /// Folgenzeile unter dem Serientitel: "S01E02 · Episodentitel", ohne Titel nur "S01E02". Ohne Staffel/Folge → nil.
    public static func episodeLine(season: Int?, episode: Int?, title: String?) -> String? {
        guard let s = season, let e = episode else { return nil }
        let code = String(format: "S%02dE%02d", s, e)
        guard let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return code }
        return "\(code) · \(t)"
    }

    /// Uhrzeit des Endes bei normaler Geschwindigkeit: "Endet um 22:41". Restzeit ≤ 0 oder nicht endlich → nil.
    public static func endTime(remaining: Double, now: Date = Date(), timeZone: TimeZone = .current) -> String? {
        guard remaining.isFinite, remaining > 0 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute], from: now.addingTimeInterval(remaining))
        return String(format: "Endet um %02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
