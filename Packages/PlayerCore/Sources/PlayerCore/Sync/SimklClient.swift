import Foundation

/// Simkl-API (Spec §7 P4). PIN-Login wie Trakt-Geräte-Code; Scrobble/Playback im Trakt-Format.
public struct SimklClient: Sendable {
    public let clientID: String
    let http: APISending
    let sleep: APISleep
    static let base = "https://api.simkl.com"

    public init(clientID: String, http: APISending = URLSessionSender(), sleep: @escaping APISleep = defaultAPISleep) {
        self.clientID = clientID; self.http = http; self.sleep = sleep
    }

    func request(_ method: String, _ path: String, token: SyncToken? = nil, json: [String: Any]? = nil) throws -> APIRequest {
        let sep = path.contains("?") ? "&" : "?"
        guard let u = URL(string: Self.base + path + sep + "client_id=\(clientID)") else { throw APIError.decoding("url") }
        // Simkl verlangt bei jeder Anfrage App-Name, -Version und User-Agent.
        var h = ["Content-Type": "application/json", "simkl-api-key": clientID,
                 "app-name": SyncAppInfo.name, "app-version": SyncAppInfo.version, "User-Agent": SyncAppInfo.userAgent]
        if let token { h["Authorization"] = "Bearer \(token.accessToken)" }
        return APIRequest(method: method, url: u, headers: h, body: try json.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) })
    }

    func json(_ r: APIRequest) async throws -> Any {
        let res = try await http.sendRespectingRateLimit(r, sleep: sleep)
        guard (200..<300).contains(res.status) else { throw APIError.status(res.status) }
        return try JSONSerialization.jsonObject(with: res.data.isEmpty ? Data("{}".utf8) : res.data)
    }

    public func deviceCode() async throws -> DeviceCode {
        let o = try await json(request("GET", "/oauth/pin")) as? [String: Any] ?? [:]
        guard let uc = o["user_code"] as? String else { throw APIError.decoding("user_code") }
        return DeviceCode(deviceCode: uc, userCode: uc, verificationURL: o["verification_url"] as? String ?? "https://simkl.com/pin",
                          expiresIn: o["expires_in"] as? Int ?? 900, interval: o["interval"] as? Int ?? 5)
    }

    public func poll(_ code: DeviceCode) async throws -> DevicePoll {
        let (s, d) = try await http.send(request("GET", "/oauth/pin/\(code.userCode)"))
        guard s == 200 else { return s == 404 ? .expired : .failed(s) }
        let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
        if let t = o["access_token"] as? String { return .success(SyncToken(accessToken: t)) }
        return .pending
    }

    public func scrobble(_ action: ScrobbleAction, imdb: String, season: Int?, episode: Int?, percent: Double, token: SyncToken) async throws {
        var body: [String: Any] = ["progress": (percent * 100).rounded() / 100]
        if let s = season, let e = episode {
            body["show"] = ["ids": ["imdb": imdb]]; body["episode"] = ["season": s, "number": e]
        } else { body["movie"] = ["ids": ["imdb": imdb]] }
        let r = try request("POST", "/scrobble/\(action.rawValue)", token: token, json: body)
        try await SyncRetry.scrobble(action, sleep: sleep) { try await http.sendRespectingRateLimit(r, sleep: sleep) }
    }

    public func playback(token: SyncToken) async throws -> [RemoteProgress] {
        let arr = try await json(request("GET", "/sync/playback", token: token)) as? [[String: Any]] ?? []
        return arr.compactMap { o in
            let pct = (o["progress"] as? Double ?? 0) / 100
            let date = (o["paused_at"] as? String).flatMap(TraktClient.date) ?? .distantPast
            if let m = o["movie"] as? [String: Any], let item = TraktClient.meta(m, type: "movie") {
                return RemoteProgress(id: item.id, item: item, fraction: pct, updated: date, playbackID: o["id"] as? Int)
            }
            if let sh = o["show"] as? [String: Any], let ep = o["episode"] as? [String: Any], let item = TraktClient.meta(sh, type: "series"),
               let s = ep["season"] as? Int, let e = (ep["episode"] ?? ep["number"]) as? Int {
                return RemoteProgress(id: "\(item.id):\(s):\(e)", item: item, season: s, episode: e, fraction: pct, updated: date,
                                      playbackID: o["id"] as? Int)
            }
            return nil
        }
    }

    /// "Plan to watch" = Merkliste.
    public func watchlist(token: SyncToken) async throws -> [MetaPreview] {
        let o = try await json(request("GET", "/sync/all-items/plantowatch", token: token)) as? [String: Any] ?? [:]
        let movies = (o["movies"] as? [[String: Any]] ?? []).compactMap { ($0["movie"] as? [String: Any]).flatMap { TraktClient.meta($0, type: "movie") } }
        let shows = ((o["shows"] as? [[String: Any]] ?? []) + (o["anime"] as? [[String: Any]] ?? []))
            .compactMap { ($0["show"] as? [String: Any]).flatMap { TraktClient.meta($0, type: "series") } }
        return movies + shows
    }
}
