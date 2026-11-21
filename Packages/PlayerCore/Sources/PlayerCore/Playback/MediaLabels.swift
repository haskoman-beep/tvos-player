import Foundation

/// Klartext für Rohwerte der Player-Engine (Sprachcodes, Codecs, Formate, Kanäle, Spur-Plaketten).
/// Regeln: research/vergleich_player_ui.md §8. Reine Funktionen, damit der Player und die Tests sie teilen.
public enum MediaLabels {

    // MARK: Sprache

    /// ISO 639-2 B/T-Paare und ausgeschriebene Namen, die Locale nicht (sicher) auf zwei Buchstaben bringt.
    static let languageAliases: [String: String] = [
        "ger": "de", "deu": "de", "german": "de", "deutsch": "de",
        "eng": "en", "english": "en", "englisch": "en",
        "fre": "fr", "fra": "fr", "french": "fr",
        "dut": "nl", "nld": "nl",
        "cze": "cs", "ces": "cs",
        "chi": "zh", "zho": "zh",
        "gre": "el", "ell": "el",
        "rum": "ro", "ron": "ro",
        "alb": "sq", "sqi": "sq", "arm": "hy", "hye": "hy", "baq": "eu", "eus": "eu",
        "bur": "my", "mya": "my", "geo": "ka", "kat": "ka", "ice": "is", "isl": "is",
        "mac": "mk", "mkd": "mk", "mao": "mi", "mri": "mi", "may": "ms", "msa": "ms",
        "per": "fa", "fas": "fa", "slo": "sk", "slk": "sk", "tib": "bo", "bod": "bo",
        "wel": "cy", "cym": "cy",
    ]

    /// Normalisierter Sprachcode: "ger"/"deu"/"German"/"de-DE" → "de", "pob"/"pt-BR" → "pt-BR",
    /// sonst zwei Buchstaben (drei Buchstaben über Locale). "und", leer oder nil → nil.
    /// Unbekannte Codes kommen klein geschrieben unverändert zurück (dann liefert `languageName` "Unbekannt").
    public static func languageCode(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !s.isEmpty else { return nil }
        s = s.replacingOccurrences(of: "_", with: "-")
        if s == "pob" || s == "pt-br" { return "pt-BR" }
        if let dash = s.firstIndex(of: "-") { s = String(s[..<dash]) }
        if s.isEmpty || s == "und" || s == "unknown" { return nil }
        if let alias = languageAliases[s] { return alias }
        guard s.allSatisfy({ $0.isASCII && $0.isLetter }) else { return s }
        if s.count == 3, let two = Locale.LanguageCode(s).identifier(.alpha2), two != "und" { return two }
        return s
    }

    /// Deutscher Sprachname mit großem Anfangsbuchstaben ("de" → "Deutsch", "eng" → "Englisch").
    /// nil, "und" oder unbekannt → "Unbekannt".
    public static func languageName(_ raw: String?) -> String {
        guard let code = languageCode(raw) else { return "Unbekannt" }
        let de = Locale(identifier: "de")
        let name = code.contains("-") ? de.localizedString(forIdentifier: code) : de.localizedString(forLanguageCode: code)
        guard let name, !name.isEmpty, name.lowercased() != code.lowercased() else { return "Unbekannt" }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    // MARK: Bild

    /// Auflösung nach Bildbreite (robust gegen Letterbox). nil oder ≤ 0 → nil.
    public static func resolution(width: Int?) -> String? {
        guard let w = width, w > 0 else { return nil }
        switch w {
        case 6000...: return "8K"
        case 3000...: return "4K"
        case 2200...: return "1440p"
        case 1500...: return "1080p"
        case 1100...: return "720p"
        default: return "SD"
        }
    }

    /// Dynamikumfang aus dem Namen des Engine-`VideoFormat`-Falls ("dolbyVision", "hdr10Plus", "hdr10", "hlg", "sdr").
    /// SDR und Unbekanntes → nil (nichts anzeigen).
    public static func dynamicRange(_ f: String?) -> String? {
        switch f?.lowercased() {
        case "dolbyvision": return "Dolby Vision"
        case "hdr10plus": return "HDR10+"
        case "hdr10": return "HDR10"
        case "hlg": return "HLG"
        default: return nil
        }
    }

    /// Video-Codec aus dem libavcodec-Namen ("hevc" → "HEVC"). Unbekannt → Großbuchstaben, nil/leer → nil.
    public static func videoCodec(_ name: String?) -> String? {
        guard let n = name?.trimmingCharacters(in: .whitespaces).lowercased(), !n.isEmpty else { return nil }
        switch n {
        case "hevc", "h265", "h.265": return "HEVC"
        case "h264", "h.264", "avc", "avc1": return "H.264"
        case "av1": return "AV1"
        case "vp9": return "VP9"
        case "mpeg2video", "mpeg2": return "MPEG-2"
        default: return n.uppercased()
        }
    }

    // MARK: Ton

    /// Tonformat nach Codec und Flags ("truehd" + Atmos → "Dolby Atmos (TrueHD)", "dts" + Profil "DTS-HD MA" → "DTS-HD MA").
    /// TrueHD-Atmos erkennt die Engine teils nur am Profil ("Dolby TrueHD + Dolby Atmos"), daher zählt auch das.
    /// Ohne Codec → "Unbekannt".
    public static func audioFormat(codec: String?, profile: String?, isAtmos: Bool, isDTSX: Bool) -> String {
        guard let c = codec?.trimmingCharacters(in: .whitespaces).lowercased(), !c.isEmpty else { return "Unbekannt" }
        let p = profile?.uppercased() ?? ""
        switch c {
        case "truehd", "mlp":
            return isAtmos || p.contains("ATMOS") ? "Dolby Atmos (TrueHD)" : "Dolby TrueHD"
        case "eac3":
            return isAtmos ? "Dolby Atmos (DD+)" : "Dolby Digital+"
        case "ac3":
            return "Dolby Digital"
        case "dts", "dca":
            if isDTSX || p.contains("DTS:X") { return "DTS:X" }
            if p.contains("MA") { return "DTS-HD MA" }
            if p.contains("HRA") || p.contains("HR") { return "DTS-HD HR" }
            return "DTS"
        case "aac": return "AAC"
        case "flac": return "FLAC"
        case "opus": return "Opus"
        default:
            return c.hasPrefix("pcm") ? "PCM" : c.uppercased()
        }
    }

    /// Kanäle: 1 → "Mono", 2 → "Stereo", 6 → "5.1", 8 → "7.1", sonst "N Kanäle".
    /// Ein libav-Layout ("stereo", "5.1(side)", "7.1") hat Vorrang; ein unbekanntes Layout ("hexagonal") fällt auf die Zahl zurück.
    /// nil/0 ohne brauchbares Layout → nil.
    public static func channels(_ n: Int?, layout: String? = nil) -> String? {
        if var l = layout?.trimmingCharacters(in: .whitespaces).lowercased(), !l.isEmpty {
            if let paren = l.firstIndex(of: "(") { l = String(l[..<paren]).trimmingCharacters(in: .whitespaces) }
            if l == "mono" { return "Mono" }
            if l == "stereo" { return "Stereo" }
            let parts = l.split(separator: ".", omittingEmptySubsequences: false)
            if parts.count >= 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) { return l }
        }
        guard let n, n > 0 else { return nil }
        switch n {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(n) Kanäle"
        }
    }

    // MARK: Spurnamen und Plaketten

    /// Wörter, die in einem Spurnamen nichts über Sprache und Codec hinaus sagen.
    static let genericNameWords: Set<String> = [
        // Ton-Codecs und -Formate
        "truehd", "hd", "dts", "ma", "hra", "hr", "x", "dtsx", "ac3", "eac3", "ac", "dd", "ddp", "dolby", "digital", "plus",
        "atmos", "aac", "lc", "he", "flac", "opus", "pcm", "lpcm", "mp3", "mp2", "vorbis", "mlp",
        // Untertitel-Codecs
        "subrip", "srt", "ass", "ssa", "pgs", "pgssub", "hdmv", "vobsub", "dvdsub", "dvd", "dvbsub", "webvtt", "vtt", "mov", "text", "tx3g",
        // Kanäle
        "mono", "stereo", "surround", "ch", "channel", "channels", "kanal", "kanäle",
        // Allgemein
        "track", "spur", "audio", "ton", "sub", "subs", "subtitle", "subtitles", "untertitel",
    ]

    /// true, wenn der Spurname nichts über Sprache und Codec hinaus sagt ("English", "Surround 7.1", "TrueHD",
    /// Engine-Ersatznamen wie "ENG (subrip)" oder "Track 3 (subrip)") – dann bleibt er in der Anzeige weg.
    /// Leerer Name gilt als generisch. Ohne Sprache der Spur zählt ein Sprachwort im Namen als Information.
    public static func isGenericTrackName(_ name: String?, language: String?, codec: String?) -> Bool {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return true }
        var generic = genericNameWords
        if let c = codec?.lowercased(), !c.isEmpty {
            generic.insert(c)
            generic.formUnion(c.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        }
        let code = languageCode(language)
        if let code {
            if let raw = language?.lowercased() { generic.insert(raw) }
            generic.insert(code.lowercased())
            for loc in ["de", "en"] {
                let l = Locale(identifier: loc)
                let n = code.contains("-") ? l.localizedString(forIdentifier: code) : l.localizedString(forLanguageCode: code)
                if let n { generic.formUnion(n.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)) }
            }
        }
        let tokens = name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        return tokens.allSatisfy { t in
            if t.allSatisfy(\.isNumber) { return true }
            if generic.contains(t) { return true }
            // "GER" im Namen bei Sprache "deu": gleiche Sprache, sagt nichts Neues.
            if let code, languageCode(t) == code, t.count <= 3 { return true }
            return false
        }
    }

    /// Plaketten an einer Spur in fester Reihenfolge: Erzwungen, SDH, Kommentar, Hörfilm, Standard, Extern bzw. Quellname.
    public static func trackBadges(isForced: Bool = false, isHearingImpaired: Bool = false, isCommentary: Bool = false,
                                   isVisualImpaired: Bool = false, isDefault: Bool = false, isExternal: Bool = false,
                                   source: String? = nil) -> [String] {
        var b: [String] = []
        if isForced { b.append("Erzwungen") }
        if isHearingImpaired { b.append("SDH") }
        if isCommentary { b.append("Kommentar") }
        if isVisualImpaired { b.append("Hörfilm") }
        if isDefault { b.append("Standard") }
        if isExternal {
            let s = source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            b.append(s.isEmpty ? "Extern" : s)
        }
        return b
    }

    /// Bild-Untertitel (PGS, VobSub, DVB, XSUB): werden als Bild gezeichnet, nicht als Text.
    /// Gleiche Teilwort-Liste wie AetherEngines internes `isBitmapSubtitleCodec`.
    public static func isImageSubtitleCodec(_ codec: String?) -> Bool {
        guard let c = codec?.lowercased(), !c.isEmpty else { return false }
        return ["pgs", "hdmv", "dvb_sub", "dvbsub", "dvd_sub", "dvdsub", "vobsub", "xsub"].contains { c.contains($0) }
    }
}
