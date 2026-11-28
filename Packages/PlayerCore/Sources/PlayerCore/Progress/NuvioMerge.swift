import Foundation

// Nuvio account sync, T5: merge and delete rules for pulled account rows (plan section 1.6). Separate from the
// fraction-based `merge(remote:)` of Trakt/Simkl: Nuvio delivers absolute position and duration.

extension ProgressBook {
    /// Takes pulled entries into the book. Per id the newer time wins (remote `last_watched` against the local
    /// `updated`); a tie keeps local, so merging the same input twice changes nothing. Otherwise the rules of
    /// `record(...)` apply: a watched entry is reopened only by a session past 120 s and 5 %, the next-episode hint
    /// stays until the episode ran past 120 s, an episode older than a whole-series "watched" marker stays out and a
    /// newer one replaces the marker. Finished: `watched`, or position / duration ≥ `finishedAt` (0.92). Local
    /// title, artwork and remembered sources stay; the pulled entry only fills what is missing. A remote length of 0
    /// (unknown) keeps the local length. Bad numbers are repaired like stored ones (`ProgressNumbers`).
    /// Callers filter the input with `NuvioState.filterPulled` first (tombstones, addendum A4). Nothing here is ever
    /// queued for a push: pulled entries never go back to the account.
    /// Returns how many entries changed.
    @discardableResult
    public mutating func merge(nuvio pulled: [NuvioProgressEntry]) -> Int {
        var changed = 0
        for var r in pulled {
            r.updated = ProgressNumbers.date(r.updated)
            r.duration = ProgressNumbers.storedDuration(r.duration)
            r.position = ProgressNumbers.storedPosition(r.position, duration: r.duration)
            let old = entries[r.id]
            let remoteMS = NuvioMapping.epochMS(r.updated)
            if let l = old {
                let localMS = NuvioMapping.epochMS(l.updated)
                if localMS > remoteMS { continue }
                if localMS == remoteMS, !(r.watched && !l.finished) { continue }
            }
            if r.id != r.item.id, let m = entries[r.item.id], m.season == nil, m.finished,
               NuvioMapping.epochMS(m.updated) >= remoteMS { continue }
            let duration = r.duration > 0 ? r.duration : ProgressNumbers.storedDuration(old?.duration ?? 0)
            let position = duration > 0 ? min(r.position, duration) : r.position
            let done = r.watched || Self.nuvioFinished(position: position, duration: duration)
            let ranLong = position > Self.markerSeconds
            if let l = old, l.finished, !done, !(ranLong && position > Self.unfinishFraction * duration) { continue }
            let keepNextUp = !done && old?.nextUp == true && !ranLong
            clearSeriesMarker(itemID: r.item.id, episodeID: r.id, updated: r.updated)
            let item = old.map { Self.filled($0.item, from: r.item) } ?? r.item
            let known = duration > 0 || position > 0 || done
            let e = WatchProgress(id: r.id, item: item, season: r.season, episode: r.episode,
                                  position: done ? 0 : position, duration: duration, updated: r.updated,
                                  finished: done, nextUp: keepNextUp ? true : nil,
                                  remoteFraction: known ? nil : ProgressNumbers.storedFraction(old?.remoteFraction))
            if e != old { entries[r.id] = e; changed += 1 }
        }
        return changed
    }

    /// Shortest length (seconds) with which a pulled row can count as finished: the server records completion only
    /// for `duration >= 60000` ms (reference v1.3, push section), so a 1 ms / 1 ms row is no finished title.
    public static let nuvioMinFinishSeconds = 60.0

    /// The 92 % rule for pulled rows, with the server's length floor.
    static func nuvioFinished(position: Double, duration: Double) -> Bool {
        duration.isFinite && duration >= nuvioMinFinishSeconds && position / duration >= finishedAt
    }

    /// Moves every entry of one title from its provisional id `from` (`tmdb:N`) to `to` (`tt…`) once the IMDb id is
    /// known (review 2, finding 2). Only entries of the kind move (`series`: episodes and series markers; else the
    /// film), so a film and a series sharing a TMDB number stay apart. When `to` already has an entry at the key, the
    /// newer `updated` (whole ms) wins and a tie keeps the target; a finished entry is reopened only by a session past
    /// `markerSeconds` and `unfinishFraction` (the rule of `record`). The target's title and artwork stay, gaps are
    /// filled from the moved entry. `drop` says which moved entries a tombstone blocks. Idempotent: a second call finds nothing to
    /// move. Returns how many entries changed.
    @discardableResult
    public mutating func rekeyNuvio(from: String, to: String, series: Bool,
                                    drop: (WatchProgress) -> Bool = { _ in false }) -> Int {
        guard from != to else { return 0 }
        let moving = entries.values.filter { e in
            e.item.id == from && (e.season != nil || ContentKind.isEpisodic(type: e.item.type)) == series
        }.sorted { $0.id < $1.id }
        var changed = 0
        for old in moving {
            entries[old.id] = nil
            changed += 1
            var e = old
            e.id = NuvioMapping.localProgressID(itemID: to, season: old.season, episode: old.episode)
            e.item.id = to
            if e.item.poster == nil || e.item.poster?.isEmpty == true {
                e.item.poster = NuvioMapping.meta(to, series: series, name: nil).poster
            }
            if e.item.background == nil || e.item.background?.isEmpty == true {
                e.item.background = NuvioMapping.meta(to, series: series, name: nil).background
            }
            if drop(e) { continue }
            guard let t = entries[e.id] else { entries[e.id] = e; continue }
            let movedMS = NuvioMapping.epochMS(e.updated), targetMS = NuvioMapping.epochMS(t.updated)
            var winner = movedMS > targetMS ? e : t
            if winner == e, t.finished, !e.finished,
               !(e.position > Self.markerSeconds && e.position > Self.unfinishFraction * e.duration) { winner = t }
            // The target's title and artwork stay (it is the user's own entry); the moved one only fills gaps.
            winner.item = Self.filled(t.item, from: e.item)
            entries[e.id] = winner
        }
        return changed
    }

    /// Delete events of a delta pull, as local progress ids (`tt…` or `tt…:S:E`).
    /// - `deletedProgress`: an unfinished entry goes (that entry only, not the whole series). A finished entry stays:
    ///   clients plausibly drop the progress row once a title is watched, which must not un-watch it.
    /// - `watchedRemoved`: a finished entry goes (it is unwatched); unfinished progress stays.
    /// Both only when the id is not in `protected` (a pending push for it) and the local `updated` is older than
    /// `before` (the last pull); otherwise the local play is newer and wins. Returns how many entries went.
    @discardableResult
    public mutating func applyNuvio(deletedProgress ids: [String], watchedRemoved: [String],
                                    protected: Set<String>, before: Date) -> Int {
        var removed = 0
        func drop(_ id: String, finished: Bool) {
            guard !protected.contains(id), let e = entries[id], e.finished == finished,
                  ProgressNumbers.date(e.updated) < before else { return }
            entries[id] = nil
            removed += 1
        }
        for id in ids { drop(id, finished: false) }
        for id in watchedRemoved { drop(id, finished: true) }
        return removed
    }
}
