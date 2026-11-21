import Foundation

/// Merkmale aus Name/Beschreibung eines Streams (AIOStreams-Format), für Plaketten in der Quellenliste.
public struct StreamTraits: Equatable, Sendable {
    public var resolution: String?
    public var hdr: [String] = []
    public var audio: [String] = []
    public var languages: [String] = []
    public var sizeBytes: Int64?
    /// true = sofort abspielbar (Debrid-Cache), false = muss erst laden, nil = unbekannt.
    public var cached: Bool?
    /// "7.1" / "5.1" / "2.0" laut Name.
    public var channels: String?

    public static func parse(_ s: StreamItem) -> StreamTraits {
        let text = [s.name, s.title, s.description, s.behaviorHints?.filename].compactMap { $0 }.joined(separator: " ")
        let up = text.uppercased()
        var t = StreamTraits()

        for (key, label) in [("2160P", "2160p"), ("4K", "2160p"), ("UHD", "2160p"), ("1440P", "1440p"), ("1080P", "1080p"), ("720P", "720p"), ("480P", "480p")]
        where t.resolution == nil && containsToken(up, key) { t.resolution = label }

        if containsToken(up, "DV") || up.contains("DOLBY VISION") || up.contains("DOVI") { t.hdr.append("DV") }
        if up.contains("HDR10+") || up.contains("HDR10PLUS") { t.hdr.append("HDR10+") }
        else if containsToken(up, "HDR10") { t.hdr.append("HDR10") }
        else if containsToken(up, "HDR") { t.hdr.append("HDR") }

        if up.contains("ATMOS") { t.audio.append("Atmos") }
        if up.contains("TRUEHD") { t.audio.append("TrueHD") }
        if up.contains("DTS-HD") || up.contains("DTS HD") || up.contains("DTSHD") { t.audio.append("DTS-HD MA") }
        else if up.contains("DTS:X") || containsToken(up, "DTS") { t.audio.append("DTS") }
        if up.contains("DDP") || up.contains("DD+") || up.contains("EAC3") || up.contains("E-AC-3") { t.audio.append("DD+") }
        else if containsToken(up, "DD") || up.contains("AC3") { t.audio.append("DD") }
        if containsToken(up, "AAC") { t.audio.append("AAC") }
        for ch in ["7.1", "5.1", "2.0"] where t.channels == nil && containsToken(up, ch) { t.channels = ch }

        for (flag, code) in [("🇩🇪", "de"), ("🇬🇧", "en"), ("🇺🇸", "en"), ("🇯🇵", "ja"), ("🇫🇷", "fr"), ("🇪🇸", "es"), ("🇮🇹", "it")]
        where text.contains(flag) && !t.languages.contains(code) { t.languages.append(code) }
        if (containsToken(up, "GERMAN") || containsToken(up, "DEUTSCH") || containsToken(up, "GER")) && !t.languages.contains("de") { t.languages.append("de") }
        if containsToken(up, "MULTI") && !t.languages.contains("multi") { t.languages.append("multi") }

        t.sizeBytes = s.behaviorHints?.videoSize ?? parseSize(up)

        if text.contains("⚡") || up.contains("[TB+]") || up.contains("[RD+]") || up.contains("CACHED") { t.cached = true }
        else if text.contains("⏳") || text.contains("🎫") || up.contains("DOWNLOAD") || up.contains("UNCACHED") { t.cached = false }
        return t
    }

    /// Token = nicht von Buchstaben/Ziffern umschlossen (damit "DV" nicht in "DVD..." greift usw.).
    static func containsToken(_ hay: String, _ token: String) -> Bool {
        var search = hay[...]
        while let r = search.range(of: token) {
            let before = r.lowerBound == hay.startIndex ? nil : hay[hay.index(before: r.lowerBound)]
            let after = r.upperBound == hay.endIndex ? nil : hay[r.upperBound]
            let isAlnum: (Character?) -> Bool = { c in c.map { $0.isLetter || $0.isNumber } ?? false }
            if !isAlnum(before) && !isAlnum(after) { return true }
            search = hay[r.upperBound...]
        }
        return false
    }

    static func parseSize(_ up: String) -> Int64? {
        let pattern = #"(\d+(?:[.,]\d+)?)\s*(TB|GB|MB)"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: up, range: NSRange(up.startIndex..., in: up)),
              let nr = Range(m.range(at: 1), in: up), let ur = Range(m.range(at: 2), in: up),
              let n = Double(up[nr].replacingOccurrences(of: ",", with: ".")) else { return nil }
        let mult: Double = switch up[ur] { case "TB": 1e12; case "GB": 1e9; default: 1e6 }
        return Int64(n * mult)
    }
}

/// Nur abspielbare Streams, Reihenfolge von AIOStreams bleibt.
public func playableStreams(_ s: [StreamItem]) -> [StreamItem] {
    s.filter { st in
        guard let u = st.url, let url = URL(string: u), let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

/// Eine Tonspur, wie die Player-Engine sie meldet.
public struct AudioTrackInfo: Equatable, Sendable {
    public var id: Int
    public var language: String?
    public var name: String?
    public var channels: Int?
    /// libavcodec-Name, z. B. "eac3", "ac3", "dts", "truehd".
    public var codec: String?
    public init(id: Int, language: String?, name: String? = nil, channels: Int? = nil, codec: String? = nil) {
        self.id = id; self.language = language; self.name = name; self.channels = channels; self.codec = codec
    }

    /// Über ARC unverändert durchreichbar (kein Umkodieren nötig).
    public var isPassthrough: Bool { ["eac3", "ac3"].contains(codec?.lowercased() ?? "") }
}

/// Rangfolge innerhalb einer Sprache: Surround vor Stereo, dann DD/DD+ (ohne Umkodieren über ARC) vor DTS/TrueHD, dann Kanäle.
func audioScore(_ t: AudioTrackInfo) -> Int {
    let ch = t.channels ?? 0
    return (ch >= 6 ? 1000 : 0) + (t.isPassthrough ? 100 : 0) + ch
}

/// Sprache nach Vorrang ("de", "en", "orig" = erste Spur); bei gleicher Sprache die beste nach `audioScore`.
public func preferredAudioTrack(_ tracks: [AudioTrackInfo], priority: [String]) -> AudioTrackInfo? {
    func norm(_ l: String?) -> String? {
        guard let l = l?.lowercased() else { return nil }
        switch l { case "de", "deu", "ger", "german", "deutsch": return "de"
        case "en", "eng", "english": return "en"
        default: return String(l.prefix(2)) }
    }
    for p in priority {
        if p == "orig" { return tracks.first }
        let m = tracks.filter { norm($0.language) == p }
        if let best = m.max(by: { audioScore($0) < audioScore($1) }) { return best }
    }
    return tracks.first
}

/// "Nicht gecacht"-Platzhalter von AIOStreams/TorBox: kurze Clips statt Film/Folge.
/// Unter 50 % der erwarteten Laufzeit oder (ohne Laufzeit) höchstens 121 s.
public func isPlaceholderVideo(duration: Double, expectedRuntimeMinutes: Double?) -> Bool {
    guard duration > 0 else { return false }
    if let r = expectedRuntimeMinutes, r > 0 { return duration < r * 60 * 0.5 }
    return duration <= 121
}

/// "117 min", "1h 57min", "2 h" → Minuten. Zahl gefolgt von "h" zählt als Stunden, sonst als Minuten.
public func parseRuntimeMinutes(_ s: String?) -> Double? {
    guard let s = s?.lowercased() else { return nil }
    let chars = Array(s)
    var total = 0.0, i = 0
    while i < chars.count {
        guard chars[i].isNumber else { i += 1; continue }
        var j = i
        while j < chars.count, chars[j].isNumber { j += 1 }
        let v = Double(String(chars[i..<j])) ?? 0
        var k = j
        while k < chars.count, chars[k] == " " { k += 1 }
        total += (k < chars.count && chars[k] == "h") ? v * 60 : v
        i = j
    }
    return total > 0 ? total : nil
}
