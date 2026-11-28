import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import PlayerCore

// Nuvio account sync, T3. No request leaves the process (`FakeSender`); fixtures hold invented values only.

private func text(_ name: String) throws -> String { String(decoding: try fixture(name), as: UTF8.self) }
private func jsonBody(_ r: APIRequest) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: r.body ?? Data())) as? [String: Any] ?? [:]
}
private func keys(_ r: APIRequest) -> Set<String> { Set(jsonBody(r).keys) }
private let session = NuvioSession(accessToken: "AT1", refreshToken: "RT1", expiresAt: nil,
                                   userID: "00000000-0000-4000-8000-000000000001")

private final class NuvioCallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    var all: [Double] { lock.withLock { values } }
    func note(_ s: Double) { lock.withLock { values.append(s) } }
}

private struct FailingSender: APISending {
    func send(_ r: APIRequest) async throws -> (status: Int, data: Data) { throw URLError(.notConnectedToInternet) }
}

private func client(_ http: FakeSender, sleeps: NuvioCallLog = NuvioCallLog(),
                    onUnauthorized: (@Sendable (NuvioSession) async -> NuvioRenewal)? = nil) -> NuvioClient {
    NuvioClient(http: http, sleep: { sleeps.note($0) }, onUnauthorized: onUnauthorized)
}

// MARK: Auth

@Test func nuvioSignInRequestAndSession() async throws {
    let http = FakeSender([(200, try text("nuvio-token.json"))])
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let s = try await client(http).signIn(email: "user@example.org", password: "pw-geheim", now: now)
    #expect(s == NuvioSession(accessToken: "AT1", refreshToken: "RT1", expiresAt: now.addingTimeInterval(3600),
                              userID: "00000000-0000-4000-8000-000000000001"))
    let r = try #require(http.sent.first)
    #expect(r.method == "POST")
    #expect(r.url.host == "api.nuvio.tv" && r.url.path == "/auth/v1/token" && r.url.query == "grant_type=password")
    #expect(r.headers["apikey"] == "sb_publishable_1Clq8rlTVACkdcZuqr6_AD__xUUC_EN")
    #expect(r.headers["Content-Type"] == "application/json" && r.headers["User-Agent"] == SyncAppInfo.userAgent)
    #expect(r.headers["Authorization"] == nil)
    #expect(keys(r) == ["email", "password"])
    #expect(jsonBody(r)["email"] as? String == "user@example.org" && jsonBody(r)["password"] as? String == "pw-geheim")
    #expect(!r.url.absoluteString.contains("pw-geheim") && !r.url.absoluteString.contains("example.org"))
}

@Test func nuvioSignInDefaultsAndMissingFields() async throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let noExpiry = FakeSender([(200, #"{"access_token":"AT1","refresh_token":"RT1","user":{"id":"u1"}}"#)])
    #expect(try await client(noExpiry).signIn(email: "a", password: "b", now: now).expiresAt == now.addingTimeInterval(3600))
    let asString = FakeSender([(200, #"{"access_token":"AT1","refresh_token":"RT1","expires_in":"7200","user":{"id":"u1"}}"#)])
    #expect(try await client(asString).signIn(email: "a", password: "b", now: now).expiresAt == now.addingTimeInterval(7200))
    let noUser = FakeSender([(200, #"{"access_token":"AT1","refresh_token":"RT1"}"#)])
    await #expect(throws: NuvioError.decoding("user")) { try await client(noUser).signIn(email: "a", password: "b") }
    let noToken = FakeSender([(200, #"{"refresh_token":"RT1","user":{"id":"u1"}}"#)])
    await #expect(throws: NuvioError.decoding("access_token")) { try await client(noToken).signIn(email: "a", password: "b") }
}

@Test func nuvioSignInRefusalCarriesNoSecret() async throws {
    let body = #"{"code":400,"error_code":"invalid_credentials","msg":"Invalid login credentials for user@example.org"}"#
    let http = FakeSender([(400, body)])
    do {
        _ = try await client(http).signIn(email: "user@example.org", password: "pw-geheim")
        Issue.record("no error")
    } catch let e as NuvioError {
        #expect(e == .status(400, code: "invalid_credentials"))
        for t in [String(describing: e), String(reflecting: e), "\(e)", e.localizedDescription] {
            #expect(!t.contains("pw-geheim") && !t.contains("user@example.org") && !t.contains("Invalid login"))
        }
    }
    // The documented PostgREST body: only `code`, never `message`.
    let other = FakeSender([(400, try text("nuvio-error.json"))])
    await #expect(throws: NuvioError.status(400, code: "PGRST202")) { try await client(other).signIn(email: "a", password: "b") }
    // A code that is no short identifier is dropped.
    let odd = FakeSender([(422, #"{"code":"user@example.org has no access"}"#)])
    await #expect(throws: NuvioError.status(422, code: nil)) { try await client(odd).signIn(email: "a", password: "b") }
    // 401 on the sign-in is a refusal, not an expired session.
    let unauthorized = FakeSender([(401, "")])
    await #expect(throws: NuvioError.status(401, code: nil)) { try await client(unauthorized).signIn(email: "a", password: "b") }
}

@Test func nuvioRefreshReplacesBothTokens() async throws {
    let http = FakeSender([(200, try text("nuvio-refresh.json"))])
    let now = Date(timeIntervalSince1970: 2_000)
    let s = try await client(http).refresh(session, now: now)
    #expect(s == NuvioSession(accessToken: "AT2", refreshToken: "RT2", expiresAt: now.addingTimeInterval(3600),
                              userID: session.userID))
    let r = try #require(http.sent.first)
    #expect(r.method == "POST" && r.url.path == "/auth/v1/token" && r.url.query == "grant_type=refresh_token")
    #expect(keys(r) == ["refresh_token"] && jsonBody(r)["refresh_token"] as? String == "RT1")
    #expect(r.headers["Authorization"] == nil && r.headers["apikey"] == NuvioClient.publishableKey)
}

@Test func nuvioRefreshKeepsWhatTheAnswerLacks() async throws {
    let http = FakeSender([(200, #"{"access_token":"AT3","user":{"id":"someone-else"}}"#)])
    let now = Date(timeIntervalSince1970: 3_000)
    let s = try await client(http).refresh(session, now: now)
    #expect(s.accessToken == "AT3" && s.refreshToken == "RT1" && s.userID == session.userID)
    #expect(s.expiresAt == now.addingTimeInterval(3600))
}

@Test func nuvioRefreshOutcomes() async throws {
    for status in [400, 401, 403] {
        await #expect(throws: NuvioError.signedOut) { try await client(FakeSender([(status, "")])).refresh(session) }
    }
    await #expect(throws: NuvioError.status(500, code: nil)) { try await client(FakeSender([(500, "")])).refresh(session) }
    await #expect(throws: NuvioError.rateLimited) {
        try await client(FakeSender([(429, ""), (429, "")])).refresh(session)
    }
    await #expect(throws: NuvioError.offline) { try await NuvioClient(http: FailingSender(), sleep: { _ in }).refresh(session) }
    var empty = session; empty.refreshToken = ""
    let none = FakeSender([])
    await #expect(throws: NuvioError.signedOut) { try await client(none).refresh(empty) }
    #expect(none.sent.isEmpty)
}

@Test func nuvioSignOut() async throws {
    let http = FakeSender([(204, "")])
    try await client(http).signOut(session)
    let r = try #require(http.sent.first)
    #expect(r.method == "POST" && r.url.path == "/auth/v1/logout" && r.url.query == nil)
    #expect(r.headers["Authorization"] == "Bearer AT1" && r.headers["apikey"] == NuvioClient.publishableKey && r.body == nil)
    // 401: no refresh is tried for a sign-out.
    let refreshed = NuvioCallLog()
    let gone = FakeSender([(401, "")])
    await #expect(throws: NuvioError.signedOut) {
        try await client(gone, onUnauthorized: { _ in refreshed.note(1); return .refused }).signOut(session)
    }
    #expect(refreshed.all.isEmpty && gone.sent.count == 1)
}

// MARK: Calls and bodies

@Test func nuvioRPCRequests() async throws {
    let http = FakeSender([
        (200, try text("nuvio-profiles.json")), (200, try text("nuvio-addons.json")), (200, try text("nuvio-collections.json")),
        (200, try text("nuvio-progress.json")), (200, "12347"), (200, try text("nuvio-progress-delta.json")), (204, ""),
        (200, try text("nuvio-watched.json")), (200, "98767"), (200, try text("nuvio-watched-delta.json")),
    ])
    let c = client(http)
    _ = try await c.profiles(session)
    _ = try await c.addons(profile: 2, session)
    _ = try await c.collections(profile: 2, session)
    _ = try await c.progress(profile: 2, session)
    #expect(try await c.progressCursor(profile: 2, session) == 12347)
    _ = try await c.progressDelta(profile: 2, since: 12340, session)
    try await c.push(profile: 2, [NuvioProgressPush(contentID: "tt1", contentType: "movie", videoID: "tt1",
                                                    position: 1, duration: 2, lastWatched: 3)], session)
    _ = try await c.watched(profile: 2, page: 3, session)
    #expect(try await c.watchedCursor(profile: 2, session) == 98767)
    _ = try await c.watchedDelta(profile: 2, since: 98760, limit: 5000, session)

    let expected: [(String, String, String?, Set<String>)] = [
        ("POST", "/rest/v1/rpc/sync_pull_profiles", nil, []),
        ("GET", "/rest/v1/addons", "select=*&profile_id=eq.2&order=sort_order", []),
        ("POST", "/rest/v1/rpc/sync_pull_collections", nil, ["p_profile_id"]),
        ("POST", "/rest/v1/rpc/sync_pull_watch_progress", nil, ["p_profile_id"]),
        ("POST", "/rest/v1/rpc/sync_get_watch_progress_delta_cursor", nil, ["p_profile_id"]),
        ("POST", "/rest/v1/rpc/sync_pull_watch_progress_delta", nil, ["p_profile_id", "p_since_event_id", "p_limit"]),
        ("POST", "/rest/v1/rpc/sync_push_watch_progress", nil, ["p_profile_id", "p_entries"]),
        ("POST", "/rest/v1/rpc/sync_pull_watched_items", nil, ["p_profile_id", "p_page", "p_page_size"]),
        ("POST", "/rest/v1/rpc/sync_get_watched_items_delta_cursor", nil, ["p_profile_id"]),
        ("POST", "/rest/v1/rpc/sync_pull_watched_items_delta", nil, ["p_profile_id", "p_since_event_id", "p_limit"]),
    ]
    #expect(http.sent.count == expected.count)
    for (r, e) in zip(http.sent, expected) {
        #expect(r.method == e.0 && r.url.host == "api.nuvio.tv" && r.url.path == e.1 && r.url.query == e.2, "\(e.1)")
        #expect(r.headers["Authorization"] == "Bearer AT1" && r.headers["apikey"] == NuvioClient.publishableKey, "\(e.1)")
        #expect(r.headers["User-Agent"] == SyncAppInfo.userAgent)
        if e.3.isEmpty {
            #expect(r.body == nil && r.headers["Content-Type"] == nil, "\(e.1)")
        } else {
            #expect(keys(r) == e.3 && r.headers["Content-Type"] == "application/json", "\(e.1)")
            #expect(jsonBody(r)["p_profile_id"] as? Int == 2, "\(e.1)")
        }
    }
    #expect(jsonBody(http.sent[5])["p_since_event_id"] as? Int == 12340 && jsonBody(http.sent[5])["p_limit"] as? Int == 1000)
    #expect(jsonBody(http.sent[7])["p_page"] as? Int == 3 && jsonBody(http.sent[7])["p_page_size"] as? Int == 500)
    #expect(jsonBody(http.sent[9])["p_since_event_id"] as? Int == 98760 && jsonBody(http.sent[9])["p_limit"] as? Int == 1000)
}

@Test func nuvioPushBody() async throws {
    let http = FakeSender([(204, "")])
    let film = NuvioProgressPush(contentID: "tmdb:550", contentType: "movie", videoID: "tmdb:550",
                                 position: 3_600_000, duration: 7_920_000, lastWatched: 1_711_600_000_000)
    let episode = NuvioProgressPush(contentID: "tmdb:1396", contentType: "series", videoID: "tmdb:1396:1:1", season: 1,
                                    episode: 1, position: 1_800_000, duration: 3_480_000, lastWatched: 1_711_600_000_001)
    try await client(http).push(profile: 1, [film, episode], session)
    let r = try #require(http.sent.first)
    let text = String(decoding: r.body ?? Data(), as: UTF8.self)
    #expect(!text.contains("progress_key") && !text.contains("."))   // integers only, no key
    let entries = try #require(jsonBody(r)["p_entries"] as? [[String: Any]])
    #expect(entries.count == 2)
    #expect(Set(entries[0].keys) == ["content_id", "content_type", "video_id", "position", "duration", "last_watched"])
    #expect(entries[0]["position"] as? Int == 3_600_000 && entries[0]["last_watched"] as? Int == 1_711_600_000_000)
    #expect(Set(entries[1].keys) == ["content_id", "content_type", "video_id", "season", "episode", "position", "duration",
                                     "last_watched"])
    #expect(entries[1]["season"] as? Int == 1 && entries[1]["video_id"] as? String == "tmdb:1396:1:1")
    // Nothing to push: no request.
    let none = FakeSender([])
    try await client(none).push(profile: 1, [], session)
    #expect(none.sent.isEmpty)
    // The push entry round-trips (the outbox stores it).
    let back = try JSONDecoder().decode(NuvioProgressPush.self, from: try JSONEncoder().encode(episode))
    #expect(back == episode)
}

// MARK: 401 and 429

@Test func nuvioUnauthorizedRefreshesOnceAndResends() async throws {
    let http = FakeSender([(401, ""), (200, "7")])
    let calls = NuvioCallLog()
    let fresh = NuvioSession(accessToken: "AT2", refreshToken: "RT2", expiresAt: nil, userID: session.userID)
    let c = client(http, onUnauthorized: { old in
        calls.note(1)
        return old.accessToken == "AT1" ? .renewed(fresh) : .refused
    })
    #expect(try await c.progressCursor(profile: 1, session) == 7)
    #expect(calls.all.count == 1 && http.sent.count == 2)
    #expect(http.sent[0].headers["Authorization"] == "Bearer AT1" && http.sent[1].headers["Authorization"] == "Bearer AT2")
    #expect(http.sent[0].body == http.sent[1].body && http.sent[0].url == http.sent[1].url)
    // Still 401 after the resend: signed out, no second refresh.
    let twice = FakeSender([(401, ""), (401, "")])
    let calls2 = NuvioCallLog()
    await #expect(throws: NuvioError.signedOut) {
        try await client(twice, onUnauthorized: { _ in calls2.note(1); return .renewed(fresh) }).profiles(session)
    }
    #expect(calls2.all.count == 1 && twice.sent.count == 2)
    // Without a hook, or when it has nothing: signed out after one request.
    let bare = FakeSender([(401, "")])
    await #expect(throws: NuvioError.signedOut) { try await client(bare).profiles(session) }
    #expect(bare.sent.count == 1)
    let nothing = FakeSender([(401, "")])
    await #expect(throws: NuvioError.signedOut) { try await client(nothing, onUnauthorized: { _ in .refused }).profiles(session) }
    #expect(nothing.sent.count == 1)
}

@Test func nuvioRateLimit() async throws {
    let sleeps = NuvioCallLog()
    let busy = FakeSender([(429, ""), (429, "")])
    await #expect(throws: NuvioError.rateLimited) { try await client(busy, sleeps: sleeps).progressCursor(profile: 1, session) }
    #expect(sleeps.all.count == 1 && busy.sent.count == 2)
    let later = FakeSender([(429, ""), (200, "5")])
    let sleeps2 = NuvioCallLog()
    #expect(try await client(later, sleeps: sleeps2).progressCursor(profile: 1, session) == 5)
    #expect(sleeps2.all.count == 1)
}

@Test func nuvioStatusAndTransportErrors() async throws {
    await #expect(throws: NuvioError.status(403, code: "42501")) {
        try await client(FakeSender([(403, #"{"code":"42501","message":"permission denied for user@example.org"}"#)])).profiles(session)
    }
    await #expect(throws: NuvioError.status(503, code: nil)) { try await client(FakeSender([(503, "<html>")])).profiles(session) }
    await #expect(throws: NuvioError.offline) { try await NuvioClient(http: FailingSender(), sleep: { _ in }).profiles(session) }
    await #expect(throws: NuvioError.decoding("profiles")) { try await client(FakeSender([(200, "{}")])).profiles(session) }
    // Descriptions name the status and the code only.
    #expect(NuvioError.status(403, code: "42501").description == "Nuvio: HTTP 403 (42501)")
    #expect(NuvioError.rateLimited.description.contains("429"))
}

// MARK: Decoding

@Test func nuvioProfilesAndAddonsDecode() async throws {
    let http = FakeSender([(200, try text("nuvio-profiles.json")), (200, try text("nuvio-addons.json"))])
    let c = client(http)
    let p = try await c.profiles(session)
    #expect(p.map(\.profileIndex) == [1, 2] && p.map(\.name) == ["Main", "Kids"])
    #expect(p[1].usesPrimaryAddons && p[1].pinEnabled && !p[0].pinEnabled && p[0].avatarColorHex == "#1E88E5")
    #expect(!String(describing: p[0]).contains("0000") && !String(describing: p[0]).contains("Main"))
    let a = try await c.addons(profile: 1, session)
    #expect(a.map(\.sortOrder) == [0, 1] && a.map(\.name) == ["Example Catalog", "Example Metadata"])
    #expect(a[0].enabled && !a[1].enabled && a[0].url.hasSuffix("/manifest.json"))
    #expect(!String(describing: a[0]).contains("SECRETKEY") && String(describing: a[0]).contains("catalog.example.com"))
}

@Test func nuvioPageSkipsMalformedRows() async throws {
    let page = #"""
    [{"content_id":"tt1","content_type":"movie","video_id":"tt1","position":"1000","duration":2000,"last_watched":3},
     {"content_id":"tt2","content_type":"movie","video_id":"tt2","position":"viel","duration":2000,"last_watched":3},
     17,
     {"content_id":"tt3","content_type":"series","season":"2","episode":4,"position":10.0,"duration":20,"last_watched":30,"neu":true}]
    """#
    let http = FakeSender([(200, page), (200, #"[{"profile_index":1,"name":"A"},{"name":"ohne Index"}]"#),
                           (200, #"[{"url":"https://a.example/manifest.json"},{"name":"ohne url"}]"#)])
    let c = client(http)
    let p = try await c.progress(profile: 1, session)
    #expect(p.rows.map(\.contentID) == ["tt1", "tt3"])
    #expect(p.received == 4 && p.skipped == 2)
    #expect(p.rows[0].position == 1000 && p.rows[1].season == 2 && p.rows[1].position == 10)
    #expect(p.rows[0].progressKey == "tt1" && p.rows[1].progressKey == "tt3_s2e4")   // computed when missing
    #expect(try await c.profiles(session).map(\.profileIndex) == [1])
    let a = try await c.addons(profile: 1, session)
    #expect(a.count == 1 && a[0].enabled && a[0].sortOrder == 0)
}

@Test func nuvioSnapshotFixturesDecode() async throws {
    let http = FakeSender([(200, try text("nuvio-progress.json")), (200, try text("nuvio-watched.json"))])
    let c = client(http)
    let p = try await c.progress(profile: 1, session)
    #expect(p.skipped == 0 && p.rows.count == 2)
    #expect(p.rows[0] == NuvioProgressRow(id: "00000000-0000-4000-8000-0000000000c1",
                                          userID: "00000000-0000-4000-8000-000000000001", profileID: 1,
                                          contentID: "tmdb:550", contentType: "movie", videoID: "tmdb:550",
                                          progressKey: "tmdb:550", position: 3_600_000, duration: 7_920_000,
                                          lastWatched: 1_711_600_000_000))
    #expect(p.rows[1].season == 1 && p.rows[1].episode == 1 && p.rows[1].progressKey == "tmdb:1396_s1e1")
    let w = try await c.watched(profile: 1, page: 1, session)
    #expect(w.received == 2 && w.rows.map(\.contentID) == ["tmdb:550", "tt0903747"])
    #expect(w.rows[0].title == "Fight Club" && w.rows[0].season == nil && w.rows[1].episode == 2)
    #expect(w.rows[0].watchedAt == 1_711_600_000_000)
    // Rows round-trip through their own encoding (for state that keeps them).
    #expect(try JSONDecoder().decode(NuvioProgressRow.self, from: try JSONEncoder().encode(p.rows[1])) == p.rows[1])
    #expect(try JSONDecoder().decode(NuvioWatchedItem.self, from: try JSONEncoder().encode(w.rows[1])) == w.rows[1])
}

@Test func nuvioDeltaEventsDecode() async throws {
    let http = FakeSender([(200, try text("nuvio-progress-delta.json")), (200, try text("nuvio-watched-delta.json"))])
    let c = client(http)
    let p = try await c.progressDelta(profile: 1, since: 12345, session)
    #expect(p.rows.map(\.eventID) == [12346, 12347] && p.lastEventID == 12347)
    #expect(p.rows[0].operation == .upsert && p.rows[0].progressKey == "tmdb:550" && p.rows[0].row?.position == 3_600_000)
    #expect(p.rows[1].operation == .delete && p.rows[1].progressKey == "tmdb:1396_s1e1" && p.rows[1].row?.season == 1)
    let w = try await c.watchedDelta(profile: 1, since: 98765, session)
    #expect(w.rows.map(\.operation) == [.upsert, .delete] && w.lastEventID == 98767)
    #expect(w.rows[1].item.contentID == "tmdb:1396" && w.rows[1].item.episode == 1)
}

@Test func nuvioDeltaEdgeRows() async throws {
    let progress = #"""
    [{"event_id":5,"operation":"delete","progress_key":"tmdb:1"},
     {"event_id":"6","operation":"upsert","progress_key":"tmdb:2"},
     {"event_id":9,"operation":"truncate","progress_key":"tmdb:3"},
     {"event_id":7,"operation":"delete","content_id":"tmdb:4","season":1,"episode":2},
     {"operation":"delete","progress_key":"tmdb:5"}]
    """#
    let watched = #"""
    [{"event_id":3,"operation":"delete","content_id":"tt9","season":null,"episode":null},
     {"event_id":4,"operation":"upsert","content_id":"tt9"},
     {"event_id":2,"operation":"delete"}]
    """#
    let http = FakeSender([(200, progress), (200, watched)])
    let c = client(http)
    let p = try await c.progressDelta(profile: 1, since: 0, session)
    // A delete needs a key only; an upsert needs its row; unknown operations and rows without event_id are skipped.
    #expect(p.rows.map(\.eventID) == [5, 7] && p.rows.map(\.progressKey) == ["tmdb:1", "tmdb:4_s1e2"])
    #expect(p.rows[0].row == nil && p.received == 5 && p.skipped == 3)
    #expect(p.lastEventID == 9)   // the cursor may move past rows that will never read
    let w = try await c.watchedDelta(profile: 1, since: 0, session)
    #expect(w.rows.map(\.eventID) == [3] && w.rows[0].item.watchedAt == 0 && w.lastEventID == 4 && w.skipped == 2)
}

@Test func nuvioCursorForms() async throws {
    for (body, want) in [("42", 42), (#""42""#, 42), ("null", 0), (#"[{"sync_get_watch_progress_delta_cursor":42}]"#, 42),
                         (#"{"cursor":42}"#, 42), ("[42]", 42), ("[]", 0), ("", 0), ("42.0", 42), ("-3", 0)] {
        let http = FakeSender([(200, body)])
        #expect(try await client(http).progressCursor(profile: 1, session) == want, "\(body)")
    }
    for body in [#"{"a":1,"b":2}"#, #""viele""#, "true", "[1,2]"] {
        await #expect(throws: NuvioError.decoding("cursor")) {
            try await client(FakeSender([(200, body)])).watchedCursor(profile: 1, session)
        }
    }
}

@Test func nuvioCollectionsForms() async throws {
    let http = FakeSender([(200, try text("nuvio-collections.json")), (200, try text("nuvio-collections-string.json")),
                           (200, "[]"), (200, #"[{"profile_id":1,"collections_json":null}]"#),
                           (200, #"[{"profile_id":1,"collections_json":"kaputt"}]"#)])
    let c = client(http)
    let a = try await c.collections(profile: 1, session)
    let b = try await c.collections(profile: 1, session)
    #expect(a == b)
    let list = try #require(try JSONSerialization.jsonObject(with: a) as? [[String: Any]])
    #expect(list.count == 1 && list[0]["title"] as? String == "Weekend Picks")
    #expect(String(decoding: a, as: UTF8.self).contains("🚀"))
    #expect(try await c.collections(profile: 1, session) == Data("[]".utf8))
    #expect(try await c.collections(profile: 1, session) == Data("[]".utf8))
    await #expect(throws: NuvioError.decoding("collections_json")) { try await c.collections(profile: 1, session) }
    // The bytes feed the existing import.
    let r = try NuvioImport.parse(a)
    #expect(r.collections.map(\.title) == ["Weekend Picks"] && r.collections[0].folders.map(\.title) == ["Sci-Fi"])
}

// MARK: Guard rails

@Test func nuvioClientCanBuildOnlyAllowedCalls() throws {
    let forbidden = ["sync_push_addons", "sync_push_collections", "sync_push_profiles", "sync_push_library",
                     "sync_delete_profile_data", "signup", "settings", "sync_delete", "sync_push_watched_items"]
    let c = NuvioClient(http: FakeSender([]))
    var built: [String] = []
    for e in NuvioEndpoint.allCases {
        built.append(e.path + "?" + (e.query(profile: 1) ?? ""))
        built.append(try c.request(e, profile: 3, session: session).url.absoluteString)
    }
    #expect(NuvioEndpoint.allCases.count == 13)
    for u in built { for f in forbidden { #expect(!u.contains(f), "\(u)") } }
    #expect(Set(NuvioEndpoint.allCases.map(\.path)).count == 12)   // sign-in and refresh share the token path
}


// MARK: Review 2 (findings 9, 13)

@Test func nuvioRefreshThatCannotRunIsOfflineNotSignedOut() async throws {
    let http = FakeSender([(401, "")])
    await #expect(throws: NuvioError.offline) {
        try await client(http, onUnauthorized: { _ in .unavailable }).progressCursor(profile: 1, session)
    }
    #expect(http.sent.count == 1)
    // `renewal` maps refresh failures: 5xx and 429 are unavailable, 400 is refused, 200 renewed.
    let down = client(FakeSender([(503, "")]))
    #expect(await down.renewal(session, now: Date(timeIntervalSince1970: 1_750_000_000)) == .unavailable)
    let busy = client(FakeSender([(429, ""), (429, "")]))
    #expect(await busy.renewal(session, now: Date(timeIntervalSince1970: 1_750_000_000)) == .unavailable)
    let refused = client(FakeSender([(400, #"{"error":"invalid_grant"}"#)]))
    #expect(await refused.renewal(session, now: Date(timeIntervalSince1970: 1_750_000_000)) == .refused)
    let ok = client(FakeSender([(200, #"{"access_token":"AT9","refresh_token":"RT9","expires_in":3600,"user":{"id":"\#(session.userID)"}}"#)]))
    if case .renewed(let s) = await ok.renewal(session, now: Date(timeIntervalSince1970: 1_750_000_000)) {
        #expect(s.accessToken == "AT9")
    } else { Issue.record("expected renewed") }
}

@Test func nuvioRedirectIsAnAnswerNotASecondRequest() async throws {
    // A 307 on sign-in comes back as `.status(307)`; the body is sent exactly once.
    let http = FakeSender([(307, "")])
    await #expect(throws: NuvioError.status(307, code: nil)) { _ = try await client(http).signIn(email: "a@b.example", password: "pw-invented") }
    #expect(http.sent.count == 1)
    // The Nuvio session delegate refuses the redirect (called through the protocol, as URLSession does).
    let delegate: URLSessionTaskDelegate = RedirectRefusal()
    let task = URLSession(configuration: .ephemeral).dataTask(with: URL(string: "https://example.org/a")!)
    let response = HTTPURLResponse(url: URL(string: "https://example.org/a")!, statusCode: 307, httpVersion: nil,
                                   headerFields: ["Location": "https://example.net/b"])!
    let next = URLRequest(url: URL(string: "https://example.net/b")!)
    #if canImport(FoundationNetworking)
    let box = NuvioCallLog()
    // Linux protocols have no optional requirements: a near-miss signature would silently run the default (which
    // follows the redirect), and this call would see a request.
    delegate.urlSession(URLSession.shared, task: task, willPerformHTTPRedirection: response, newRequest: next) { r in
        box.note(r == nil ? 0 : 1)
    }
    #expect(box.all == [0])
    #else
    // Calling the optional async requirement through the existential crashes the Swift 6.2.4 compiler (SILGen), so
    // the answer is taken from the concrete type, and the Objective-C selector URLSession looks for proves the
    // requirement is really implemented (a near-miss signature would not respond to it).
    let r = await RedirectRefusal().urlSession(URLSession.shared, task: task, willPerformHTTPRedirection: response,
                                               newRequest: next)
    #expect(r == nil)
    let wanted = NSSelectorFromString("URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:")
    #expect((delegate as AnyObject).responds(to: wanted))
    #endif
    #expect(URLSessionByteTransport.nuvio.session.delegate is RedirectRefusal)
}
