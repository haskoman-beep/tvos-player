import Foundation

/// Spuren einer Sprache im Ton-/Untertitel-Panel.
public struct TrackLanguageGroup: Equatable, Sendable {
    /// Normalisierter Sprachcode (`MediaLabels.languageCode`), nil = unbekannt.
    public var code: String?
    /// Deutscher Sprachname ("Englisch", "Unbekannt").
    public var name: String
    public var tracks: [AudioTrackInfo]

    public init(code: String?, name: String, tracks: [AudioTrackInfo]) {
        self.code = code; self.name = name; self.tracks = tracks
    }

    /// Kopfzeile mit Anzahl, z. B. "Deutsch (2)".
    public var header: String { "\(name) (\(tracks.count))" }
}

/// Beschriftung einer Spurzeile im Panel.
public struct TrackRowLabel: Equatable, Sendable {
    /// Titel, z. B. "Englisch".
    public var title: String
    /// Detailzeile, z. B. "Dolby Atmos (TrueHD) · 7.1"; nil = keine.
    public var detail: String?
    /// Spurname, nur wenn er mehr sagt als Sprache und Codec.
    public var name: String?
    /// Plaketten (Erzwungen, SDH, Kommentar, Hörfilm, Standard, Extern).
    public var badges: [String]
}

/// Technik-Rohwerte der laufenden Wiedergabe für den Info-Reiter (vom Backend befüllt).
public struct PlaybackTechSnapshot: Equatable, Sendable {
    public var videoWidth: Int?
    /// Name des Engine-`VideoFormat` der Quelle ("dolbyVision", "hdr10", "sdr" …).
    public var sourceFormat: String?
    /// Name des Engine-`VideoFormat` der Ausgabe (nach Tonemapping).
    public var outputFormat: String?
    public var dolbyVisionProfile: Int?
    /// libavcodec-Name des Video-Codecs ("hevc").
    public var videoCodec: String?
    /// Engine-Beschreibung der Tonkette, z. B. "TRUEHD → EAC3 bridge".
    public var audioPipeline: String?
    /// Name des Engine-`AudioDelivery` ("streamCopy", "bridged", "decoded" …).
    public var audioDelivery: String?
    /// Aktive Tonspur (für die Kanalzahl der Ausgabe).
    public var activeAudio: AudioTrackInfo?
    /// Dateiname der Quelle, falls erkennbar.
    public var fileName: String?

    public init(videoWidth: Int? = nil, sourceFormat: String? = nil, outputFormat: String? = nil, dolbyVisionProfile: Int? = nil,
                videoCodec: String? = nil, audioPipeline: String? = nil, audioDelivery: String? = nil,
                activeAudio: AudioTrackInfo? = nil, fileName: String? = nil) {
        self.videoWidth = videoWidth; self.sourceFormat = sourceFormat; self.outputFormat = outputFormat
        self.dolbyVisionProfile = dolbyVisionProfile; self.videoCodec = videoCodec; self.audioPipeline = audioPipeline
        self.audioDelivery = audioDelivery; self.activeAudio = activeAudio; self.fileName = fileName
    }
}

/// Eine Zeile im Info-Reiter ("Auflösung" – "4K").
public struct TrackPanelInfoRow: Equatable, Sendable, Identifiable {
    public var label: String
    public var value: String
    public var id: String { label }
    public init(label: String, value: String) { self.label = label; self.value = value }
}

/// Reine Logik des Ton-/Untertitel-Panels (Gruppierung, Sortierung, Beschriftung). Regeln: research §7/§8.
public enum TrackPanelLogic {

    // MARK: Gruppierung und Sortierung

    /// Spuren nach Sprache gruppiert. Reihenfolge der Gruppen: Wunschsprachen in ihrer Reihenfolge
    /// (normalisiert, "orig" und Unbekanntes übersprungen), dann übrige Sprachen in Dateireihenfolge, Unbekannt zuletzt.
    /// Innerhalb einer Gruppe: normale Spuren (auch erzwungene) vor SDH vor Kommentar/Hörfilm, sonst Dateireihenfolge.
    public static func groupByLanguage(_ tracks: [AudioTrackInfo], preferred: [String]) -> [TrackLanguageGroup] {
        var order: [String?] = []
        var byCode: [String?: [AudioTrackInfo]] = [:]
        for t in tracks {
            let c = MediaLabels.languageCode(t.language)
            if byCode[c] == nil { order.append(c); byCode[c] = [] }
            byCode[c]?.append(t)
        }
        var wanted: [String] = []
        for p in preferred {
            guard p.lowercased() != "orig", let c = MediaLabels.languageCode(p), !wanted.contains(c) else { continue }
            wanted.append(c)
        }
        func rank(_ c: String?) -> Int {
            guard let c else { return Int.max }
            if let i = wanted.firstIndex(of: c) { return i }
            return wanted.count + (order.firstIndex(of: c) ?? 0)
        }
        let sortedCodes = order.enumerated().sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
        return sortedCodes.map { c in
            let list = byCode[c] ?? []
            let sorted = list.enumerated().sorted { a, b in
                let ra = trackRank(a.element), rb = trackRank(b.element)
                return ra != rb ? ra < rb : a.offset < b.offset
            }.map(\.element)
            return TrackLanguageGroup(code: c, name: MediaLabels.languageName(c), tracks: sorted)
        }
    }

    /// Tonspuren in Panel-Reihenfolge (nach Sprache, Profil-Tonsprachen zuerst), als flache Liste.
    public static func sortedAudio(_ tracks: [AudioTrackInfo], priority: [String]) -> [AudioTrackInfo] {
        groupByLanguage(tracks, preferred: priority).flatMap(\.tracks)
    }

    /// Untertitel nach Sprache gruppiert, Profil-UT-Sprache zuerst.
    public static func subtitleGroups(_ tracks: [AudioTrackInfo], preferredLanguage: String?) -> [TrackLanguageGroup] {
        groupByLanguage(tracks, preferred: preferredLanguage.map { [$0] } ?? [])
    }

    static func trackRank(_ t: AudioTrackInfo) -> Int {
        if t.isCommentary || t.isVisualImpaired { return 2 }
        if t.isHearingImpaired { return 1 }
        return 0
    }

    // MARK: Zeilen

    /// Tonzeile: Titel Sprache, Detail "Format · Kanäle", Name nur wenn nicht generisch.
    public static func audioRow(_ t: AudioTrackInfo) -> TrackRowLabel {
        let format = MediaLabels.audioFormat(codec: t.codec, profile: t.profile, isAtmos: t.isAtmos, isDTSX: t.isDTSX)
        let detail = [format, MediaLabels.channels(t.channels, layout: t.channelLayout)].compactMap { $0 }.joined(separator: " · ")
        return TrackRowLabel(title: MediaLabels.languageName(t.language), detail: detail.isEmpty ? nil : detail,
                             name: meaningfulName(t),
                             badges: MediaLabels.trackBadges(isForced: t.isForced, isHearingImpaired: t.isHearingImpaired,
                                                             isCommentary: t.isCommentary, isVisualImpaired: t.isVisualImpaired,
                                                             isDefault: t.isDefault, isExternal: t.isExternal))
    }

    /// Untertitelzeile: Titel Sprache, Detail Format ("SRT", "PGS · Bild"), Name nur wenn nicht generisch.
    public static func subtitleRow(_ t: AudioTrackInfo) -> TrackRowLabel {
        TrackRowLabel(title: MediaLabels.languageName(t.language), detail: subtitleFormat(codec: t.codec, isImage: t.isImage),
                      name: meaningfulName(t),
                      badges: MediaLabels.trackBadges(isForced: t.isForced, isHearingImpaired: t.isHearingImpaired,
                                                      isCommentary: t.isCommentary, isDefault: t.isDefault,
                                                      isExternal: t.isExternal))
    }

    static func meaningfulName(_ t: AudioTrackInfo) -> String? {
        guard !MediaLabels.isGenericTrackName(t.name, language: t.language, codec: t.codec) else { return nil }
        return t.name?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Untertitelformat im Klartext. Bild-Untertitel bekommen " · Bild". nil/leer → nil.
    public static func subtitleFormat(codec: String?, isImage: Bool) -> String? {
        guard let c = codec?.trimmingCharacters(in: .whitespaces).lowercased(), !c.isEmpty else { return isImage ? "Bild" : nil }
        let name: String
        switch c {
        case "subrip", "srt": name = "SRT"
        case "ass", "ssa": name = "ASS"
        case "webvtt", "vtt": name = "WebVTT"
        case "mov_text", "tx3g": name = "Text"
        case "text": name = "Text"
        default:
            if c.contains("pgs") || c.contains("hdmv") { name = "PGS" }
            else if c.contains("dvd") || c.contains("vobsub") { name = "VobSub" }
            else if c.contains("dvb") { name = "DVB" }
            else { name = c.uppercased() }
        }
        return isImage || MediaLabels.isImageSubtitleCodec(c) ? "\(name) · Bild" : name
    }

    // MARK: Info-Reiter

    /// Ton-Ausgabe, wenn die Engine den Ton umwandelt ("Dolby Digital+ 5.1 (umgewandelt)"). Unverändert → nil.
    /// Die E-AC-3-Brücke der Engine endet bei 5.1 (7.1 wird gefaltet), FLAC trägt die Kanäle der Quelle.
    public static func audioOutput(pipeline: String?, delivery: String?, sourceChannels: Int?, sourceLayout: String? = nil) -> String? {
        guard let d = delivery?.lowercased(), d == "bridged" || d == "decoded",
              let p = pipeline?.uppercased(), !p.isEmpty else { return nil }
        let src = MediaLabels.channels(sourceChannels, layout: sourceLayout)
        func join(_ parts: String?...) -> String { parts.compactMap { $0 }.joined(separator: " ") }
        if p.contains("→ EAC3") || p.contains("-> EAC3") {
            let ch = (sourceChannels ?? 0) > 6 ? "5.1" : src
            return join("Dolby Digital+", ch, "(umgewandelt)")
        }
        if p.contains("→ FLAC") || p.contains("-> FLAC") { return join("FLAC", src, "(umgewandelt, verlustfrei)") }
        if p.contains("APAC") { return "APAC (umgewandelt)" }
        if p.contains("PCM") || p.contains("COREAUDIO") { return join("PCM", src, "(dekodiert)") }
        return nil
    }

    /// Dateiname der Quelle, wenn die Adresse auf eine Mediendatei endet ("Film.2015.1080p.mkv"); sonst nil.
    public static func sourceFileName(_ url: URL?) -> String? {
        guard let url else { return nil }
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let media: Set<String> = ["mkv", "mp4", "m4v", "avi", "ts", "m2ts", "mov", "webm", "wmv", "flv", "mpg", "mpeg"]
        guard media.contains(ext), name.count > ext.count + 1 else { return nil }
        return name
    }

    /// Zeilen des Info-Reiters: Auflösung, Dynamik, Ausgabe (nur bei Tonemapping), Video-Codec, Ton-Ausgabe, Quelle.
    public static func infoRows(_ s: PlaybackTechSnapshot) -> [TrackPanelInfoRow] {
        var rows: [TrackPanelInfoRow] = []
        if let r = MediaLabels.resolution(width: s.videoWidth) { rows.append(.init(label: "Auflösung", value: r)) }
        let srcRange = MediaLabels.dynamicRange(s.sourceFormat)
        if s.sourceFormat != nil || srcRange != nil {
            var v = srcRange ?? "SDR"
            if srcRange == "Dolby Vision", let p = s.dolbyVisionProfile { v += " (Profil \(p))" }
            rows.append(.init(label: "Dynamik", value: v))
            if s.outputFormat != nil, MediaLabels.dynamicRange(s.outputFormat) != srcRange {
                rows.append(.init(label: "Ausgabe", value: MediaLabels.dynamicRange(s.outputFormat) ?? "SDR"))
            }
        }
        if let c = MediaLabels.videoCodec(s.videoCodec) { rows.append(.init(label: "Video-Codec", value: c)) }
        if let a = audioOutput(pipeline: s.audioPipeline, delivery: s.audioDelivery,
                               sourceChannels: s.activeAudio?.channels, sourceLayout: s.activeAudio?.channelLayout) {
            rows.append(.init(label: "Ton-Ausgabe", value: a))
        }
        if let f = s.fileName { rows.append(.init(label: "Quelle", value: f)) }
        return rows
    }
}
