import Foundation

/// Wave L: request bodies and sending of the queued changes (watchlist, watched, Continue Watching).
enum SyncWriteBody {
    /// `{"movies":[{"ids":{"imdb":…}}]}` or `"shows"`; `extra` goes into the title object (Simkl list target).
    static func titles(imdb: String, series: Bool, extra: [String: Any] = [:]) -> [String: Any] {
        var o: [String: Any] = ["ids": ["imdb": imdb]]
        for (k, v) in extra { o[k] = v }
        return [series ? "shows" : "movies": [o]]
    }

    /// Playback entry ID as number or string.
    static func playbackID(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let s = v as? String { return Int(s) }
        return nil
    }
}

/// Deletes the matching playback entries. Nothing to delete (none found, or none with an ID) is not a confirmation.
func deletePlayback(_ c: SyncChange, remote: [RemoteProgress], service: String,
                    delete: (Int) async throws -> Int) async throws -> SyncWriteResult {
    let plan = SyncQueue.playbackPlan(for: c, in: remote)
    for id in plan.ids {
        let res = SyncWriteResult.classify(status: try await delete(id), deleting: true)
        if res != .confirmed { return res }
    }
    if plan.withoutID > 0 {
        return .unconfirmed("\(service): \(plan.withoutID) Fortschritt-Eintrag/Einträge ohne ID, nicht gelöscht")
    }
    if plan.ids.isEmpty { return .unconfirmed("\(service): kein Fortschritt-Eintrag gefunden, nichts gelöscht") }
    return .confirmed
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
                return try await deletePlayback(c, remote: try await playback(token: token), service: "Trakt") { id in
                    try await perform(request("DELETE", "/sync/playback/\(id)", token: token), token: token).status
                }
            }
        } catch { return .retry }
    }

    private func post(_ path: String, _ body: [String: Any], _ token: SyncToken) async throws -> SyncWriteResult {
        let r = try await perform(request("POST", path, token: token, json: body), token: token)
        return SyncWriteResult.classify(status: r.status)
    }
}

extension SimklClient {
    /// Simkl list of a title ("plantowatch", "watching", "completed", …), nil = on no list.
    /// Reads `/sync/all-items/movies` (or `/shows` and `/anime`: Simkl keeps anime as its own type) fresh, because
    /// Simkl list membership is exclusive.
    func listStatus(imdb: String, series: Bool, token: SyncToken) async throws -> String? {
        for type in series ? ["shows", "anime"] : ["movies"] {
            if let s = try await listStatus(imdb: imdb, path: "/sync/all-items/\(type)", token: token) { return s }
        }
        return nil
    }

    private func listStatus(imdb: String, path: String, token: SyncToken) async throws -> String? {
        let o = try await json(request("GET", path, token: token)) as? [String: Any] ?? [:]
        for key in ["movies", "shows", "anime"] {
            for e in o[key] as? [[String: Any]] ?? [] {
                let t = (e["movie"] ?? e["show"]) as? [String: Any]
                if (t?["ids"] as? [String: Any])?["imdb"] as? String == imdb { return e["status"] as? String ?? "?" }
            }
        }
        return nil
    }

    /// Sends one queued change. Never throws: network errors count as `.retry`.
    /// The watchlist never uses `/sync/history/remove` (it would also delete watched episodes): Simkl has no call
    /// that only takes a title off "plan to watch", so a removal stays local (held for 30 days, so the next pull
    /// does not bring it back onto a Simkl-backed watchlist row). An add only goes out when the
    /// title is on no Simkl list, because adding moves it out of "watching"/"completed".
    public func apply(_ c: SyncChange, token: SyncToken) async -> SyncWriteResult {
        guard let imdb = c.imdb else { return .confirmed }
        let plain = SyncWriteBody.titles(imdb: imdb, series: c.series)
        do {
            switch c.kind {
            case .watchlistAdd:
                if let status = try await listStatus(imdb: imdb, series: c.series, token: token) {
                    return .skipped("Simkl: Merkliste nicht geändert (Titel steht in „\(status)“)")
                }
                return try await post("/sync/add-to-list", SyncWriteBody.titles(imdb: imdb, series: c.series, extra: ["to": "plantowatch"]), token)
            case .watchlistRemove:
                return .unconfirmed("Merkliste: Simkl nur lokal entfernt (Simkl kann das nicht, ohne den Verlauf zu löschen)")
            case .markUnwatched: return try await post("/sync/history/remove", plain, token)
            case .markWatched: return try await post("/sync/history", plain, token)
            case .removeFromContinue:
                return try await deletePlayback(c, remote: try await playback(token: token), service: "Simkl") { id in
                    try await http.sendRespectingRateLimit(request("DELETE", "/sync/playback/\(id)", token: token), sleep: sleep).status
                }
            }
        } catch { return .retry }
    }

    private func post(_ path: String, _ body: [String: Any], _ token: SyncToken) async throws -> SyncWriteResult {
        let r = try await http.sendRespectingRateLimit(request("POST", path, token: token, json: body), sleep: sleep)
        return SyncWriteResult.classify(status: r.status)
    }
}
