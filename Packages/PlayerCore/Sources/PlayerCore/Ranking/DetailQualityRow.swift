import Foundation

/// Welle E-a: Technik-Werte für die eine Qualitätszeile der Detailseite: `BestQuality` plus bestes Tonformat mit Kanälen.
public struct DetailQuality: Equatable, Sendable {
    public var best: BestQuality
    /// Tonformat der besten Tonspur ("TrueHD", "DTS-HD MA", "DD+" …), nil = unbekannt.
    public var audioFormat: String?
    /// Kanäle derselben Quelle ("7.1"); ohne erkanntes Format die meisten Kanäle über alle Quellen.
    public var audioChannels: String?

    public init(best: BestQuality, audioFormat: String? = nil, audioChannels: String? = nil) {
        self.best = best; self.audioFormat = audioFormat; self.audioChannels = audioChannels
    }

    /// Rangfolge der Tonformate (Atmos ist ein eigenes Merkmal, kein Format).
    static let formatRank = ["TrueHD", "DTS:X", "DTS-HD MA", "DD+", "DTS", "DD", "AAC"]
    static let channelRank = ["7.1", "5.1", "2.0"]

    /// Wie `BestQuality.from`: sicher ungecachte Quellen zählen nur, wenn es keine anderen gibt. nil ohne Quellen.
    public static func from(_ traits: [StreamTraits]) -> DetailQuality? {
        guard let best = BestQuality.from(traits) else { return nil }
        let usable = traits.filter { $0.cached != false }
        let t = usable.isEmpty ? traits : usable
        func fmt(_ x: StreamTraits) -> Int? { x.audio.compactMap { formatRank.firstIndex(of: $0) }.min() }
        func ch(_ x: StreamTraits) -> Int { x.channels.flatMap { channelRank.firstIndex(of: $0) } ?? channelRank.count }
        // Beste Quelle nach Format, dann Kanälen; Format und Kanäle kommen aus derselben Quelle.
        let top = t.filter { fmt($0) != nil }.min { a, b in
            let fa = fmt(a)!, fb = fmt(b)!
            return fa != fb ? fa < fb : ch(a) < ch(b)
        }
        if let top {
            return DetailQuality(best: best, audioFormat: formatRank[fmt(top)!], audioChannels: top.channels)
        }
        return DetailQuality(best: best, audioFormat: nil, audioChannels: best.channels)
    }

    public static func from(_ streams: [StreamItem]) -> DetailQuality? { from(streams.map(StreamTraits.parse)) }
}

extension QualityBadges {
    /// Höchstens so viele Plaketten in der Qualitätszeile der Detailseite.
    public static let detailRowLimit = 5

    /// Qualitätszeile der Detailseite, eine Zeile, höchstens 5, in dieser Reihenfolge:
    /// 1. Auflösung, 2. DV (sonst HDR10+/HDR10/HDR), 3. Atmos, 4. Tonformat + Kanäle als EINE Plakette („TrueHD 7.1“),
    /// 5. Remux. Abgeschaltete Typen entfallen (Tonformat: `audio`, Kanäle: `channels`).
    public static func detailRow(_ q: DetailQuality, settings s: BadgeSettings) -> [QualityBadge] {
        let logos = s.style == .logo
        let b = q.best
        var out: [QualityBadge] = []
        func add(_ type: BadgeType, _ text: String, _ logo: QualityLogoKind?) {
            guard s.shows(type) else { return }
            out.append(QualityBadge(type: type, text: text, logo: logos ? logo : nil))
        }
        if let r = resolutionBadge(b.resolution) { add(.resolution, r.text, r.logo) }
        if b.dolbyVision { add(.hdr, "Dolby Vision", .dolbyVision) }
        else if let h = b.hdr { add(.hdr, h, hdrLogo(h)) }
        if b.atmos { add(.audio, "Dolby Atmos", .dolbyAtmos) }
        if let a = audioText(q, settings: s) { out.append(QualityBadge(type: .audio, text: a)) }
        if b.remux { add(.source, "REMUX", .remux) }
        return Array(out.prefix(detailRowLimit))
    }

    /// „TrueHD 7.1“; ohne Format nur die Kanäle (nicht bei 2.0); nil, wenn nichts bleibt.
    static func audioText(_ q: DetailQuality, settings s: BadgeSettings) -> String? {
        let format = s.audio ? q.audioFormat : nil
        var channels = s.channels ? q.audioChannels : nil
        if format == nil, channels == "2.0" { channels = nil }
        let parts = [format, channels].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Poster-Plaketten (höchstens 3: Auflösung, DV/HDR, Atmos) nach „Qualität auf Postern“; leer bei „Aus“.
    public static func poster(_ b: BestQuality, settings s: BadgeSettings, placement: PosterBadgePlacement) -> [QualityBadge] {
        guard placement != .off else { return [] }
        return poster(b, settings: s)
    }
}
