import Foundation

/// Plaketten-Typen, die der Nutzer einzeln ein-/ausschalten kann (Einstellungen → Aussehen → Plaketten).
public enum BadgeType: String, Codable, Sendable, CaseIterable {
    case resolution, hdr, source, videoCodec, audio, channels, languages, size, cacheStatus
}

/// Darstellung der Plaketten: reine Text-Kapseln oder gezeichnete Wortmarken-Logos (wo vorhanden).
public enum BadgeStyle: String, Codable, Sendable, CaseIterable { case text, logo }

/// Gezeichnete Logo-Plaketten (Wortmarken-Stil, in der App per SwiftUI gezeichnet, keine Bilddateien).
public enum QualityLogoKind: String, Codable, Sendable, CaseIterable {
    case uhd4K, dolbyVision, hdr10, hdr10Plus, dolbyAtmos, dtsX, dtsHDMA, remux
}

/// Farbton einer Plakette: neutral (Glas) oder Status (sofort abspielbar / lädt erst).
public enum BadgeTone: String, Sendable { case neutral, ready, pending }

/// Eine anzuzeigende Plakette: Text (immer gesetzt, auch als Bedienhilfe-Text) und ggf. Logo.
public struct QualityBadge: Hashable, Sendable, Identifiable {
    public var type: BadgeType
    public var text: String
    public var logo: QualityLogoKind?
    public var tone: BadgeTone
    public var id: String { "\(type.rawValue)-\(text)" }

    public init(type: BadgeType, text: String, logo: QualityLogoKind? = nil, tone: BadgeTone = .neutral) {
        self.type = type; self.text = text; self.logo = logo; self.tone = tone
    }
}

/// Plaketten-Einstellungen eines Profils (Teil von `Appearance`). Fehlende Felder: Standardwerte.
public struct BadgeSettings: Codable, Sendable, Hashable {
    public var resolution: Bool
    public var hdr: Bool
    public var source: Bool
    /// Standard aus: in fast jeder Zeile gleich (H.264/HEVC), trägt wenig zur Wahl bei.
    public var videoCodec: Bool
    public var audio: Bool
    public var channels: Bool
    public var languages: Bool
    public var size: Bool
    public var cacheStatus: Bool
    public var style: BadgeStyle
    /// Kleine Plaketten auf Postern (nur bei schon gecachten Quellen).
    public var onPosters: Bool

    public init(resolution: Bool = true, hdr: Bool = true, source: Bool = true, videoCodec: Bool = false, audio: Bool = true,
                channels: Bool = true, languages: Bool = true, size: Bool = true, cacheStatus: Bool = true,
                style: BadgeStyle = .logo, onPosters: Bool = true) {
        self.resolution = resolution; self.hdr = hdr; self.source = source; self.videoCodec = videoCodec; self.audio = audio
        self.channels = channels; self.languages = languages; self.size = size; self.cacheStatus = cacheStatus
        self.style = style; self.onPosters = onPosters
    }

    enum CodingKeys: String, CodingKey {
        case resolution, hdr, source, videoCodec, audio, channels, languages, size, cacheStatus, style, onPosters
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BadgeSettings()
        func b(_ k: CodingKeys, _ def: Bool) throws -> Bool { try c.decodeIfPresent(Bool.self, forKey: k) ?? def }
        resolution = try b(.resolution, d.resolution)
        hdr = try b(.hdr, d.hdr)
        source = try b(.source, d.source)
        videoCodec = try b(.videoCodec, d.videoCodec)
        audio = try b(.audio, d.audio)
        channels = try b(.channels, d.channels)
        languages = try b(.languages, d.languages)
        size = try b(.size, d.size)
        cacheStatus = try b(.cacheStatus, d.cacheStatus)
        style = try c.decodeIfPresent(BadgeStyle.self, forKey: .style) ?? d.style
        onPosters = try b(.onPosters, d.onPosters)
    }

    public func shows(_ t: BadgeType) -> Bool {
        switch t {
        case .resolution: resolution
        case .hdr: hdr
        case .source: source
        case .videoCodec: videoCodec
        case .audio: audio
        case .channels: channels
        case .languages: languages
        case .size: size
        case .cacheStatus: cacheStatus
        }
    }

    public mutating func set(_ t: BadgeType, _ on: Bool) {
        switch t {
        case .resolution: resolution = on
        case .hdr: hdr = on
        case .source: source = on
        case .videoCodec: videoCodec = on
        case .audio: audio = on
        case .channels: channels = on
        case .languages: languages = on
        case .size: size = on
        case .cacheStatus: cacheStatus = on
        }
    }
}

/// Beste Werte über alle (gecachten) Quellen eines Titels – für Detailseite und Poster.
/// Wie `TechBadges.summary`: sicher ungecachte Quellen zählen nur, wenn es keine anderen gibt.
public struct BestQuality: Equatable, Sendable {
    /// Beste Auflösung ("2160p", "1440p", "1080p", "720p", "480p").
    public var resolution: String?
    public var dolbyVision = false
    /// Bestes HDR außer DV: "HDR10+" > "HDR10" > "HDR".
    public var hdr: String?
    public var atmos = false
    public var dtsX = false
    /// Meiste Kanäle ("7.1" > "5.1" > "2.0").
    public var channels: String?

    public init(resolution: String? = nil, dolbyVision: Bool = false, hdr: String? = nil, atmos: Bool = false,
                dtsX: Bool = false, channels: String? = nil) {
        self.resolution = resolution; self.dolbyVision = dolbyVision; self.hdr = hdr
        self.atmos = atmos; self.dtsX = dtsX; self.channels = channels
    }

    static let resolutionRank = ["2160p", "1440p", "1080p", "720p", "480p"]

    /// nil ohne Quellen.
    public static func from(_ traits: [StreamTraits]) -> BestQuality? {
        guard !traits.isEmpty else { return nil }
        let usable = traits.filter { $0.cached != false }
        let t = usable.isEmpty ? traits : usable
        var b = BestQuality()
        b.resolution = resolutionRank.first { r in t.contains { $0.resolution == r } }
        b.dolbyVision = t.contains { $0.hdr.contains("DV") }
        let others = Set(t.flatMap(\.hdr)).subtracting(["DV"])
        b.hdr = others.contains("HDR10+") ? "HDR10+" : others.contains("HDR10") ? "HDR10" : others.isEmpty ? nil : "HDR"
        b.atmos = t.contains { $0.audio.contains("Atmos") }
        b.dtsX = t.contains { $0.audio.contains("DTS:X") }
        b.channels = ["7.1", "5.1", "2.0"].first { c in t.contains { $0.channels == c } }
        return b
    }

    public static func from(_ streams: [StreamItem]) -> BestQuality? { from(streams.map(StreamTraits.parse)) }
}

public enum QualityBadges {
    /// Plaketten einer Quelle (Quellenliste), Reihenfolge wie bisher; nur eingeschaltete Typen.
    public static func forStream(_ t: StreamTraits, settings s: BadgeSettings) -> [QualityBadge] {
        let logos = s.style == .logo
        var out: [QualityBadge] = []
        func add(_ type: BadgeType, _ text: String, _ logo: QualityLogoKind? = nil, _ tone: BadgeTone = .neutral) {
            guard s.shows(type) else { return }
            out.append(QualityBadge(type: type, text: text, logo: logos ? logo : nil, tone: tone))
        }
        if let r = t.resolution { add(.resolution, r, r == "2160p" ? .uhd4K : nil) }
        for h in t.hdr { add(.hdr, h, hdrLogo(h)) }
        if let src = t.source { add(.source, src, src == "REMUX" ? .remux : nil) }
        if let c = t.videoCodec { add(.videoCodec, t.tenBit ? "\(c) 10-bit" : c) }
        for a in t.audio { add(.audio, a, audioLogo(a)) }
        if let ch = t.channels { add(.channels, ch) }
        for l in t.languages { add(.languages, l.uppercased()) }
        if let b = t.sizeBytes { add(.size, formatSize(b)) }
        if t.cached == true { add(.cacheStatus, "⚡ sofort", nil, .ready) }
        else if t.cached == false { add(.cacheStatus, "lädt erst", nil, .pending) }
        return out
    }

    /// Technik-Plaketten der Detailseite: 4K/HD, Dolby Vision, HDR-Art, Atmos, DTS:X, Kanäle.
    public static func detail(_ b: BestQuality, settings s: BadgeSettings) -> [QualityBadge] {
        let logos = s.style == .logo
        var out: [QualityBadge] = []
        func add(_ type: BadgeType, _ text: String, _ logo: QualityLogoKind?) {
            guard s.shows(type) else { return }
            out.append(QualityBadge(type: type, text: text, logo: logos ? logo : nil))
        }
        if let r = resolutionBadge(b.resolution) { add(.resolution, r.text, r.logo) }
        if b.dolbyVision { add(.hdr, "Dolby Vision", .dolbyVision) }
        if let h = b.hdr { add(.hdr, h, hdrLogo(h)) }
        if b.atmos { add(.audio, "Dolby Atmos", .dolbyAtmos) }
        if b.dtsX { add(.audio, "DTS:X", .dtsX) }
        if let ch = b.channels, ch != "2.0" { add(.channels, ch, nil) }
        return out
    }

    /// Höchstens 3 kleine Plaketten fürs Poster: beste Auflösung, DV (sonst HDR-Art), Atmos. Leer, wenn abgeschaltet.
    public static func poster(_ b: BestQuality, settings s: BadgeSettings) -> [QualityBadge] {
        guard s.onPosters else { return [] }
        let logos = s.style == .logo
        var out: [QualityBadge] = []
        func add(_ type: BadgeType, _ text: String, _ logo: QualityLogoKind?) {
            guard s.shows(type) else { return }
            out.append(QualityBadge(type: type, text: text, logo: logos ? logo : nil))
        }
        if let r = resolutionBadge(b.resolution) { add(.resolution, r.text, r.logo) }
        if b.dolbyVision { add(.hdr, "Dolby Vision", .dolbyVision) }
        else if let h = b.hdr { add(.hdr, h, hdrLogo(h)) }
        if b.atmos { add(.audio, "Dolby Atmos", .dolbyAtmos) }
        return Array(out.prefix(3))
    }

    /// 2160p → „4K“ (Logo), 1080p/1440p → „HD“, darunter keine Plakette.
    static func resolutionBadge(_ r: String?) -> (text: String, logo: QualityLogoKind?)? {
        switch r {
        case "2160p": ("4K", .uhd4K)
        case "1440p", "1080p": ("HD", nil)
        default: nil
        }
    }

    static func hdrLogo(_ h: String) -> QualityLogoKind? {
        switch h {
        case "DV": .dolbyVision
        case "HDR10+": .hdr10Plus
        case "HDR10": .hdr10
        default: nil
        }
    }

    static func audioLogo(_ a: String) -> QualityLogoKind? {
        switch a {
        case "Atmos": .dolbyAtmos
        case "DTS:X": .dtsX
        case "DTS-HD MA": .dtsHDMA
        default: nil
        }
    }

    /// Dateigröße wie zuvor (Dezimal-Einheiten, deutsches Komma): „30,71 GB“, „854 MB“, „1,20 TB“.
    public static func formatSize(_ bytes: Int64) -> String {
        let v = Double(bytes)
        let s: String
        if v >= 1e12 { s = String(format: "%.2f TB", v / 1e12) }
        else if v >= 1e9 { s = String(format: "%.2f GB", v / 1e9) }
        else { s = String(format: "%.0f MB", v / 1e6) }
        return s.replacingOccurrences(of: ".", with: ",")
    }
}
