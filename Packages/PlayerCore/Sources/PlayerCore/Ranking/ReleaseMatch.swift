import Foundation

/// Merkmale der gerade gespielten Quelle, um bei der nächsten Folge dasselbe Release wiederzufinden
/// (gleiche Gruppe, gleiches Namensmuster, gleiche Bild-/Tonmerkmale, gleicher Addon/Debrid-Dienst).
public struct ReleaseProfile: Equatable, Sendable {
    public var addon: String?
    public var bingeGroup: String?
    /// Release-Gruppe (`-GRUPPE` am Ende des Dateinamens), klein geschrieben.
    public var group: String?
    /// Technischer Teil des Namens nach der Folgennummer (ohne Folgentitel), z. B. "1080p.web-dl.ddp5.1.h.264-ntb".
    public var pattern: String?
    /// Debrid-/Usenet-Dienst laut Quellenname ("TB", "RD", …).
    public var service: String?
    public var traits: StreamTraits

    public init(stream: StreamItem, addon: String?) {
        self.addon = addon?.isEmpty == true ? nil : addon
        bingeGroup = stream.behaviorHints?.bingeGroup.flatMap { $0.isEmpty ? nil : $0 }
        let name = ReleaseName.releaseName(stream)
        group = name.flatMap(ReleaseName.group)
        pattern = name.flatMap(ReleaseName.pattern)
        service = ReleaseName.service(stream)
        traits = StreamTraits.parse(stream)
    }

    /// Nähe einer Quelle zu diesem Release, in Stufen: Gruppe/Muster → Sprache → Auflösung → HDR/DV, Ton, Rest;
    /// Addon und Dienst nur als Gleichstand-Brecher. `anchored` = Gruppe, Muster oder Auflösung stimmt: nur dann darf
    /// die Quelle die bestehende Sortierung überstimmen. Nur bekannte Merkmale der laufenden Quelle zählen.
    public func match(_ s: StreamItem, addon: String?) -> (score: Int, anchored: Bool) {
        var p = 0, anchored = false
        let name = ReleaseName.releaseName(s)
        if let group, name.flatMap(ReleaseName.group) == group { p += 1000; anchored = true }
        if let pattern, name.flatMap(ReleaseName.pattern) == pattern { p += 800; anchored = true }
        let t = StreamTraits.parse(s)
        if !traits.languages.isEmpty, Set(traits.languages) == Set(t.languages) { p += 250 }
        if let r = traits.resolution, t.resolution == r { p += 150; anchored = true }
        if !traits.hdr.isEmpty {
            if traits.hdr.contains("DV") == t.hdr.contains("DV") { p += 60 }
            if Set(traits.hdr) == Set(t.hdr) { p += 40 }
        } else if traits.resolution != nil, t.hdr.isEmpty { p += 20 }   // SDR bleibt SDR
        if !traits.audio.isEmpty, Set(traits.audio) == Set(t.audio) { p += 30 }
        if let src = traits.source, t.source == src { p += 20 }
        if let c = traits.channels, t.channels == c { p += 15 }
        if let v = traits.videoCodec, t.videoCodec == v { p += 10 }
        if let a = self.addon, a == addon { p += 20 }
        if let service, ReleaseName.service(s) == service { p += 20 }
        return (p, anchored)
    }

    /// Punkte allein (Log/Tests).
    public func score(_ s: StreamItem, addon: String?) -> Int { match(s, addon: addon).score }
}

/// Quelle für die nächste Folge. Reihenfolge: gleiche `bingeGroup` (Stremio) → höchste Release-Nähe unter den Quellen
/// mit gleicher Gruppe, gleichem Muster oder gleicher Auflösung → bestehende Sortierung (erste Quelle).
/// Sicher nicht gecachte Quellen nur, wenn es sonst keine gibt. Gleichstand: Listenreihenfolge.
public func nextEpisodeStream(_ streams: [(addon: String, stream: StreamItem)], matching ref: ReleaseProfile?) -> StreamItem? {
    let ok = Set(playableStreams(streams.map(\.stream)).map(\.id))
    let all = streams.filter { ok.contains($0.stream.id) }
    let ready = all.filter { StreamTraits.parse($0.stream).cached != false }
    let pool = ready.isEmpty ? all : ready
    guard let ref else { return pool.first?.stream }
    if let g = ref.bingeGroup, let same = pool.first(where: { $0.stream.behaviorHints?.bingeGroup == g }) { return same.stream }
    var best: (score: Int, stream: StreamItem)?
    for e in pool {
        let m = ref.match(e.stream, addon: e.addon)
        if m.anchored, m.score > (best?.score ?? -1) { best = (m.score, e.stream) }
    }
    return best?.stream ?? pool.first?.stream
}

/// Release-Namen zerlegen (Gruppe, Muster, Dienst). Nur Text-Heuristik, ohne Netz.
enum ReleaseName {
    /// Dateiname, sonst eine Zeile aus Titel/Beschreibung, die wie ein Release-Name aussieht (Folgenkennung + Punkte).
    static func releaseName(_ s: StreamItem) -> String? {
        if let f = s.behaviorHints?.filename, !f.isEmpty { return f }
        // AIOStreams: eine Zeile wie "📁 Show.S01E02.1080p.WEB-DL-GRP.mkv" → das Wort mit Punkten und Folgenkennung.
        let words = [s.title, s.description].compactMap { $0 }.flatMap { $0.split(whereSeparator: \.isWhitespace) }
        return words.map(String.init).first { w in w.contains(".") && episodeIndex(tokens(w)) != nil }
    }

    static func stripExtension(_ n: String) -> String {
        let exts = ["mkv", "mp4", "m4v", "avi", "ts", "m2ts", "webm", "mov"]
        guard let dot = n.lastIndex(of: "."), exts.contains(n[n.index(after: dot)...].lowercased()) else { return n }
        return String(n[..<dot])
    }

    /// Endungen nach "-", die keine Gruppe sind (WEB-DL, BD-Rip, DTS-HD …).
    private static let notGroups: Set<String> = ["dl", "rip", "hd", "x", "ma", "es", "dts", "web", "dovi", "hdr", "sdr", "ac3", "aac"]

    static func group(_ name: String) -> String? {
        let base = stripExtension(name.trimmingCharacters(in: .whitespaces))
        guard let dash = base.lastIndex(of: "-") else { return nil }
        var g = String(base[base.index(after: dash)...])
        if let b = g.firstIndex(where: { $0 == "[" || $0 == "(" || $0 == " " }) { g = String(g[..<b]) }
        let low = g.lowercased()
        guard (2...20).contains(low.count), low.allSatisfy({ $0.isLetter || $0.isNumber }),
              !notGroups.contains(low), !low.allSatisfy(\.isNumber) else { return nil }
        return low
    }

    static func tokens(_ n: String) -> [String] {
        stripExtension(n).lowercased().split(whereSeparator: { $0 == "." || $0 == " " || $0 == "_" }).map(String.init)
    }

    /// Index der Folgenkennung (S01E02, 1x02).
    static func episodeIndex(_ t: [String]) -> Int? {
        t.firstIndex { tok in
            tok.range(of: #"^s\d{1,2}e\d{1,4}"#, options: .regularExpression) != nil
                || tok.range(of: #"^\d{1,2}x\d{2,3}$"#, options: .regularExpression) != nil
        }
    }

    private static let techWords: Set<String> = [
        "2160p", "1440p", "1080p", "1080i", "720p", "576p", "480p", "4k", "uhd", "web", "web-dl", "webdl", "webrip", "web-rip",
        "bluray", "blu-ray", "bdrip", "brrip", "remux", "hdtv", "german", "ger", "deutsch", "multi", "dual", "dl", "english", "eng",
        "amzn", "nf", "dsnp", "atvp", "hmax", "max", "pmtp", "hulu", "itunes", "sky", "rtl", "joyn", "hdr", "hdr10", "dv", "dovi",
        "x264", "x265", "h264", "h265", "hevc", "avc", "av1", "repack", "proper", "internal",
    ]

    /// Teil nach der Folgenkennung ab dem ersten Technik-Wort (der Folgentitel davor wechselt je Folge).
    static func pattern(_ name: String) -> String? {
        let t = tokens(name)
        guard let e = episodeIndex(t) else { return nil }
        let tail = Array(t[(e + 1)...])
        guard !tail.isEmpty else { return nil }
        // Ab der Auflösung (ein Folgentitel wie „Max“ wäre sonst ein Technik-Wort); nur ohne Auflösung ab dem ersten anderen Technik-Wort.
        let start = tail.firstIndex { $0.range(of: #"^\d{3,4}[pi]$"#, options: .regularExpression) != nil }
            ?? tail.firstIndex { techWords.contains($0) } ?? 0
        let p = tail[start...].joined(separator: ".")
        return p.isEmpty ? nil : p
    }

    /// Kurzzeichen (nur in Klammer- bzw. Plus-/Blitz-Form) und ausgeschriebene Namen je Dienst.
    private static let services: [(code: String, names: [String])] = [
        ("TB", ["TORBOX"]), ("RD", ["REAL-DEBRID", "REALDEBRID"]), ("AD", ["ALLDEBRID"]), ("PM", ["PREMIUMIZE"]),
        ("DL", ["DEBRID-LINK", "DEBRIDLINK"]), ("ED", ["EASYDEBRID"]), ("OC", ["OFFCLOUD"]), ("PKP", ["PIKPAK"]),
        ("NZB", ["USENET", "EASYNEWS"]), ("EN", []),
    ]

    /// Dienst aus dem Quellennamen ("[TB⚡] …", "[RD+]", "TorBox …"). Kurzzeichen nur als ganzes Wort mit "+", "⚡",
    /// "⏳" oder "]" dahinter (nicht "CACHED+", nicht "WEB-DL"); "EN" nur als Klammer-Token "[EN]", "[EN+]", "[EN⚡]".
    static func service(_ s: StreamItem) -> String? {
        let up = (s.name ?? "").uppercased()
        for (code, names) in services {
            let lead = code == "EN" ? #"\["# : #"(^|[^A-Z0-9])"#
            if up.range(of: lead + code + #"(\+|⚡|⏳|\])"#, options: .regularExpression) != nil
                || names.contains(where: { up.contains($0) }) { return code == "EN" ? "NZB" : code }
        }
        return nil
    }
}
