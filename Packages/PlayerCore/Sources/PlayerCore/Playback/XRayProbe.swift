import Foundation

/// Wave X0 (spike): debug probe on pause. With the developer switch on, a pause grabs the paused frame from the
/// engine (resident bytes only), runs Vision face detection on it and logs `xray:` lines. Pure decisions and log
/// texts live here so they are testable on Linux; the app part is App/Sources/Views/Player/XRayProbe.swift.
public enum XRayProbe {
    /// Device setting key (UserDefaults, not the profile: it is a developer switch, like the hitch log).
    public static let settingKey = "debug.xrayProbe"
    /// Width asked from the engine (the still decoder scales down, never up).
    public static let maxWidth = 1920
    /// Wait after the pause before the grab starts: a quick pause/play pair (or a double press) costs nothing,
    /// and the pause itself never waits for the probe.
    public static let settleDelay: Duration = .milliseconds(400)
    /// Frames whose decoded time is further than this from the paused position may show another scene.
    public static let maxFrameOffset = 0.1
    /// Faces logged one per line, the largest first; the count line always has the full number.
    public static let maxLoggedFaces = 8

    /// Whether a pause starts a probe. `playing` is the new state after the change; `wasPlaying` the old one, so
    /// only a real transition from playing to paused counts (not the paused state at load or after a seek).
    /// `ended` (end of file, autoplay follows) and an inactive scene (TV button, app in the background) are no pause.
    public static func shouldStart(enabled: Bool, wasPlaying: Bool, playing: Bool, loading: Bool, ended: Bool,
                                   sceneActive: Bool, duration: Double, failed: Bool, blocked: Bool) -> Bool {
        enabled && wasPlaying && !playing && !loading && !ended && sceneActive && duration > 0 && !failed && !blocked
    }

    /// Engine log line of a held picture that was decoded and reshaped on the CPU (Dolby Vision Profile 5 with the
    /// still reshaping trait, during an audio switch or reload) → `P5 gehaltenes Bild per CPU (… ms)`; nil otherwise.
    /// Engine form (7.71.2): `[AetherEngine] held picture: up after 412ms (Dolby Vision reshaped, 1920x1080, hdr=false)`.
    public static func heldPictureLine(engineLine line: String) -> String? {
        guard line.contains("held picture: up after"), line.contains("Dolby Vision reshaped"),
              let r = line.range(of: "up after ") else { return nil }
        let digits = line[r.upperBound...].prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return "P5 gehaltenes Bild per CPU (\(digits) ms)"
    }

    /// Key for the memory of sources known to be Profile 5: scheme, host, port and path. The query is dropped
    /// (tokens and expiry stamps change between resolves of the same file).
    public static func sourceKey(_ url: URL) -> String {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        c.query = nil; c.fragment = nil; c.user = nil; c.password = nil
        return c.string ?? url.absoluteString
    }

    /// Content type for the log: "SDR", "HDR10", "HDR10+", "HLG", "DV P5", "DV P7→8.1", "DV P8" or "DV ?".
    /// `format` is the engine's `sourceVideoFormat` name, `dvProfile` its `sourceDVProfile`,
    /// `convertedToP81` whether the engine rewrites a Profile 7 source to 8.1.
    public static func contentLabel(format: String?, dvProfile: Int?, convertedToP81: Bool) -> String {
        if let p = dvProfile {
            if p == 7 { return convertedToP81 ? "DV P7→8.1" : "DV P7" }
            return "DV P\(p)"
        }
        switch format {
        case "sdr": return "SDR"
        case "hdr10": return "HDR10"
        case "hdr10Plus": return "HDR10+"
        case "hlg": return "HLG"
        case "dolbyVision": return "DV ?"
        case let f?: return f
        case nil: return "?"
        }
    }

    /// Profile 5 (and AV1 10.0) has no displayable base layer: without the still reshaping trait no frame comes.
    public static func isProfile5(dvProfile: Int?) -> Bool { dvProfile == 5 || dvProfile == 10 }

    public enum FrameVerdict: Equatable, Sendable {
        /// Decoded up to the paused position (the frame the user sees).
        case atTarget
        /// Decoded, but at another time (keyframe of the segment, ladder still): maybe another scene.
        case offTarget(seconds: Double)
        /// The engine stopped before the target (750 ms / 900 packet bound).
        case unrefined(seconds: Double)
    }

    public static func verdict(requested: Double, actual: Double, refined: Bool) -> FrameVerdict {
        let delta = actual - requested
        if !refined { return .unrefined(seconds: delta) }
        return abs(delta) < maxFrameOffset ? .atTarget : .offTarget(seconds: delta)
    }

    public static func verdictText(_ v: FrameVerdict) -> String {
        switch v {
        case .atTarget: "am Ziel"
        case .offTarget(let d): "daneben \(signed(d)) s"
        case .unrefined(let d): "nicht verfeinert \(signed(d)) s"
        }
    }

    /// One detected face for the log. Box in pixels of the grabbed frame; angles in degrees (nil = not reported).
    public struct Face: Equatable, Sendable {
        public var width: Int
        public var height: Int
        public var confidence: Double
        public var yaw: Double?
        public var roll: Double?
        public var quality: Double?
        public var landmarks: Bool

        public init(width: Int, height: Int, confidence: Double, yaw: Double? = nil, roll: Double? = nil,
                    quality: Double? = nil, landmarks: Bool = false) {
            self.width = width; self.height = height; self.confidence = confidence
            self.yaw = yaw; self.roll = roll; self.quality = quality; self.landmarks = landmarks
        }
    }

    /// Largest faces first, at most `maxLoggedFaces`.
    public static func facesForLog(_ faces: [Face]) -> [Face] {
        Array(faces.sorted { $0.width * $0.height > $1.width * $1.height }.prefix(maxLoggedFaces))
    }

    /// Start line: content type and what the engine says about stills for it.
    public static func startLine(content: String, at seconds: Double, stills: Bool, drawsInView: Bool,
                                 reshapingBuiltIn: Bool) -> String {
        "Pause bei \(fixed(seconds, 2)) s · \(content) · Standbilder \(stills ? "ja" : "nein")"
            + " · Vorschau nur im View \(drawsInView ? "ja" : "nein") · P5-Umformung \(reshapingBuiltIn ? "eingebaut" : "fehlt")"
    }

    public static func frameLine(ms: Int, width: Int, height: Int, verdict: FrameVerdict, content: String) -> String {
        "Bild \(width)×\(height) in \(ms) ms · \(verdictText(verdict)) · \(content)"
    }

    public static func noFrameLine(ms: Int, content: String, reason: String) -> String {
        "kein Bild nach \(ms) ms · \(content) · \(reason)"
    }

    public static func visionLine(ms: Int, faces: Int, frameWidth: Int) -> String {
        "Vision \(ms) ms · \(faces) Gesicht\(faces == 1 ? "" : "er") · Breite \(frameWidth)"
    }

    public static func faceLine(index: Int, _ f: Face) -> String {
        var parts = ["Gesicht \(index + 1): \(f.width)×\(f.height) px", "Konfidenz \(fixed(f.confidence, 2))"]
        if let y = f.yaw { parts.append("Gier \(Int(y.rounded()))°") }
        if let r = f.roll { parts.append("Roll \(Int(r.rounded()))°") }
        if let q = f.quality { parts.append("Qualität \(fixed(q, 2))") }
        parts.append(f.landmarks ? "Landmarken ja" : "Landmarken nein")
        return parts.joined(separator: " · ")
    }

    public static func totalLine(ms: Int, outcome: String) -> String { "fertig nach \(ms) ms · \(outcome)" }

    static func fixed(_ v: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), v)
    }

    static func signed(_ v: Double) -> String { (v >= 0 ? "+" : "") + fixed(v, 2) }
}

/// Small most-recent-first key set with a cap (sources known to be Dolby Vision Profile 5), Codable for UserDefaults.
public struct RecentKeySet: Codable, Equatable, Sendable {
    public static let defaultCapacity = 200
    public private(set) var keys: [String]
    public let capacity: Int

    public init(keys: [String] = [], capacity: Int = RecentKeySet.defaultCapacity) {
        self.capacity = max(1, capacity)
        self.keys = Array(keys.prefix(self.capacity))
    }

    public func contains(_ key: String) -> Bool { keys.contains(key) }

    /// Moves the key to the front; the oldest key falls out beyond the capacity. Returns true when it was new.
    @discardableResult public mutating func insert(_ key: String) -> Bool {
        let new = !keys.contains(key)
        keys.removeAll { $0 == key }
        keys.insert(key, at: 0)
        if keys.count > capacity { keys.removeLast(keys.count - capacity) }
        return new
    }
}
