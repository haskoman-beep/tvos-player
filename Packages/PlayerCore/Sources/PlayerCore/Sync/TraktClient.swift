import Foundation

/// OAuth-Token (Trakt und Simkl). `expiresAt` nil = läuft nicht ab.
public struct SyncToken: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?

    public init(accessToken: String, refreshToken: String? = nil, expiresAt: Date? = nil) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiresAt = expiresAt
    }

    /// Sicherheitsabstand vor dem Ablauf, ab dem erneuert wird.
    public static let refreshLeeway: TimeInterval = 60

    public func needsRefresh(now: Date = Date()) -> Bool {
        guard let e = expiresAt else { return false }
        return e.timeIntervalSince(now) < Self.refreshLeeway
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
    /// Wave L: the service's playback entry ID (needed to delete it); nil if the service did not send one.
    public var playbackID: Int? = nil
}

public enum ScrobbleAction: String, Sendable { case start, pause, stop }

/// Trakt-API v2 (Spec §7 P4). Client-ID/Secret gibt der Nutzer über die Handy-Seite ein.
public struct TraktClient: Sendable {
    public let clientID: String
    public let clientSecret: String
    let http: APISending
    let sleep: APISleep
    /// Nach einer 401 einmal aufgerufen (mit dem abgelehnten Token); liefert das erneuerte Token oder nil.
    let onUnauthorized: (@Sendable (SyncToken) async -> SyncToken?)?
    static let base = "https://api.trakt.tv"

    public init(clientID: String, clientSecret: String, http: APISending = URLSessionSender(), sleep: @escaping APISleep = defaultAPISleep,
                onUnauthorized: (@Sendable (SyncToken) async -> SyncToken?)? = nil) {
        self.clientID = clientID; self.clientSecret = clientSecret; self.http = http; self.sleep = sleep; self.onUnauthorized = onUnauthorized
    }

    func request(_ method: String, _ path: String, token: SyncToken? = nil, json: [String: Any]? = nil) throws -> APIRequest {
        guard let u = URL(string: Self.base + path) else { throw APIError.decoding("url") }
        var h = ["Content-Type": "application/json", "trakt-api-version": "2", "trakt-api-key": clientID]
        if let token { h["Authorization"] = "Bearer \(token.accessToken)" }
        return APIRequest(method: method, url: u, headers: h, body: try json.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) })
    }

    /// 429: einmal nach `Retry-After`. 401 mit Token: einmal erneuern lassen und wiederholen.
    func perform(_ r: APIRequest, token: SyncToken?) async throws -> APIResponse {
        let res = try await http.sendRespectingRateLimit(r, sleep: sleep)
        guard res.status == 401, let token, let onUnauthorized, let fresh = await onUnauthorized(token) else { return res }
        var again = r
        again.headers["Authorization"] = "Bearer \(fresh.accessToken)"
        return try await http.sendRespectingRateLimit(again, sleep: sleep)
    }

    func json(_ r: APIRequest, token: SyncToken? = nil) async throws -> Any {
        let res = try await perform(r, token: token)
        guard (200..<300).contains(res.status) else { throw APIError.status(res.status) }
        return try JSONSerialization.jsonObject(with: res.data.isEmpty ? Data("{}".utf8) : res.data)
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

    /// Scrobble: Fortschritt in Prozent (0…100). 409 (schon erfasst) gilt als Erfolg, `stop` wird nach Netzfehler einmal wiederholt.
    public func scrobble(_ action: ScrobbleAction, imdb: String, season: Int?, episode: Int?, percent: Double, token: SyncToken) async throws {
        var body: [String: Any] = ["progress": (percent * 100).rounded() / 100]
        if let s = season, let e = episode {
            body["show"] = ["ids": ["imdb": imdb]]; body["episode"] = ["season": s, "number": e]
        } else {
            body["movie"] = ["ids": ["imdb": imdb]]
        }
        let r = try request("POST", "/scrobble/\(action.rawValue)", token: token, json: body)
        try await SyncRetry.scrobble(action, sleep: sleep) { try await perform(r, token: token) }
    }

    public func playback(token: SyncToken) async throws -> [RemoteProgress] {
        let arr = try await json(request("GET", "/sync/playback?limit=50", token: token), token: token) as? [[String: Any]] ?? []
        return arr.compactMap { o in
            let pct = (o["progress"] as? Double ?? 0) / 100
            let date = (o["paused_at"] as? String).flatMap(Self.date) ?? .distantPast
            if let m = o["movie"] as? [String: Any], let item = Self.meta(m, type: "movie") {
                return RemoteProgress(id: item.id, item: item, fraction: pct, updated: date, playbackID: SyncWriteBody.playbackID(o["id"]))
            }
            if let sh = o["show"] as? [String: Any], let ep = o["episode"] as? [String: Any], let item = Self.meta(sh, type: "series"),
               let s = ep["season"] as? Int, let e = ep["number"] as? Int {
                return RemoteProgress(id: "\(item.id):\(s):\(e)", item: item, season: s, episode: e, fraction: pct, updated: date,
                                      playbackID: SyncWriteBody.playbackID(o["id"]))
            }
            return nil
        }
    }

    public func watchlist(token: SyncToken) async throws -> [MetaPreview] {
        let arr = try await json(request("GET", "/sync/watchlist?sort_by=added&sort_how=desc", token: token), token: token) as? [[String: Any]] ?? []
        return Self.items(arr)
    }

    /// Trakt-Nutzer- und Listennamen: nur `[A-Za-z0-9._-]`, nicht nur Punkte (kein Pfad über fremde Kit-Dateien).
    public static func isSafeName(_ s: String) -> Bool {
        !s.isEmpty && !s.allSatisfy { $0 == "." } && s.unicodeScalars.allSatisfy { c in
            ("a"..."z").contains(c) || ("A"..."Z").contains(c) || ("0"..."9").contains(c) || c == "." || c == "_" || c == "-"
        }
    }

    /// Pseudo-Listen für Trakt-Empfehlungen des angemeldeten Nutzers (`/recommendations/{movies,shows}`).
    public static let recommendationSlugs = ["recommendations/movies", "recommendations/shows"]
    public static func isRecommendations(_ slug: String) -> Bool { recommendationSlugs.contains(slug) }

    /// Empfehlungen für den angemeldeten Nutzer, ohne Titel aus der Merkliste. Antwort: Titel-Objekte ohne Hülle.
    public func recommendations(series: Bool, limit: Int = 20, token: SyncToken) async throws -> [MetaPreview] {
        let n = max(1, min(limit, 100))
        let path = "/recommendations/\(series ? "shows" : "movies")?ignore_watchlisted=true&limit=\(n)"
        let arr = try await json(request("GET", path, token: token), token: token) as? [[String: Any]] ?? []
        return arr.compactMap { Self.meta($0, type: series ? "series" : "movie") }
    }

    /// Öffentliche oder eigene Liste. `user` nil = angemeldeter Nutzer ("me").
    /// `recommendations/movies` / `recommendations/shows` (nur mit Anmeldung) liefern Trakt-Empfehlungen.
    /// `limit` gilt nur für Empfehlungen (Trakt liefert dort höchstens 100, ohne Angabe 20).
    public func list(user: String?, slug: String, token: SyncToken?, limit: Int? = nil) async throws -> [MetaPreview] {
        if user == nil, Self.isRecommendations(slug) {
            guard let token else { return [] }
            return try await recommendations(series: slug.hasSuffix("shows"), limit: limit ?? 20, token: token)
        }
        let isWatchlist = slug == "watchlist" || slug == "watchlist/movies" || slug == "watchlist/shows"
        if let user, !Self.isSafeName(user) { throw TraktNameError(name: user) }
        if !isWatchlist, !Self.isSafeName(slug) { throw TraktNameError(name: slug) }
        let path: String
        // Merkliste, auch nach Typ (`watchlist/movies`, `watchlist/shows` – Fusion-Kit).
        if isWatchlist { path = "/users/\(user ?? "me")/\(slug)" }
        else if user == nil, Int(slug) != nil { path = "/lists/\(slug)/items" }   // Listen-ID (z. B. aus Nuvio)
        else { path = "/users/\(user ?? "me")/lists/\(slug)/items" }
        let arr = try await json(request("GET", path, token: token), token: token) as? [[String: Any]] ?? []
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
        ISODate.dateTime(s)
    }
}

/// Trakt-Nutzer oder -Liste mit unzulässigen Zeichen; es wird nichts gesendet.
public struct TraktNameError: Error, Equatable, CustomStringConvertible {
    public let name: String
    public var description: String { "ungültiger Trakt-Name „\(name)“" }
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
