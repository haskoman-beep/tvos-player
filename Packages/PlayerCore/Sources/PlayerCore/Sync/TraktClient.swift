import Foundation

/// OAuth-Token (Trakt und Simkl). `expiresAt` nil = läuft nicht ab.
public struct SyncToken: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?

    public init(accessToken: String, refreshToken: String? = nil, expiresAt: Date? = nil) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiresAt = expiresAt
    }

    public func needsRefresh(now: Date = Date()) -> Bool {
        guard let e = expiresAt else { return false }
        return e.timeIntervalSince(now) < 7 * 86400
    }
}

/// Geräte-Login: Code am Handy eingeben.
public struct DeviceCode: Sendable, Equatable {
    public var deviceCode: String
    public var userCode: String
    public var verificationURL: String
    public var expiresIn: Int
    public var interval: Int
}

public enum DevicePoll: Sendable, Equatable { case pending, slowDown, success(SyncToken), expired, denied, failed(Int) }

/// Fortschritt eines angefangenen Titels aus dem Sync-Dienst.
public struct RemoteProgress: Sendable, Equatable {
    /// "tt…" oder "tt…:S:E"
    public var id: String
    public var item: MetaPreview
    public var season: Int?
    public var episode: Int?
    /// 0…1
    public var fraction: Double
    public var updated: Date
}

public enum ScrobbleAction: String, Sendable { case start, pause, stop }

/// Trakt-API v2 (Spec §7 P4). Client-ID/Secret gibt der Nutzer über die Handy-Seite ein.
public struct TraktClient: Sendable {
    public let clientID: String
    public let clientSecret: String
    let http: APISending
    static let base = "https://api.trakt.tv"

    public init(clientID: String, clientSecret: String, http: APISending = URLSessionSender()) {
        self.clientID = clientID; self.clientSecret = clientSecret; self.http = http
    }

    func request(_ method: String, _ path: String, token: SyncToken? = nil, json: [String: Any]? = nil) throws -> APIRequest {
        guard let u = URL(string: Self.base + path) else { throw APIError.decoding("url") }
        var h = ["Content-Type": "application/json", "trakt-api-version": "2", "trakt-api-key": clientID]
        if let token { h["Authorization"] = "Bearer \(token.accessToken)" }
        return APIRequest(method: method, url: u, headers: h, body: try json.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) })
    }

    func json(_ r: APIRequest) async throws -> Any {
        let (s, d) = try await http.send(r)
        guard (200..<300).contains(s) else { throw APIError.status(s) }
        return try JSONSerialization.jsonObject(with: d.isEmpty ? Data("{}".utf8) : d)
    }

    // MARK: Login

    public func deviceCode() async throws -> DeviceCode {
        let o = try await json(request("POST", "/oauth/device/code", json: ["client_id": clientID])) as? [String: Any] ?? [:]
        guard let dc = o["device_code"] as? String, let uc = o["user_code"] as? String else { throw APIError.decoding("device_code") }
        return DeviceCode(deviceCode: dc, userCode: uc, verificationURL: o["verification_url"] as? String ?? "https://trakt.tv/activate",
                          expiresIn: o["expires_in"] as? Int ?? 600, interval: o["interval"] as? Int ?? 5)
    }

    public func poll(_ code: DeviceCode, now: Date = Date()) async throws -> DevicePoll {
        let (s, d) = try await http.send(request("POST", "/oauth/device/token",
                                                 json: ["code": code.deviceCode, "client_id": clientID, "client_secret": clientSecret]))
        switch s {
        case 200: return .success(try Self.token(d, now: now))
        case 400: return .pending
        case 429: return .slowDown
        case 404, 409, 410: return .expired
        case 418: return .denied
        default: return .failed(s)
        }
    }

    public func refresh(_ t: SyncToken, now: Date = Date()) async throws -> SyncToken {
        guard let rt = t.refreshToken else { throw APIError.notConnected }
        let (s, d) = try await http.send(request("POST", "/oauth/token", json: [
            "refresh_token": rt, "client_id": clientID, "client_secret": clientSecret,
            "redirect_uri": "urn:ietf:wg:oauth:2.0:oob", "grant_type": "refresh_token"]))
        guard s == 200 else { throw APIError.status(s) }
        return try Self.token(d, now: now)
    }

    static func token(_ d: Data, now: Date) throws -> SyncToken {
        let o = try JSONSerialization.jsonObject(with: d) as? [String: Any] ?? [:]
        guard let at = o["access_token"] as? String else { throw APIError.decoding("access_token") }
        let created = (o["created_at"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? now
        return SyncToken(accessToken: at, refreshToken: o["refresh_token"] as? String,
                         expiresAt: (o["expires_in"] as? Double).map { created.addingTimeInterval($0) })
    }

    // MARK: Daten

    /// Scrobble: Fortschritt in Prozent (0…100).
    public func scrobble(_ action: ScrobbleAction, imdb: String, season: Int?, episode: Int?, percent: Double, token: SyncToken) async throws {
        var body: [String: Any] = ["progress": (percent * 100).rounded() / 100]
        if let s = season, let e = episode {
            body["show"] = ["ids": ["imdb": imdb]]; body["episode"] = ["season": s, "number": e]
        } else {
            body["movie"] = ["ids": ["imdb": imdb]]
        }
        _ = try await json(request("POST", "/scrobble/\(action.rawValue)", token: token, json: body))
    }

    public func playback(token: SyncToken) async throws -> [RemoteProgress] {
        let arr = try await json(request("GET", "/sync/playback?limit=50", token: token)) as? [[String: Any]] ?? []
        return arr.compactMap { o in
            let pct = (o["progress"] as? Double ?? 0) / 100
            let date = (o["paused_at"] as? String).flatMap(Self.date) ?? .distantPast
            if let m = o["movie"] as? [String: Any], let item = Self.meta(m, type: "movie") {
                return RemoteProgress(id: item.id, item: item, fraction: pct, updated: date)
            }
            if let sh = o["show"] as? [String: Any], let ep = o["episode"] as? [String: Any], let item = Self.meta(sh, type: "series"),
               let s = ep["season"] as? Int, let e = ep["number"] as? Int {
                return RemoteProgress(id: "\(item.id):\(s):\(e)", item: item, season: s, episode: e, fraction: pct, updated: date)
            }
            return nil
        }
    }

    public func watchlist(token: SyncToken) async throws -> [MetaPreview] {
        let arr = try await json(request("GET", "/sync/watchlist?sort_by=added&sort_how=desc", token: token)) as? [[String: Any]] ?? []
        return Self.items(arr)
    }

    /// Öffentliche oder eigene Liste. `user` nil = angemeldeter Nutzer ("me").
    public func list(user: String?, slug: String, token: SyncToken?) async throws -> [MetaPreview] {
        let path: String
        if slug == "watchlist" { path = "/users/\(user ?? "me")/watchlist" }
        else if user == nil, Int(slug) != nil { path = "/lists/\(slug)/items" }   // Listen-ID (z. B. aus Nuvio)
        else { path = "/users/\(user ?? "me")/lists/\(slug)/items" }
        let arr = try await json(request("GET", path, token: token)) as? [[String: Any]] ?? []
        return Self.items(arr)
    }

    static func items(_ arr: [[String: Any]]) -> [MetaPreview] {
        arr.compactMap { o in
            if let m = o["movie"] as? [String: Any] { return meta(m, type: "movie") }
            if let s = o["show"] as? [String: Any] { return meta(s, type: "series") }
            return nil
        }
    }

    static func meta(_ o: [String: Any], type: String) -> MetaPreview? {
        guard let ids = o["ids"] as? [String: Any], let imdb = ids["imdb"] as? String, imdb.hasPrefix("tt"),
              let title = o["title"] as? String else { return nil }
        return MetaPreview(id: imdb, type: type, name: title, poster: metahubPoster(imdb), background: metahubBackground(imdb),
                           releaseInfo: (o["year"] as? Int).map(String.init))
    }

    static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

/// Trakt-Listen-Link → Quelle: trakt.tv/users/NAME/lists/SLUG oder trakt.tv/users/NAME/watchlist.
public enum TraktLink {
    public static func source(from text: String) -> CatalogSource? {
        guard let u = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), u.host?.contains("trakt.tv") == true else { return nil }
        let p = u.path.split(separator: "/").map(String.init)
        guard p.count >= 3, p[0] == "users" else { return nil }
        let user = p[1]
        if p[2] == "watchlist" {
            return CatalogSource(id: "trakt.\(user).watchlist", title: "Merkliste von \(user)", kind: .trakt(user: user, list: "watchlist"), mediaType: .both)
        }
        guard p.count >= 4, p[2] == "lists" else { return nil }
        let slug = p[3]
        return CatalogSource(id: "trakt.\(user).\(slug)", title: slug.replacingOccurrences(of: "-", with: " ").capitalized,
                             kind: .trakt(user: user, list: slug), mediaType: .both)
    }
}
