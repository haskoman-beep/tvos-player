import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Nuvio account sync errors. No case carries a password, token, e-mail address, body or URL: `code` is the short
/// server error identifier only (`PGRST202`, `invalid_credentials`), `decoding` names the field or payload.
public enum NuvioError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The session is not (or no longer) accepted: 401 on a data call without a successful refresh, or 400/401/403
    /// on the refresh call itself. The caller wipes the stored session.
    case signedOut
    /// Still 429 after one wait for `Retry-After`.
    case rateLimited
    /// Any other non-2xx answer (403 = row-level-security refusal).
    case status(Int, code: String?)
    /// The request did not get an answer (no network, time limit, TLS …).
    case offline
    /// The answer could not be read.
    case decoding(String)

    public var description: String {
        switch self {
        case .signedOut: return "Nuvio: Sitzung abgelaufen"
        case .rateLimited: return "Nuvio: zu viele Anfragen (429)"
        case .status(let s, let code): return "Nuvio: HTTP \(s)" + (code.map { " (\($0))" } ?? "")
        case .offline: return "Nuvio: nicht erreichbar"
        case .decoding(let what): return "Nuvio: Antwort unlesbar (\(what))"
        }
    }
}

/// The only calls the client can build (plan section 1.4). Nothing that writes profiles, addons, collections or the
/// library, deletes data, signs up or touches settings can be expressed.
public enum NuvioEndpoint: String, CaseIterable, Sendable {
    case signIn, refresh, signOut
    case profiles, addons, collections
    case progress, progressCursor, progressDelta, pushProgress
    case watched, watchedCursor, watchedDelta

    public var method: String { self == .addons ? "GET" : "POST" }

    /// Path below `NuvioClient.base`.
    public var path: String {
        switch self {
        case .signIn, .refresh: return "/auth/v1/token"
        case .signOut: return "/auth/v1/logout"
        case .profiles: return "/rest/v1/rpc/sync_pull_profiles"
        case .addons: return "/rest/v1/addons"
        case .collections: return "/rest/v1/rpc/sync_pull_collections"
        case .progress: return "/rest/v1/rpc/sync_pull_watch_progress"
        case .progressCursor: return "/rest/v1/rpc/sync_get_watch_progress_delta_cursor"
        case .progressDelta: return "/rest/v1/rpc/sync_pull_watch_progress_delta"
        case .pushProgress: return "/rest/v1/rpc/sync_push_watch_progress"
        case .watched: return "/rest/v1/rpc/sync_pull_watched_items"
        case .watchedCursor: return "/rest/v1/rpc/sync_get_watched_items_delta_cursor"
        case .watchedDelta: return "/rest/v1/rpc/sync_pull_watched_items_delta"
        }
    }

    /// Query string (without `?`); only the auth grants and the addon table read have one.
    public func query(profile: Int) -> String? {
        switch self {
        case .signIn: return "grant_type=password"
        case .refresh: return "grant_type=refresh_token"
        case .addons: return "select=*&profile_id=eq.\(profile)&order=sort_order"
        default: return nil
        }
    }

    /// Calls that send `Authorization: Bearer` (all but sign-in and refresh).
    var authorized: Bool { self != .signIn && self != .refresh }
}

/// What `onUnauthorized` did with a refused access token (review 2, finding 9).
public enum NuvioRenewal: Equatable, Sendable {
    /// A renewed session (the app stored it); the request is sent once more with it.
    case renewed(NuvioSession)
    /// The account refused the refresh (`NuvioError.signedOut` from `refresh`): the call ends in `.signedOut`.
    case refused
    /// The refresh could not run (offline, 429, 5xx, unreadable answer): the call ends in `.offline` and the stored
    /// session stays.
    case unavailable
}

/// Client for the public Nuvio API (reference v1.3, `https://api.nuvio.tv`). Every call goes through `APISending`.
/// 429: one wait for `Retry-After` (at most 10 s), then `.rateLimited`. 401 on a data call: `onUnauthorized` is asked
/// once (it refreshes and stores the session); `.renewed` sends the request once more, `.refused` is `.signedOut`,
/// `.unavailable` is `.offline`. The default sender refuses redirects (`URLSessionByteTransport.nuvio`), so a 3xx is
/// an answer (`.status`), never a second request with the body or token elsewhere.
public struct NuvioClient: Sendable {
    public static let base = URL(string: "https://api.nuvio.tv")!
    /// The publishable key from the public API reference (meant for public clients).
    public static let publishableKey = "sb_publishable_1Clq8rlTVACkdcZuqr6_AD__xUUC_EN"
    /// Lifetime assumed when an auth answer has no `expires_in`.
    public static let defaultLifetime: TimeInterval = 3600
    /// Largest page of a delta pull (the server clamps to 1…1000).
    public static let maxDeltaLimit = 1000

    let http: APISending
    let sleep: APISleep
    let onUnauthorized: (@Sendable (NuvioSession) async -> NuvioRenewal)?

    public init(http: APISending = URLSessionSender(client: LimitedHTTPClient.nuvio), sleep: @escaping APISleep = defaultAPISleep,
                onUnauthorized: (@Sendable (NuvioSession) async -> NuvioRenewal)? = nil) {
        self.http = http; self.sleep = sleep; self.onUnauthorized = onUnauthorized
    }

    // MARK: Requests

    func request(_ e: NuvioEndpoint, profile: Int = 1, body: [String: JSONValue]? = nil, raw: Data? = nil,
                 session: NuvioSession? = nil) throws -> APIRequest {
        let q = e.query(profile: profile).map { "?" + $0 } ?? ""
        guard let url = URL(string: Self.base.absoluteString + e.path + q) else { throw NuvioError.decoding("url") }
        var h = ["apikey": Self.publishableKey, "User-Agent": SyncAppInfo.userAgent, "Accept": "application/json"]
        if e.authorized, let session { h["Authorization"] = "Bearer \(session.accessToken)" }
        var data = raw
        if data == nil, let body { data = try Self.encoder.encode(body) }
        if data != nil { h["Content-Type"] = "application/json" }
        return APIRequest(method: e.method, url: url, headers: h, body: data)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    /// Sends with the 429 rule; transport errors become `.offline` (cancellation stays cancellation).
    private func send(_ r: APIRequest) async throws -> APIResponse {
        let res: APIResponse
        do {
            res = try await http.sendRespectingRateLimit(r, sleep: sleep)
        } catch is CancellationError {
            throw CancellationError()
        } catch let e as NuvioError {
            throw e
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw NuvioError.offline
        }
        if res.status == 429 { throw NuvioError.rateLimited }
        return res
    }

    /// A data call: 401 → ask `onUnauthorized` once and resend with the renewed session; still 401, or the refresh
    /// refused → `.signedOut`; the refresh could not run → `.offline` (the session stays).
    func perform(_ r: APIRequest, session: NuvioSession) async throws -> Data {
        var res = try await send(r)
        if res.status == 401, let onUnauthorized {
            switch await onUnauthorized(session) {
            case .renewed(let fresh):
                var again = r
                again.headers["Authorization"] = "Bearer \(fresh.accessToken)"
                res = try await send(again)
            case .refused:
                throw NuvioError.signedOut
            case .unavailable:
                if Task.isCancelled { throw CancellationError() }
                throw NuvioError.offline
            }
        }
        if res.status == 401 { throw NuvioError.signedOut }
        guard (200..<300).contains(res.status) else {
            throw NuvioError.status(res.status, code: NuvioPayload.errorCode(res.data))
        }
        return res.data
    }

    // MARK: Auth

    /// `POST auth/v1/token?grant_type=password`. The two values go into the body only and are kept nowhere.
    public func signIn(email: String, password: String, now: Date = Date()) async throws -> NuvioSession {
        let r = try request(.signIn, body: ["email": .string(email), "password": .string(password)])
        let res = try await send(r)
        guard (200..<300).contains(res.status) else {
            throw NuvioError.status(res.status, code: NuvioPayload.errorCode(res.data))
        }
        let a = try Self.auth(res.data)
        guard let user = a.userID, !user.isEmpty else { throw NuvioError.decoding("user") }
        guard let refresh = a.refreshToken else { throw NuvioError.decoding("refresh_token") }
        return NuvioSession(accessToken: a.accessToken, refreshToken: refresh,
                            expiresAt: now.addingTimeInterval(a.expiresIn ?? Self.defaultLifetime), userID: user)
    }

    /// `POST auth/v1/token?grant_type=refresh_token`. Keeps the user id, and the old refresh token when the answer
    /// has none. 400/401/403 → `.signedOut` (the session is gone on the server).
    public func refresh(_ s: NuvioSession, now: Date = Date()) async throws -> NuvioSession {
        guard !s.refreshToken.isEmpty else { throw NuvioError.signedOut }
        let res = try await send(try request(.refresh, body: ["refresh_token": .string(s.refreshToken)]))
        if [400, 401, 403].contains(res.status) { throw NuvioError.signedOut }
        guard (200..<300).contains(res.status) else {
            throw NuvioError.status(res.status, code: NuvioPayload.errorCode(res.data))
        }
        let a = try Self.auth(res.data)
        return NuvioSession(accessToken: a.accessToken, refreshToken: a.refreshToken ?? s.refreshToken,
                            expiresAt: now.addingTimeInterval(a.expiresIn ?? Self.defaultLifetime), userID: s.userID)
    }

    /// `refresh` as a `NuvioRenewal`, for the app's `onUnauthorized` hook (which stores a renewed session):
    /// `.signedOut` → `.refused`, any other failure → `.unavailable`.
    public func renewal(_ s: NuvioSession, now: Date = Date()) async -> NuvioRenewal {
        do { return .renewed(try await refresh(s, now: now)) } catch NuvioError.signedOut { return .refused } catch {
            return .unavailable
        }
    }

    /// `POST auth/v1/logout`. The reference (v1.3, "Sign out") documents no `scope` parameter, so none is sent; whether
    /// the server ends only this session or all sessions of the account is not stated (review 2, finding 14). No refresh on 401 (that answer already means signed out: `.signedOut`).
    public func signOut(_ s: NuvioSession) async throws {
        let res = try await send(try request(.signOut, session: s))
        if res.status == 401 { throw NuvioError.signedOut }
        guard (200..<300).contains(res.status) else {
            throw NuvioError.status(res.status, code: NuvioPayload.errorCode(res.data))
        }
    }

    struct Auth { var accessToken: String; var refreshToken: String?; var expiresIn: TimeInterval?; var userID: String? }

    static func auth(_ d: Data) throws -> Auth {
        guard case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: d) else {
            throw NuvioError.decoding("token")
        }
        guard case .string(let at)? = o["access_token"], !at.isEmpty else { throw NuvioError.decoding("access_token") }
        var rt: String?
        if case .string(let s)? = o["refresh_token"], !s.isEmpty { rt = s }
        var user: String?
        if case .object(let u)? = o["user"], case .string(let id)? = u["id"] { user = id }
        return Auth(accessToken: at, refreshToken: rt, expiresIn: seconds(o["expires_in"]), userID: user)
    }

    /// `expires_in` as a positive number of seconds (number or numeric string).
    private static func seconds(_ v: JSONValue?) -> TimeInterval? {
        let n: Double?
        switch v {
        case .int(let i)?: n = Double(i)
        case .uint(let u)?: n = Double(u)
        case .double(let d)?: n = d
        case .string(let s)?: n = Double(s.trimmingCharacters(in: .whitespaces))
        default: n = nil
        }
        guard let n, n.isFinite, n > 0 else { return nil }
        return n
    }

    // MARK: Profiles, addons, collections

    /// `rpc/sync_pull_profiles` (no body). Unreadable rows are left out.
    public func profiles(_ s: NuvioSession) async throws -> [NuvioProfile] {
        let d = try await perform(try request(.profiles, session: s), session: s)
        return try NuvioPage<NuvioProfile>.decode(d, context: "profiles").rows
    }

    /// `GET rest/v1/addons?select=*&profile_id=eq.N&order=sort_order`, sorted by `sortOrder` (stable).
    public func addons(profile: Int, _ s: NuvioSession) async throws -> [NuvioAddon] {
        let d = try await perform(try request(.addons, profile: profile, session: s), session: s)
        let rows = try NuvioPage<NuvioAddon>.decode(d, context: "addons").rows
        return rows.enumerated().sorted { ($0.element.sortOrder, $0.offset) < ($1.element.sortOrder, $1.offset) }.map(\.element)
    }

    /// `rpc/sync_pull_collections`: the `collections_json` array as JSON bytes for `NuvioImport.parse`
    /// (array or string form; `[]` when the profile has none).
    public func collections(profile: Int, _ s: NuvioSession) async throws -> Data {
        let d = try await perform(try request(.collections, body: ["p_profile_id": .int(Int64(profile))], session: s),
                                  session: s)
        return try NuvioPayload.collections(d)
    }

    // MARK: Watch progress

    /// Rows the server returns at most for `progress` (reference v1.3: `p_limit` defaults to 200 and is capped at 200
    /// without `p_since_last_watched`; no paging below the newest rows is documented, review 2 finding 6).
    public static let snapshotLimit = 200

    /// `rpc/sync_pull_watch_progress` without `p_since_last_watched`: the newest rows (the server caps at 200),
    /// `last_watched` descending.
    public func progress(profile: Int, _ s: NuvioSession) async throws -> NuvioPage<NuvioProgressRow> {
        let d = try await perform(try request(.progress, body: ["p_profile_id": .int(Int64(profile))], session: s),
                                  session: s)
        return try NuvioPage<NuvioProgressRow>.decode(d, context: "progress")
    }

    /// `rpc/sync_get_watch_progress_delta_cursor`.
    public func progressCursor(profile: Int, _ s: NuvioSession) async throws -> Int {
        let d = try await perform(try request(.progressCursor, body: ["p_profile_id": .int(Int64(profile))], session: s),
                                  session: s)
        return try NuvioPayload.cursor(d)
    }

    /// `rpc/sync_pull_watch_progress_delta`: events after `since`, in the order the server sent them (documented as
    /// `event_id` ascending). `limit` is clamped to 1…1000.
    public func progressDelta(profile: Int, since: Int, limit: Int = 1000,
                              _ s: NuvioSession) async throws -> NuvioPage<NuvioProgressEvent> {
        let d = try await perform(try request(.progressDelta, body: Self.deltaBody(profile, since, limit), session: s),
                                  session: s)
        return try NuvioPage<NuvioProgressEvent>.decode(d, context: "progress_delta")
    }

    /// `rpc/sync_push_watch_progress` (204). An empty list sends nothing.
    public func push(profile: Int, _ entries: [NuvioProgressPush], _ s: NuvioSession) async throws {
        guard !entries.isEmpty else { return }
        let body = try Self.encoder.encode(PushBody(profileID: profile, entries: entries))
        _ = try await perform(try request(.pushProgress, raw: body, session: s), session: s)
    }

    private struct PushBody: Encodable {
        var profileID: Int
        var entries: [NuvioProgressPush]
        enum CodingKeys: String, CodingKey { case profileID = "p_profile_id", entries = "p_entries" }
    }

    // MARK: Watch history

    /// `rpc/sync_pull_watched_items`: one page (1-based), `watched_at` descending. `received < pageSize` = last page.
    public func watched(profile: Int, page: Int, pageSize: Int = 500,
                        _ s: NuvioSession) async throws -> NuvioPage<NuvioWatchedItem> {
        let body: [String: JSONValue] = ["p_profile_id": .int(Int64(profile)), "p_page": .int(Int64(max(1, page))),
                                         "p_page_size": .int(Int64(max(1, pageSize)))]
        let d = try await perform(try request(.watched, body: body, session: s), session: s)
        return try NuvioPage<NuvioWatchedItem>.decode(d, context: "watched")
    }

    /// `rpc/sync_get_watched_items_delta_cursor`.
    public func watchedCursor(profile: Int, _ s: NuvioSession) async throws -> Int {
        let d = try await perform(try request(.watchedCursor, body: ["p_profile_id": .int(Int64(profile))], session: s),
                                  session: s)
        return try NuvioPayload.cursor(d)
    }

    /// `rpc/sync_pull_watched_items_delta`: events after `since`, in server order. `limit` is clamped to 1…1000.
    public func watchedDelta(profile: Int, since: Int, limit: Int = 1000,
                             _ s: NuvioSession) async throws -> NuvioPage<NuvioWatchedEvent> {
        let d = try await perform(try request(.watchedDelta, body: Self.deltaBody(profile, since, limit), session: s),
                                  session: s)
        return try NuvioPage<NuvioWatchedEvent>.decode(d, context: "watched_delta")
    }

    static func deltaBody(_ profile: Int, _ since: Int, _ limit: Int) -> [String: JSONValue] {
        ["p_profile_id": .int(Int64(profile)), "p_since_event_id": .int(Int64(max(0, since))),
         "p_limit": .int(Int64(min(max(1, limit), maxDeltaLimit)))]
    }
}
