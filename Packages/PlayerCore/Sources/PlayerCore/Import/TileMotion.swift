import Foundation

// Wave F-o: animated package tiles. A focused tile plays its focus video (mp4 from the collection export field
// `focusVideoUrl`), else its focus GIF, else it keeps the still. The ready-made packages take the video (and for the
// studios also the still) from the public collection export at runtime; the repo bundles no file. Imports and kit
// files always win over that fixed source.

/// Which addresses can be a focus video on tvOS.
public enum FocusVideoURL {
    /// File types AVFoundation plays on tvOS. WebM is not among them.
    static let extensions: Set<String> = ["mp4", "m4v", "mov", "m3u8"]

    /// The address if it is https with a playable file type, else nil (the tile then falls back to the GIF).
    public static func playable(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty,
              let u = URL(string: s), u.scheme?.lowercased() == "https", u.host?.isEmpty == false,
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
}

/// Sound of a focus video (setting "Ton bei Kachel-Animation", default off).
public enum FocusVideoAudio {
    /// Volume the sound fades in to. Brand intros are often mastered loud.
    public static let targetVolume: Float = 0.6
    /// Fade-in after the first picture, and fade-out on focus loss (seconds).
    public static let fadeIn = 0.4
    public static let fadeOut = 0.15
    /// Quiet wait after the first picture before the fade starts: an external decoder may need a moment to lock
    /// onto the stereo signal, which would cut the start of the jingle.
    public static let fadeInDelay = 0.3

    /// Whether this run is audible: setting on, the file has a sound track, no main playback, and only during the
    /// first pass (the picture keeps looping silently afterwards).
    public static func audible(setting: Bool, hasAudioTrack: Bool, mainPlayback: Bool, loopsDone: Int) -> Bool {
        setting && hasAudioTrack && !mainPlayback && loopsDone == 0
    }

    /// Safety margin before the end of the first pass: the fade-out must be finished before the looper's next
    /// replica starts, so no part of the jingle is heard twice.
    public static let endMargin = 0.05

    /// Item time at which the sound starts fading out during the first pass (`duration` in seconds), so it is silent
    /// at the loop boundary. Nil when the clip is too short for a fade; then the sound is muted at the boundary.
    public static func fadeOutStart(duration: Double) -> Double? {
        guard duration.isFinite else { return nil }
        let t = duration - fadeOut - endMargin
        return t > 0.1 ? t : nil
    }

    /// Volume steps of a fade from `from` to `to` (`steps` values, the last one is `to`).
    public static func ramp(from: Float, to: Float, steps: Int) -> [Float] {
        guard steps > 0 else { return [to] }
        return (1...steps).map { from + (to - from) * Float($0) / Float(steps) }
    }
}

/// Disk cache of focus videos: at most `maxBytes` and `maxAge`, least recently used goes first.
public enum FocusVideoCachePlan {
    public static let maxBytes: Int64 = 50 << 20
    public static let maxAge: TimeInterval = 7 * 24 * 3600
    /// A single file above this is not kept (it would push out everything else).
    public static let maxFileBytes: Int64 = 20 << 20
    /// Anything smaller is no real clip (an error page, an empty body). The smallest export video is about 58 KB.
    public static let minFileBytes: Int64 = 4 << 10
    /// How long a failed address rests before the next attempt: load failure (network, HTTP, not a video) and
    /// playback failure (the stored file did not play; it is deleted).
    public static let retryAfterLoadFailure: TimeInterval = 300
    public static let retryAfterPlaybackFailure: TimeInterval = 1800

    /// Result of checking a downloaded body before it goes into the cache.
    public enum Check: Equatable, Sendable {
        case ok
        case tooSmall
        case tooLarge
        case notVideo(String)
    }

    /// A body is kept only if its size is sensible and it is a video: an ISO media file (`ftyp` box at byte 4,
    /// mp4/m4v/mov) or a `video/*` content type (QuickTime files may start with another box). `head` is the start of
    /// the body (at least 8 bytes to see the box).
    public static func check(contentType: String?, head: [UInt8], bytes: Int64) -> Check {
        if bytes > maxFileBytes { return .tooLarge }
        if bytes < minFileBytes { return .tooSmall }
        let hasFtyp = head.count >= 8 && Array(head[4..<8]) == Array("ftyp".utf8)
        if hasFtyp { return .ok }
        let type = (contentType ?? "").split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        if type.hasPrefix("video/") { return .ok }
        return .notVideo(type.isEmpty ? "ohne Typ" : type)
    }

    public struct Entry: Equatable, Sendable {
        public var name: String
        public var bytes: Int64
        public var used: Date
        public init(name: String, bytes: Int64, used: Date) { self.name = name; self.bytes = bytes; self.used = used }
    }

    /// Names to delete: everything older than `maxAge`, then the least recently used until the rest fits.
    public static func evict(_ entries: [Entry], now: Date, maxBytes: Int64 = maxBytes, maxAge: TimeInterval = maxAge) -> [String] {
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
}

/// Fixed source of the ready-made packages: focus videos of the streaming services and studios, plus the stills of
/// the studios, from the public collection export (user decision 22.11.: allowed for these tiles only). Loaded at
/// runtime; an import or kit file with its own picture or animation wins.
public enum PackageFixedArt {
    static let base = "https://cdn.xperience-app.com/covers/default/"
    static let version = "7"

    /// Name in the export per TMDB watch provider of `ReadyPackages.providersDE` (only those the export has).
    static let streaming: [Int: String] = [8: "netflix", 9: "prime_video", 337: "disney_plus", 350: "apple_tv_plus",
                                           531: "paramount_plus"]

    /// Export name of a package tile (`streaming_services.netflix`, `studios.pixar`), else nil.
    static func exportName(forFolderID id: String) -> String? {
        let prefix = "pkg.streaming-de."
        if id.hasPrefix(prefix), let n = Int(id.dropFirst(prefix.count)), let name = streaming[n] {
            return "streaming_services." + name
        }
        if let st = ReadyPackages.studio(forFolderID: id) { return "studios." + st.motion }
        return nil
    }

    public static func video(forFolderID id: String) -> String? {
        exportName(forFolderID: id).map { base + $0 + ".focus.mp4?v=" + version }
    }

    /// Still of a studio tile (the streaming tiles take theirs from imports or kit files).
    public static func cover(forFolderID id: String) -> String? {
        guard id.hasPrefix("pkg.studios.") else { return nil }
        return exportName(forFolderID: id).map { base + $0 + ".webp?v=" + version }
    }

    /// Fills the gaps of package tiles: a focus video where neither video nor GIF is there yet, and a studio still
    /// where no still is there yet (its name is in the picture, so no second title on top).
    public static func apply(_ c: MediaCollection) -> MediaCollection {
        var out = c
        for i in out.folders.indices where ReadyPackages.isPackageFolder(out.folders[i].id) {
            let id = out.folders[i].id
            if (out.folders[i].focusVideo ?? "").isEmpty, (out.folders[i].focusGif ?? "").isEmpty, let v = video(forFolderID: id) {
                out.folders[i].focusVideo = v
            }
            if (out.folders[i].coverImage ?? "").isEmpty, let cover = cover(forFolderID: id) {
                out.folders[i].coverImage = cover
                out.folders[i].hideTitle = true
            }
        }
        return out
    }
}
