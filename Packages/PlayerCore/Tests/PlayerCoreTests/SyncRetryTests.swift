import Foundation
import Testing
@testable import PlayerCore

/// Antworten mit Kopfzeilen oder Netzfehler.
final class ScriptSender: APISending, @unchecked Sendable {
    enum Reply { case ok(Int, String, [String: String] = [:]), fail }
    struct NetDown: Error {}
    var sent: [APIRequest] = []
    var replies: [Reply]
    init(_ replies: [Reply]) { self.replies = replies }
    func send(_ r: APIRequest) async throws -> (status: Int, data: Data) {
        let x = try await sendFull(r); return (x.status, x.data)
    }
    func sendFull(_ r: APIRequest) async throws -> APIResponse {
        sent.append(r)
        switch replies.isEmpty ? .ok(200, "{}") : replies.removeFirst() {
        case .ok(let s, let b, let h): return APIResponse(status: s, data: Data(b.utf8), headers: h)
        case .fail: throw NetDown()
        }
    }
}

final class SleepLog: @unchecked Sendable {
    var waits: [Double] = []
    var sleep: APISleep { { [self] s in waits.append(s) } }
}

@Test func trakt401RefreshesOnceAndRetries() async throws {
    let http = ScriptSender([.ok(401, ""), .ok(200, "[]")])
    let calls = SleepLog()   // zählt die Erneuerungen
    let t = TraktClient(clientID: "C", clientSecret: "S", http: http, sleep: { _ in },
                        onUnauthorized: { old in calls.waits.append(1); return old.accessToken == "OLD" ? SyncToken(accessToken: "NEW") : nil })
    _ = try await t.watchlist(token: SyncToken(accessToken: "OLD"))
    #expect(calls.waits.count == 1)
    #expect(http.sent.map { $0.headers["Authorization"] } == ["Bearer OLD", "Bearer NEW"])
}

@Test func trakt401TwiceFails() async throws {
    let http = ScriptSender([.ok(401, ""), .ok(401, "")])
    let t = TraktClient(clientID: "C", clientSecret: "S", http: http, sleep: { _ in }, onUnauthorized: { _ in SyncToken(accessToken: "NEW") })
    await #expect(throws: APIError.status(401)) { _ = try await t.playback(token: SyncToken(accessToken: "OLD")) }
    #expect(http.sent.count == 2)
}

@Test func trakt429HonoursRetryAfterCapped() async throws {
    let log = SleepLog()
    let http = ScriptSender([.ok(429, "", ["Retry-After": "3"]), .ok(200, "[]"), .ok(429, "", ["retry-after": "120"]), .ok(429, "")])
    let t = TraktClient(clientID: "C", clientSecret: "S", http: http, sleep: log.sleep)
    _ = try await t.list(user: "u", slug: "l", token: nil)
    await #expect(throws: APIError.status(429)) { _ = try await t.list(user: "u", slug: "l", token: nil) }
    #expect(log.waits == [3, 10])
    #expect(http.sent.count == 4)
    #expect(SyncRetry.retryAfter(nil) == 1 && SyncRetry.retryAfter("x") == 1 && SyncRetry.retryAfter("-4") == 0)
}

@Test func scrobble409IsSuccessAndStopRetriesOnce() async throws {
    let log = SleepLog()
    let http = ScriptSender([.ok(409, ""), .fail, .ok(201, ""), .fail, .fail, .fail])
    let t = TraktClient(clientID: "C", clientSecret: "S", http: http, sleep: log.sleep)
    let tok = SyncToken(accessToken: "A")
    try await t.scrobble(.start, imdb: "tt1", season: nil, episode: nil, percent: 10, token: tok)       // 409
    try await t.scrobble(.stop, imdb: "tt1", season: nil, episode: nil, percent: 95, token: tok)        // Fehler, dann 201
    await #expect(throws: ScriptSender.NetDown.self) {
        try await t.scrobble(.stop, imdb: "tt1", season: nil, episode: nil, percent: 95, token: tok)    // 2× Fehler
    }
    await #expect(throws: ScriptSender.NetDown.self) {
        try await t.scrobble(.pause, imdb: "tt1", season: nil, episode: nil, percent: 50, token: tok)   // keine Wiederholung
    }
    #expect(http.sent.count == 6)
    #expect(log.waits == [1.5, 1.5])
}

@Test func scrobbleOtherStatusThrows() async {
    let http = ScriptSender([.ok(404, "")])
    let s = SimklClient(clientID: "SC", http: http, sleep: { _ in })
    await #expect(throws: APIError.status(404)) {
        try await s.scrobble(.stop, imdb: "tt1", season: nil, episode: nil, percent: 90, token: SyncToken(accessToken: "T"))
    }
    #expect(http.sent.count == 1)
}

@Test func simklSendsAppHeadersOnEveryRequest() async throws {
    let http = ScriptSender([.ok(200, #"{"user_code":"X"}"#), .ok(200, "[]"), .ok(409, "")])
    let s = SimklClient(clientID: "SC", http: http, sleep: { _ in })
    _ = try await s.deviceCode()
    _ = try await s.playback(token: SyncToken(accessToken: "T"))
    try await s.scrobble(.pause, imdb: "tt1", season: 1, episode: 2, percent: 30, token: SyncToken(accessToken: "T"))
    #expect(http.sent.count == 3)
    for r in http.sent {
        #expect(r.headers["simkl-api-key"] == "SC")
        #expect(r.headers["app-name"] == "player")
        #expect(r.headers["app-version"] == SyncAppInfo.version)
        #expect(r.headers["User-Agent"] == "Player/\(SyncAppInfo.version)")
    }
    #expect(http.sent[2].url.path == "/scrobble/pause")
}

// MARK: Scrobble-Regeln

private func actions(_ e: [ScrobbleEvent<String>]) -> [String] { e.map { "\($0.action.rawValue):\($0.item)" } }

@Test func scrobbleNoStartFromEightyPercent() {
    var t = ScrobbleTracker<String>(finishedAt: 0.92)
    #expect(actions(t.progress("A", id: "a", fraction: 0.85)).isEmpty)
    #expect(actions(t.progress("A", id: "a", fraction: 0.86)).isEmpty)
    #expect(actions(t.end(id: "a")) == ["stop:A"])         // ab 80 % zählt das Verlassen als gesehen
    var u = ScrobbleTracker<String>(finishedAt: 0.92)
    _ = u.progress("A", id: "a", fraction: 0.85)
    #expect(actions(u.progress("A", id: "a", fraction: 0.95)) == ["stop:A"])
    #expect(actions(u.progress("A", id: "a", fraction: 0.97)).isEmpty)   // genau einmal
    #expect(actions(u.end(id: "a")).isEmpty)
}

@Test func scrobbleStartPauseResumeStop() {
    var t = ScrobbleTracker<String>(finishedAt: 0.92)
    #expect(actions(t.progress("A", id: "a", fraction: 0.1)) == ["start:A"])
    #expect(actions(t.progress("A", id: "a", fraction: 0.2)).isEmpty)
    #expect(actions(t.pause(id: "a")) == ["pause:A"])
    #expect(actions(t.pause(id: "a")).isEmpty)
    #expect(actions(t.pause(id: "x")).isEmpty)
    #expect(actions(t.progress("A", id: "a", fraction: 0.3)) == ["start:A"])
    #expect(actions(t.progress("B", id: "b", fraction: 0.0)) == ["stop:A", "start:B"])
    #expect(actions(t.progress("B", id: "b", fraction: 0.93)) == ["stop:B"])
    #expect(actions(t.end(id: "b")).isEmpty)
}

@Test func scrobblePausedBelowEightyEndsSilently() {
    var t = ScrobbleTracker<String>(finishedAt: 0.92)
    _ = t.progress("A", id: "a", fraction: 0.4)
    _ = t.pause(id: "a")
    #expect(actions(t.end(id: "a")).isEmpty)
    #expect(actions(t.end(id: "a")).isEmpty)
}
