import Foundation

/// Task 5.4: what the control bar knows about the running stream (engine values plus the data rate of the source).
public struct StreamTechInfo: Equatable, Sendable {
    /// Source picture width (letterbox-safe resolution, `MediaLabels.resolution`).
    public var videoWidth: Int?
    /// Name of the engine's `VideoFormat` case ("sdr", "hdr10", "dolbyVision" …).
    public var videoFormat: String?
    /// libavcodec name of the video codec ("hevc").
    public var videoCodec: String?
    /// The audio track that plays.
    public var audio: AudioTrackInfo?
    /// Mean data rate of the source in Mbit/s (file size / running time); nil = unknown.
    public var bitrateMbps: Double?

    public init(videoWidth: Int? = nil, videoFormat: String? = nil, videoCodec: String? = nil,
                audio: AudioTrackInfo? = nil, bitrateMbps: Double? = nil) {
        self.videoWidth = videoWidth; self.videoFormat = videoFormat; self.videoCodec = videoCodec
        self.audio = audio; self.bitrateMbps = bitrateMbps
    }
}

/// Task 5.4 (`player.badges`): the technical badges of the control bar.
/// `aus` → none; `kompakt` → at most 3 (resolution, short dynamic range "DV"/"HDR10", audio format);
/// `voll` → at most 6 (resolution, dynamic range, audio format, channels, video codec, data rate "61 Mbit/s").
public enum PlayerBadgeSet {
    public static func make(_ info: StreamTechInfo, mode: LookPlayerBadges) -> [String] {
        let resolution = MediaLabels.resolution(width: info.videoWidth)
        let audio = info.audio.flatMap(audioShort)
        switch mode {
        case .aus:
            return []
        case .kompakt:
            return Array([resolution, dynamicRangeShort(info.videoFormat), audio].compactMap { $0 }.prefix(3))
        case .voll:
            let channels = info.audio.flatMap { MediaLabels.channels($0.channels, layout: $0.channelLayout) }
            let parts = [resolution, MediaLabels.dynamicRange(info.videoFormat), audio, channels,
                         MediaLabels.videoCodec(info.videoCodec), bitrate(info.bitrateMbps)]
            return Array(parts.compactMap { $0 }.prefix(6))
        }
    }

    /// "DV", "HDR10+", "HDR10", "HLG"; SDR and unknown → nil.
    public static func dynamicRangeShort(_ format: String?) -> String? {
        switch MediaLabels.dynamicRange(format) {
        case "Dolby Vision": "DV"
        case let other: other
        }
    }

    /// Audio format as a badge: "Atmos", "TrueHD", "DD+", "DD", "DTS-HD MA", "DTS:X", "AAC" …; unknown → nil.
    public static func audioShort(_ t: AudioTrackInfo) -> String? {
        guard !(t.codec?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) else { return nil }
        let f = MediaLabels.audioFormat(codec: t.codec, profile: t.profile, isAtmos: t.isAtmos, isDTSX: t.isDTSX)
        if f.hasPrefix("Dolby Atmos") { return "Atmos" }
        switch f {
        case "Unbekannt": return nil
        case "Dolby TrueHD": return "TrueHD"
        case "Dolby Digital+": return "DD+"
        case "Dolby Digital": return "DD"
        default: return f
        }
    }

    /// "61 Mbit/s" from 10 on, "4,3 Mbit/s" below; nil for nothing, zero or not finite.
    public static func bitrate(_ mbps: Double?) -> String? {
        guard let m = mbps, m.isFinite, m > 0 else { return nil }
        if m >= 10 { return "\(Int(m.rounded())) Mbit/s" }
        let tenths = Int((m * 10).rounded())
        return "\(tenths / 10),\(tenths % 10) Mbit/s"
    }
}
