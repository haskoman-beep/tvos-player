import Foundation

/// Wave L: request bodies and sending of the queued changes (watchlist, watched, Continue Watching).
enum SyncWriteBody {
    /// `{"movies":[{"ids":{"imdb":…}}]}` or `"shows"`; `extra` goes into the title object (Simkl list target).
    static func titles(imdb: String, series: Bool, extra: [String: Any] = [:]) -> [String: Any] {
        var o: [String: Any] = ["ids": ["imdb": imdb]]
        for (k, v) in extra { o[k] = v }
        return [series ? "shows" : "movies": [o]]
    }
}

extension TraktClient {
    /// Sends one queued change. Never throws: network errors count as `.retry`.
    public func apply(_ c: SyncChange, token: SyncToken) async -> SyncWriteResult {
        guard let imdb = c.imdb else { return .confirmed }
        let body = SyncWriteBody.titles(imdb: imdb, series: c.series)
        do {
            switch c.kind {
            case .watchlistAdd: return try await post("/sync/watchlist", body, token)
            case .watchlistRemove: return try await post("/sync/watchlist/remove", body, token)
            case .markWatched: return try await post("/sync/history", body, token)
            case .markUnwatched: return try await post("/sync/history/remove", body, token)
            case .removeFromContinue:
                let ids = SyncQueue.playbackIDs(for: c, in: try await playback(token: token))
                for id in ids {
                    let r = try await perform(request("DELETE", "/sync/playback/\(id)", token: token), token: token)
                    let res = SyncWriteResult.classify(status: r.status, deleting: true)
                    if res != .confirmed { return res }
                }
                return .confirmed
            }
        } catch { return .retry }
    }

    private func post(_ path: String, _ body: [String: Any], _ token: SyncToken) async throws -> SyncWriteResult {
        let r = try await perform(request("POST", path, token: token, json: body), token: token)
        return SyncWriteResult.classify(status: r.status)
    }
}

extension SimklClient {
    /// Sends one queued change. Never throws: network errors count as `.retry`.
    /// Simkl has no separate "remove from plan to watch": removing from history takes the title off its lists.
    public func apply(_ c: SyncChange, token: SyncToken) async -> SyncWriteResult {
        guard let imdb = c.imdb else { return .confirmed }
        let plain = SyncWriteBody.titles(imdb: imdb, series: c.series)
        do {
            switch c.kind {
            case .watchlistAdd:
                return try await post("/sync/add-to-list", SyncWriteBody.titles(imdb: imdb, series: c.series, extra: ["to": "plantowatch"]), token)
            case .watchlistRemove, .markUnwatched: return try await post("/sync/history/remove", plain, token)
            case .markWatched: return try await post("/sync/history", plain, token)
            case .removeFromContinue:
                let ids = SyncQueue.playbackIDs(for: c, in: try await playback(token: token))
                for id in ids {
                    let r = try await http.sendRespectingRateLimit(request("DELETE", "/sync/playback/\(id)", token: token), sleep: sleep)
                    let res = SyncWriteResult.classify(status: r.status, deleting: true)
                    if res != .confirmed { return res }
                }
                return .confirmed
            }
        } catch { return .retry }
    }

    private func post(_ path: String, _ body: [String: Any], _ token: SyncToken) async throws -> SyncWriteResult {
        let r = try await http.sendRespectingRateLimit(request("POST", path, token: token, json: body), sleep: sleep)
        return SyncWriteResult.classify(status: r.status)
    }
}
