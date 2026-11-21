import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// POST-fähiger Transport (Innertube braucht POST mit JSON-Körper).
public protocol HTTPPosting: Sendable {
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> Data
}

public struct URLSessionPoster: HTTPPosting {
    public init() {}
    public func post(_ url: URL, headers: [String: String], body: Data) async throws -> Data {
        var r = URLRequest(url: url, timeoutInterval: 10)
        r.httpMethod = "POST"
        r.httpBody = body
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.data(for: r)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw AddonError.http(h.statusCode) }
        return data
    }
}

/// Abspielbare Trailer-Adresse.
public struct YouTubeStream: Sendable, Equatable {
    public var url: URL
    /// true = HLS-Master (Ton als eigene Rendition, AVPlayer wählt die Stufe).
    public var isHLS: Bool
    /// Höhe der progressiven Datei (bei HLS nil).
    public var height: Int?
    /// Innertube-Client, der die Adresse geliefert hat (fürs Log).
    public var client: String
}

/// Trailer direkt im eigenen Player: Innertube-Player-API (Vorbild NuvioMobile `InAppYouTubeExtractor`).
/// Kein API-Schlüssel nötig; ein Besucher-Token (`visitor_id`) reicht, damit der visionOS-Client ein HLS-Master
/// liefert. Ohne HLS: progressive MP4 mit Ton (itag 18 o. ä.) mit direkter URL. Formate mit `signatureCipher`
/// werden ausgelassen (keine Signatur-Entschlüsselung) – dann `nil`.
public struct YouTubeResolver: Sendable {
    let poster: HTTPPosting
    static let maxHeight = 1080

    public init(poster: HTTPPosting = URLSessionPoster()) { self.poster = poster }

    struct Client: Sendable {
        var key: String
        var id: String
        var version: String
        var userAgent: String
        var context: [String: String]
    }

    /// Reihenfolge: visionOS (liefert HLS), iOS, Android (liefert progressive 360p mit Ton).
    static let clients: [Client] = [
        Client(key: "visionos", id: "101", version: "1.02",
               userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
               context: ["clientName": "VISIONOS", "clientVersion": "1.02", "deviceMake": "Apple", "deviceModel": "RealityDevice17,1",
                         "osName": "visionOS", "osVersion": "26.5.23O471"]),
        Client(key: "ios", id: "5", version: "20.10.1",
               userAgent: "com.google.ios.youtube/20.10.1 (iPhone16,2; U; CPU iOS 17_4 like Mac OS X)",
               context: ["clientName": "IOS", "clientVersion": "20.10.1", "deviceMake": "Apple", "deviceModel": "iPhone16,2",
                         "osName": "iPhone", "osVersion": "17.4.0.21E219"]),
        Client(key: "android", id: "3", version: "20.10.35",
               userAgent: "com.google.android.youtube/20.10.35 (Linux; U; Android 14; en_US) gzip",
               context: ["clientName": "ANDROID", "clientVersion": "20.10.35", "osName": "Android", "osVersion": "14",
                         "platform": "MOBILE"]),
    ]

    static let base = "https://www.youtube.com/youtubei/v1"

    public static func isVideoID(_ s: String) -> Bool {
        s.count == 11 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// Erste abspielbare Adresse oder nil. `log` bekommt je Client eine Zeile.
    public func resolve(videoID: String, log: @Sendable (String) -> Void = { _ in }) async -> YouTubeStream? {
        guard Self.isVideoID(videoID) else { log("ungültige Video-ID"); return nil }
        let visitor = await visitorData()
        if visitor == nil { log("kein Besucher-Token") }
        var fallback: YouTubeStream?
        for c in Self.clients {
            do {
                let data = try await player(videoID: videoID, client: c, visitor: visitor)
                let r = Self.parsePlayer(data, client: c.key)
                log("\(c.key): \(r.status ?? "?") · HLS \(r.hls != nil ? "ja" : "nein") · MP4 \(r.progressive.count)")
                if let h = r.hls { return h }
                if fallback == nil, let p = r.progressive.first { fallback = p }
            } catch {
                log("\(c.key): \(error)")
            }
        }
        return fallback
    }

    func visitorData() async -> String? {
        guard let u = URL(string: Self.base + "/visitor_id?prettyPrint=false") else { return nil }
        let body: [String: Any] = ["context": ["client": ["clientName": "WEB", "clientVersion": "2.20250120.01.00", "hl": "en", "gl": "US"]]]
        guard let b = try? JSONSerialization.data(withJSONObject: body),
              let d = try? await poster.post(u, headers: ["Content-Type": "application/json"], body: b),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let v = (obj["responseContext"] as? [String: Any])?["visitorData"] as? String, !v.isEmpty else { return nil }
        return v.removingPercentEncoding ?? v
    }

    func player(videoID: String, client c: Client, visitor: String?) async throws -> Data {
        guard let u = URL(string: Self.base + "/player?prettyPrint=false") else { throw TMDBError.badURL }
        var ctx: [String: Any] = c.context
        ctx["hl"] = "en"; ctx["gl"] = "US"
        if c.key == "android" { ctx["androidSdkVersion"] = 34 }
        if let visitor { ctx["visitorData"] = visitor }
        let body: [String: Any] = [
            "videoId": videoID, "contentCheckOk": true, "racyCheckOk": true,
            "context": ["client": ctx],
            "playbackContext": ["contentPlaybackContext": ["html5Preference": "HTML5_PREF_WANTS"]],
        ]
        var h = ["Content-Type": "application/json", "Origin": "https://www.youtube.com", "User-Agent": c.userAgent,
                 "X-YouTube-Client-Name": c.id, "X-YouTube-Client-Version": c.version]
        if let visitor { h["X-Goog-Visitor-Id"] = visitor }
        return try await poster.post(u, headers: h, body: try JSONSerialization.data(withJSONObject: body))
    }

    struct PlayerResult {
        var status: String?
        var hls: YouTubeStream?
        /// Progressive Dateien mit Ton und direkter URL, ≤ 1080p, beste zuerst (MP4 vor WebM).
        var progressive: [YouTubeStream]
    }

    static func parsePlayer(_ data: Data, client: String) -> PlayerResult {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return PlayerResult(progressive: []) }
        let status = (obj["playabilityStatus"] as? [String: Any])?["status"] as? String
        guard status == "OK", let sd = obj["streamingData"] as? [String: Any] else { return PlayerResult(status: status, progressive: []) }
        let hls = (sd["hlsManifestUrl"] as? String).flatMap(URL.init(string:))
            .map { YouTubeStream(url: $0, isHLS: true, height: nil, client: client) }
        var prog: [(s: YouTubeStream, mp4: Bool)] = []
        for f in sd["formats"] as? [[String: Any]] ?? [] {
            // Nur direkte URLs; `signatureCipher`/`cipher` bräuchte Entschlüsselung.
            guard let s = f["url"] as? String, let u = URL(string: s) else { continue }
            let mime = f["mimeType"] as? String ?? ""
            guard mime.isEmpty || mime.hasPrefix("video/") else { continue }
            let height = (f["height"] as? Int) ?? qualityHeight(f["qualityLabel"] as? String) ?? 0
            guard height <= maxHeight else { continue }
            prog.append((YouTubeStream(url: u, isHLS: false, height: height, client: client), !mime.contains("webm")))
        }
        prog.sort { a, b in (a.s.height ?? 0) != (b.s.height ?? 0) ? (a.s.height ?? 0) > (b.s.height ?? 0) : (a.mp4 && !b.mp4) }
        return PlayerResult(status: status, hls: hls, progressive: prog.map(\.s))
    }

    static func qualityHeight(_ label: String?) -> Int? {
        guard let l = label, let p = l.firstIndex(of: "p") else { return nil }
        return Int(l[..<p])
    }
}
