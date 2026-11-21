import Foundation
import Testing
@testable import PlayerCore

final class FakeSender: APISending, @unchecked Sendable {
    var sent: [APIRequest] = []
    var replies: [(Int, String)]
    init(_ replies: [(Int, String)]) { self.replies = replies }
    func send(_ r: APIRequest) async throws -> (status: Int, data: Data) {
        sent.append(r)
        let x = replies.isEmpty ? (200, "{}") : replies.removeFirst()
        return (x.0, Data(x.1.utf8))
    }
}

private func body(_ r: APIRequest) -> [String: Any] { (try? JSONSerialization.jsonObject(with: r.body ?? Data())) as? [String: Any] ?? [:] }

@Test func traktDeviceLoginFlow() async throws {
    let http = FakeSender([(200, #"{"device_code":"D","user_code":"ABCD1234","verification_url":"https://trakt.tv/activate","expires_in":600,"interval":5}"#),
                           (400, ""), (429, ""),
                           (200, #"{"access_token":"AT","refresh_token":"RT","expires_in":7776000,"created_at":1000}"#), (410, "")])
    let t = TraktClient(clientID: "CID", clientSecret: "SEC", http: http)
    let code = try await t.deviceCode()
    #expect(code.userCode == "ABCD1234" && code.interval == 5)
    #expect(http.sent[0].headers["trakt-api-key"] == "CID" && http.sent[0].headers["trakt-api-version"] == "2")
    #expect(try await t.poll(code) == .pending)
    #expect(try await t.poll(code) == .slowDown)
    let ok = try await t.poll(code)
    #expect(ok == .success(SyncToken(accessToken: "AT", refreshToken: "RT", expiresAt: Date(timeIntervalSince1970: 1000 + 7776000))))
    #expect(body(http.sent[3])["client_secret"] as? String == "SEC" && body(http.sent[3])["code"] as? String == "D")
    #expect(try await t.poll(code) == .expired)
}

@Test func tokenRefreshWindow() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(!SyncToken(accessToken: "a", expiresAt: now.addingTimeInterval(86400)).needsRefresh(now: now))
    #expect(!SyncToken(accessToken: "a", expiresAt: now.addingTimeInterval(61)).needsRefresh(now: now))
    #expect(SyncToken(accessToken: "a", expiresAt: now.addingTimeInterval(59)).needsRefresh(now: now))
    #expect(SyncToken(accessToken: "a", expiresAt: now.addingTimeInterval(-5)).needsRefresh(now: now))
    #expect(!SyncToken(accessToken: "a").needsRefresh(now: now))
}

@Test func traktScrobbleBodies() async throws {
    let http = FakeSender([])
    let t = TraktClient(clientID: "C", clientSecret: "S", http: http)
    let tok = SyncToken(accessToken: "AT")
    try await t.scrobble(.pause, imdb: "tt9", season: 1, episode: 3, percent: 42.123, token: tok)
    try await t.scrobble(.stop, imdb: "tt1", season: nil, episode: nil, percent: 95, token: tok)
    #expect(http.sent[0].url.path == "/scrobble/pause" && http.sent[0].headers["Authorization"] == "Bearer AT")
    let b0 = body(http.sent[0])
    #expect((b0["episode"] as? [String: Int]) == ["season": 1, "number": 3] && b0["progress"] as? Double == 42.12)
    #expect(((body(http.sent[1])["movie"] as? [String: Any])?["ids"] as? [String: String]) == ["imdb": "tt1"])
}

@Test func traktPlaybackAndWatchlistParsing() async throws {
    let playback = #"""
    [{"progress":37.5,"paused_at":"2026-11-20T20:00:00.000Z","type":"movie","movie":{"title":"Dune","year":2021,"ids":{"imdb":"tt1160419"}}},
     {"progress":10,"paused_at":"2026-11-21T08:00:00.000Z","type":"episode","episode":{"season":2,"number":4},"show":{"title":"Severance","ids":{"imdb":"tt11280740"}}},
     {"progress":5,"type":"movie","movie":{"title":"Ohne IMDb","ids":{"tmdb":1}}}]
    """#
    let http = FakeSender([(200, playback), (200, #"[{"type":"show","show":{"title":"The Bear","year":2022,"ids":{"imdb":"tt14452776"}}}]"#)])
    let t = TraktClient(clientID: "C", clientSecret: "S", http: http)
    let p = try await t.playback(token: SyncToken(accessToken: "A"))
    #expect(p.map(\.id) == ["tt1160419", "tt11280740:2:4"])
    #expect(p[0].fraction == 0.375 && p[1].season == 2 && p[1].item.type == "series")
    #expect(p[0].item.poster == "https://images.metahub.space/poster/medium/tt1160419/img")
    let w = try await t.watchlist(token: SyncToken(accessToken: "A"))
    #expect(w.map(\.id) == ["tt14452776"] && w[0].releaseInfo == "2022")
}

@Test func traktLinks() {
    #expect(TraktLink.source(from: "https://trakt.tv/users/garycrawfordgc/lists/latest-releases?sort=rank,asc")?.kind == .trakt(user: "garycrawfordgc", list: "latest-releases"))
    #expect(TraktLink.source(from: "https://trakt.tv/users/me/watchlist")?.kind == .trakt(user: "me", list: "watchlist"))
    #expect(TraktLink.source(from: "https://trakt.tv/movies/dune") == nil)
    #expect(TraktLink.source(from: "https://www.themoviedb.org/list/1") == nil)
}

@Test func simklPinFlowAndWatchlist() async throws {
    let http = FakeSender([(200, #"{"result":"OK","user_code":"7XQ2","verification_url":"https://simkl.com/pin","expires_in":900,"interval":5}"#),
                           (200, #"{"result":"KO","message":"Authorization pending"}"#),
                           (200, #"{"result":"OK","access_token":"SAT"}"#),
                           (200, #"{"movies":[{"movie":{"title":"A","ids":{"imdb":"tt1"}}}],"shows":[{"show":{"title":"B","ids":{"imdb":"tt2"}}}]}"#)])
    let s = SimklClient(clientID: "SC", http: http)
    let c = try await s.deviceCode()
    #expect(c.userCode == "7XQ2" && http.sent[0].url.absoluteString == "https://api.simkl.com/oauth/pin?client_id=SC")
    #expect(try await s.poll(c) == .pending)
    #expect(try await s.poll(c) == .success(SyncToken(accessToken: "SAT")))
    #expect(http.sent[2].url.path == "/oauth/pin/7XQ2")
    let w = try await s.watchlist(token: SyncToken(accessToken: "SAT"))
    #expect(w.map(\.id) == ["tt1", "tt2"] && w.map(\.type) == ["movie", "series"])
}

@Test func remoteProgressMergesIntoContinueWatching() {
    let old = Date(timeIntervalSince1970: 1000), new = Date(timeIntervalSince1970: 2000)
    let dune = MetaPreview(id: "tt1", type: "movie", name: "Dune")
    let show = MetaPreview(id: "tt2", type: "series", name: "Show")
    var b = ProgressBook()
    b.record(id: "tt1", item: dune, position: 600, duration: 6000, now: old)
    b.merge(remote: [RemoteProgress(id: "tt1", item: dune, fraction: 0.5, updated: new),
                     RemoteProgress(id: "tt2:1:3", item: show, season: 1, episode: 3, fraction: 0.25, updated: new)])
    #expect(b.resumePosition(for: "tt1") == 3000)
    #expect(b.resumePosition(for: "tt2:1:3") == nil && b.resumeFraction(for: "tt2:1:3") == 0.25)
    #expect(Set(b.continueWatching().map(\.id)) == ["tt1", "tt2:1:3"])
    // neuerer lokaler Stand bleibt
    b.record(id: "tt1", item: dune, position: 900, duration: 6000, now: Date(timeIntervalSince1970: 3000))
    b.merge(remote: [RemoteProgress(id: "tt1", item: dune, fraction: 0.1, updated: new)])
    #expect(b.resumePosition(for: "tt1") == 900)
}

@Test func phonePageAcceptsSyncKeys() {
    let page = PhoneInputPage(token: "tok")
    let req = HTTPRequest(method: "POST", path: "/submit", query: ["t": "tok"], headers: [:],
                          body: Data("key_trakt_id=abc&key_simkl_id=xyz".utf8))
    let cmds = page.handle(req, profileName: "P") { Data() }.1
    #expect(cmds == [.setKey(service: "trakt_id", value: "abc"), .setKey(service: "simkl_id", value: "xyz")])
}

@Test func traktListPaths() async throws {
    let http = FakeSender([(200, "[]"), (200, "[]"), (200, "[]")])
    let t = TraktClient(clientID: "C", clientSecret: "S", http: http)
    _ = try await t.list(user: nil, slug: "12345", token: nil)
    _ = try await t.list(user: "gary", slug: "latest", token: nil)
    _ = try await t.list(user: nil, slug: "watchlist", token: SyncToken(accessToken: "A"))
    #expect(http.sent.map(\.url.path) == ["/lists/12345/items", "/users/gary/lists/latest/items", "/users/me/watchlist"])
    #expect(http.sent[0].headers["Authorization"] == nil)
}
