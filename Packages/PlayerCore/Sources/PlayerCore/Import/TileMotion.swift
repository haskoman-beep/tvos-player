import Foundation

// Wave F-o: animated tiles. A focused tile plays its focus video (mp4 from an import: `focusVideoUrl` of a collection
// export, `videoURL` of a preview pack), else its focus GIF, else it keeps the still. Round 2 (user decision 22.11.):
// only imports fill tiles; the app ships no video addresses of its own, and the repo bundles no media.

/// Which addresses can be a focus video on tvOS.
public enum FocusVideoURL {
    /// File types AVFoundation plays on tvOS (any case, e.g. `.MP4`). WebM is not among them.
    static let extensions: Set<String> = ["mp4", "m4v", "mov", "m3u8"]

    /// The address if it is https with a playable file type, else nil (the tile then falls back to the GIF).
    /// Percent-encoding stays as it is; an address with raw spaces is encoded once.
    public static func playable(_ s: String?) -> String? {
        guard var s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if URL(string: s) == nil, let e = s.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed.union(CharacterSet(charactersIn: "%#"))) {
            s = e
        }
        guard let u = URL(string: s), u.scheme?.lowercased() == "https", u.host?.isEmpty == false,
              extensions.contains(u.pathExtension.lowercased()) else { return nil }
        return s
    }

    /// HLS is streamed directly; everything else is downloaded once into the disk cache.
    public static func isStream(_ s: String) -> Bool { URL(string: s)?.pathExtension.lowercased() == "m3u8" }
}

/// What a focused tile plays: focus video before focus GIF before the still.
public enum TileMotion: Equatable, Sendable {
    case video(String)
    case gif(String)
    case still

    public static func of(_ f: Folder) -> TileMotion {
        if let v = FocusVideoURL.playable(f.focusVideo) { return .video(v) }
        if let g = f.focusGif, !g.isEmpty { return .gif(g) }
        return .still
    }

    /// User decision 27.11.: the Genres row keeps its stills (no focus video, no GIF), built in or imported.
    public static func isStillRow(_ c: MediaCollection) -> Bool {
        c.id == "pkg.genres" || ["genres", "genre"].contains(PreviewPack.key(c.title))
    }

    /// The collection with focus video and GIF removed from every tile when it is a still row, else unchanged.
    public static func stillRowStripped(_ c: MediaCollection) -> MediaCollection {
        guard isStillRow(c) else { return c }
        var out = c
        for i in out.folders.indices { out.folders[i].focusVideo = nil; out.folders[i].focusGif = nil }
        return out
    }
}

/// Sound of a focus video (setting "Ton bei Kachel-Animation", default off).
public enum FocusVideoAudio {
    /// Volume the sound fades in to. Brand intros are often mastered loud.
    public static let targetVolume: Float = 0.6
    /// Fade-in after the first picture, and fade-out on focus loss or at the end of the first pass (seconds).
    public static let fadeIn = 0.4
    public static let fadeOut = 0.15
    /// Quiet wait after the first picture before the fade starts: an external decoder may need a moment to lock
    /// onto the stereo signal, which would cut the start of the jingle.
    public static let fadeInDelay = 0.3
    /// Round 2: the sound plays at most this long (long studio intros run 16–41 s), then fades out over `capFade`.
    public static let soundCap = 12.0
    public static let capFade = 1.0
    /// Safety margin before the end of the first pass: the fade-out must be finished before the looper's next
    /// replica starts, so no part of the jingle is heard twice.
    public static let endMargin = 0.05

    /// Whether this run is audible: setting on, the file has a sound track, no main playback, and only during the
    /// first pass (the picture keeps looping silently afterwards).
    public static func audible(setting: Bool, hasAudioTrack: Bool, mainPlayback: Bool, loopsDone: Int) -> Bool {
        setting && hasAudioTrack && !mainPlayback && loopsDone == 0
    }

    /// When the sound fades out (item time of the first pass) and how long the fade takes.
    public struct FadeOutPlan: Equatable, Sendable {
        public var start: Double
        public var length: Double
    }

    /// Fade-out of the first pass: after `soundCap` seconds (slow fade), or at its end if that comes sooner (short
    /// fade, finished `endMargin` before the loop boundary). Unknown duration (stream): the cap. Nil when the clip
    /// is too short for a fade; then the sound is muted at the loop boundary.
    public static func fadeOutPlan(duration: Double) -> FadeOutPlan? {
        let capped = FadeOutPlan(start: soundCap, length: capFade)
        guard duration.isFinite, duration > 0 else { return capped }
        if duration - endMargin > soundCap + capFade { return capped }
        let start = duration - fadeOut - endMargin
        return start > 0.1 ? FadeOutPlan(start: start, length: fadeOut) : nil
    }

    /// Volume steps of a fade from `from` to `to` (`steps` values, the last one is `to`).
    public static func ramp(from: Float, to: Float, steps: Int) -> [Float] {
        guard steps > 0 else { return [to] }
        return (1...steps).map { from + (to - from) * Float($0) / Float(steps) }
    }
}

/// Disk cache of focus videos in two pots, each with its own limits; least recently used goes first.
/// `silent`: short loops without a sound track. `sound`: videos with a sound track (brand stings, studio intros up
/// to about 20 MiB).
public enum FocusVideoCachePlan {
    public enum Pot: String, CaseIterable, Sendable {
        case silent, sound

        /// Folder name below Caches/FocusVideos.
        public var folder: String { rawValue }
        public var maxBytes: Int64 { self == .silent ? 50 << 20 : 150 << 20 }
        /// A single file above this is not kept (it would push out everything else).
        public var maxFileBytes: Int64 { self == .silent ? 20 << 20 : 30 << 20 }
    }

    public static let maxAge: TimeInterval = 7 * 24 * 3600
    /// Largest download at all (a file above the silent cap is kept only if it has a sound track).
    public static var maxDownloadBytes: Int64 { Pot.sound.maxFileBytes }
    /// Anything smaller is no real clip (an error page, an empty body).
    public static let minFileBytes: Int64 = 4 << 10
    /// How long a failed address rests before the next attempt: load failure (network, HTTP, not a video) and
    /// playback failure (the stored file did not play; it is deleted).
    public static let retryAfterLoadFailure: TimeInterval = 300
    public static let retryAfterPlaybackFailure: TimeInterval = 1800

    public struct Entry: Equatable, Sendable {
        public var name: String
        public var bytes: Int64
        public var used: Date
        public init(name: String, bytes: Int64, used: Date) { self.name = name; self.bytes = bytes; self.used = used }
    }

    /// Names to delete in one pot: everything older than `maxAge`, then the least recently used until the rest fits.
    public static func evict(_ entries: [Entry], now: Date, maxBytes: Int64, maxAge: TimeInterval = maxAge) -> [String] {
        var out: [String] = []
        var keep: [Entry] = []
        for e in entries {
            if now.timeIntervalSince(e.used) > maxAge { out.append(e.name) } else { keep.append(e) }
        }
        var total = keep.reduce(Int64(0)) { $0 + $1.bytes }
        for e in keep.sorted(by: { $0.used != $1.used ? $0.used < $1.used : $0.name < $1.name }) where total > maxBytes {
            out.append(e.name)
            total -= e.bytes
        }
        return out
    }

    /// File name in the cache for an address: stable hash plus the file type (AVFoundation reads the type from it).
    public static func fileName(for url: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in url.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        let ext = URL(string: url)?.pathExtension.lowercased() ?? ""
        return String(h, radix: 16) + "." + (ext.isEmpty ? "mp4" : ext)
    }

    /// Result of checking a downloaded body before it goes into the cache.
    public enum Check: Equatable, Sendable {
        case ok(Pot)
        case tooSmall
        case tooLarge
        case notVideo(String)
    }

    /// A body is kept only if it is a video (an ISO media file: `ftyp` box at byte 4, mp4/m4v/mov; or a `video/*`
    /// content type, QuickTime files may start with another box) of sensible size. `hasSound` (from `Mp4Probe`)
    /// picks the pot, and with it the size cap.
    public static func check(contentType: String?, head: [UInt8], bytes: Int64, hasSound: Bool) -> Check {
        let pot: Pot = hasSound ? .sound : .silent
        if bytes > pot.maxFileBytes { return .tooLarge }
        if bytes < minFileBytes { return .tooSmall }
        if Mp4Probe.hasFtyp(head) { return .ok(pot) }
        let type = (contentType ?? "").split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        if type.hasPrefix("video/") { return .ok(pot) }
        return .notVideo(type.isEmpty ? "ohne Typ" : type)
    }
}

/// Reads the box structure of an mp4 just far enough to tell whether it has a sound track (`hdlr` box with handler
/// `soun`). Works on the start and the end of a file (the `moov` box sits at either end), so a range request of
/// both ends is enough.
public enum Mp4Probe {
    /// Bytes to read from each end of a file.
    public static let headBytes = 128 << 10
    public static let tailBytes = 256 << 10

    public static func hasFtyp(_ head: [UInt8]) -> Bool {
        head.count >= 8 && head[4] == 0x66 && head[5] == 0x74 && head[6] == 0x79 && head[7] == 0x70
    }

    /// Handler types (`vide`, `soun`, …) of all `hdlr` boxes in the bytes.
    public static func handlers(_ b: [UInt8]) -> [String] {
        var out: [String] = []
        guard b.count >= 16 else { return out }
        var i = 0
        // hdlr: size(4) 'hdlr'(4) version+flags(4) pre_defined(4) handler_type(4)
        while i + 16 <= b.count {
            if b[i] == 0x68, b[i + 1] == 0x64, b[i + 2] == 0x6C, b[i + 3] == 0x72 {
                let t = b[(i + 12)..<(i + 16)]
                if let s = String(bytes: t, encoding: .ascii) { out.append(s) }
                i += 16
            } else {
                i += 1
            }
        }
        return out
    }

    public static func hasSoundTrack(_ bytes: [UInt8]) -> Bool { handlers(bytes).contains("soun") }
}
