import Foundation

/// Wave L: request bodies and sending of the queued changes (watchlist, watched, Continue Watching).
enum SyncWriteBody {
    /// `{"movies":[{"ids":{"imdb":…}}]}` or `"shows"`; `extra` goes into the title object (Simkl list target).
    static func titles(imdb: String, series: Bool, extra: [String: Any] = [:]) -> [String: Any] {
        var o: [String: Any] = ["ids": ["imdb": imdb]]
        for (k, v) in extra { o[k] = v }
        return [series ? "shows" : "movies": [o]]
    }

    /// ISO-8601 UTC with milliseconds, as Trakt and Simkl write `watched_at`.
    static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: d)
    }

    /// "tt…" → (imdb, nil, nil); "tt…:season:episode" → (imdb, season, episode).
    static func splitID(_ id: String) -> (imdb: String, season: Int?, episode: Int?) {
        let p = id.split(separator: ":").map(String.init)
        if p.count == 3, let s = Int(p[1]), let e = Int(p[2]) { return (p[0], s, e) }
        return (p.first ?? id, nil, nil)
    }

    /// History entry for a finished playback, with `watched_at`.
    static func history(id: String, watchedAt: Date) -> [String: Any] {
        let (imdb, season, episode) = splitID(id)
        let at = iso(watchedAt)
        guard let season, let episode else { return ["movies": [["ids": ["imdb": imdb], "watched_at": at]]] }
        return ["shows": [["ids": ["imdb": imdb],
                           "seasons": [["number": season, "episodes": [["number": episode, "watched_at": at]]]]]]]
    }

    /// Does a `GET /sync/history/{type}/{id}` answer hold this entry (same episode, watched within a minute)?
    static func historyContains(_ data: Data, season: Int?, episode: Int?, at: Date) -> Bool {
        let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
        return arr.contains { o in
            guard let w = (o["watched_at"] as? String).flatMap(TraktClient.date), abs(w.timeIntervalSince(at)) < 60 else { return false }
            guard let season, let episode else { return true }
            let ep = o["episode"] as? [String: Any]
            return ep?["season"] as? Int == season && ep?["number"] as? Int == episode
        }
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
            case .markWatched:
                // A resend first checks the history: the earlier send may have arrived without its answer.
                if (c.attempts ?? 0) > 0, try await inHistory(imdb: imdb, series: c.series, season: nil, episode: nil, at: c.createdAt, token: token) {
                    return .confirmed
                }
                let watched = SyncWriteBody.titles(imdb: imdb, series: c.series, extra: ["watched_at": SyncWriteBody.iso(c.createdAt)])
                return try await post("/sync/history", watched, token)
            case .markUnwatched: return try await post("/sync/history/remove", body, token)
            case .removeFromContinue:
                return try await deletePlayback(c, remote: try await playback(token: token), service: "Trakt") { id in
                    try await perform(request("DELETE", "/sync/playback/\(id)", token: token), token: token).status
                }
            }
        } catch { return .retry }
    }

    /// Sends a queued action (a failed scrobble stop becomes a history entry). Never throws.
    /// `.resolveThen` is handled by the app (lookup) and `.change` is never due.
    public func apply(_ e: SyncQueue.Entry, token: SyncToken) async -> SyncWriteResult {
        guard case .scrobbleStop(let id, _, let at) = e.action else { return .skipped("nichts zu senden") }
        let (imdb, season, episode) = SyncWriteBody.splitID(id)
        do {
            if e.attempts > 0, try await inHistory(imdb: imdb, series: season != nil, season: season, episode: episode, at: at, token: token) {
                return .confirmed
            }
            return try await post("/sync/history", SyncWriteBody.history(id: id, watchedAt: at), token)
        } catch { return .retry }
    }

    /// `GET /sync/history/{movies|shows}/{imdb}` around `at`. A failed check counts as "not there" (send again):
    /// a duplicate is better than a lost entry.
    func inHistory(imdb: String, series: Bool, season: Int?, episode: Int?, at: Date, token: SyncToken) async throws -> Bool {
        let window = "?start_at=\(SyncWriteBody.iso(at.addingTimeInterval(-60)))&end_at=\(SyncWriteBody.iso(at.addingTimeInterval(60)))"
        let r = try await perform(request("GET", "/sync/history/\(series ? "shows" : "movies")/\(imdb)\(window)", token: token), token: token)
        guard (200..<300).contains(r.status) else { return false }
        return SyncWriteBody.historyContains(r.data, season: season, episode: episode, at: at)
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
        // Not `json(_:)`: Simkl answers a type without items with a literal `null` (or an empty body). Any valid JSON
        // that is no object means "on no list"; HTTP errors and broken JSON still throw (retry).
        let res = try await http.sendRespectingRateLimit(request("GET", path, token: token), sleep: sleep)
        guard (200..<300).contains(res.status) else { throw APIError.status(res.status) }
        guard !res.data.isEmpty else { return nil }
        let o = try JSONSerialization.jsonObject(with: res.data, options: [.fragmentsAllowed]) as? [String: Any] ?? [:]
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
            case .markWatched:
                let watched = SyncWriteBody.titles(imdb: imdb, series: c.series, extra: ["watched_at": SyncWriteBody.iso(c.createdAt)])
                return try await post("/sync/history", watched, token)
            case .removeFromContinue:
                return try await deletePlayback(c, remote: try await playback(token: token), service: "Simkl") { id in
                    try await http.sendRespectingRateLimit(request("DELETE", "/sync/playback/\(id)", token: token), sleep: sleep).status
                }
            }
        } catch { return .retry }
    }

    /// Sends a queued action (a failed scrobble stop becomes a history entry). Never throws.
    /// Simkl keeps one watched state per title or episode, so a resend cannot double it: no history check.
    public func apply(_ e: SyncQueue.Entry, token: SyncToken) async -> SyncWriteResult {
        guard case .scrobbleStop(let id, _, let at) = e.action else { return .skipped("nichts zu senden") }
        do { return try await post("/sync/history", SyncWriteBody.history(id: id, watchedAt: at), token) }
        catch { return .retry }
    }

    private func post(_ path: String, _ body: [String: Any], _ token: SyncToken) async throws -> SyncWriteResult {
        let r = try await http.sendRespectingRateLimit(request("POST", path, token: token, json: body), sleep: sleep)
        return SyncWriteResult.classify(status: r.status)
    }
}
