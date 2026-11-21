import Foundation
import PlayerCore

/// Kalender-Daten im Speicher (Spec §7a.3: 6 h gültig), je Profil und Sprache.
@MainActor
final class UpcomingCache {
    static let shared = UpcomingCache()
    static let lifetime: TimeInterval = 6 * 3600
    /// Nach Fehlern (offline, TMDB gestört) nur kurz behalten, dann neu versuchen.
    static let failedLifetime: TimeInterval = 5 * 60

    struct Entry { var at: Date; var ttl: TimeInterval; var ids: [String]; var episodes: [UpcomingEpisode] }
    var entries: [String: Entry] = [:]
    var running: [String: Task<[UpcomingEpisode], Never>] = [:]
    /// Serien-ID ("tt…") → TMDB-ID; bleibt über die 6 h hinaus.
    var tmdbIDs: [String: Int] = [:]
}

extension AppModel {
    /// Kommende Folgen der Serien aus Weiterschauen und Merkliste (höchstens 50), höchstens 4 Abrufe gleichzeitig.
    func upcoming() async -> [UpcomingEpisode] {
        guard let tmdb else { return [] }
        let cache = UpcomingCache.shared
        let airtimes = profile.sources.tvmazeAirtimes
        let key = "\(profile.id.uuidString):\(tmdb.language):\(airtimes)"
        let watchlist = await items(.watchlist)
        let ids = Upcoming.seriesIDs(continueWatching: progress.continueWatching(limit: 200), watchlist: watchlist)
        if let e = cache.entries[key], Date().timeIntervalSince(e.at) < e.ttl, Set(e.ids) == Set(ids) {
            return e.episodes
        }
        if let t = cache.running[key] { return await t.value }

        let known = cache.tmdbIDs
        let cal = Upcoming.localCalendar
        let from = Upcoming.firstDay(today: Date(), calendar: cal), through = Upcoming.lastDay(today: Date(), calendar: cal)
        let task = Task { @MainActor () -> [UpcomingEpisode] in
            var out: [UpcomingEpisode] = []
            var failed = 0
            await withTaskGroup(of: (String, Int?, [UpcomingEpisode]?).self) { g in
                var queue = ids.makeIterator()
                for _ in 0..<4 {
                    if let id = queue.next() { g.addTask { await AppModel.fetchUpcoming(id, known: known[id], tmdb: tmdb, from: from, through: through, airtimes: airtimes) } }
                }
                while let r = await g.next() {
                    let (id, n, eps) = r
                    if let n { cache.tmdbIDs[id] = n }
                    if let eps { out += eps } else { failed += 1 }
                    if let id = queue.next() { g.addTask { await AppModel.fetchUpcoming(id, known: known[id], tmdb: tmdb, from: from, through: through, airtimes: airtimes) } }
                }
            }
            RemoteLog.info("kalender", "\(ids.count) Serien · \(out.count) Folgen · \(failed) Fehler")
            cache.entries[key] = .init(at: Date(), ttl: failed == 0 ? UpcomingCache.lifetime : UpcomingCache.failedLifetime,
                                       ids: ids, episodes: out)
            cache.running[key] = nil
            return out
        }
        cache.running[key] = task
        return await task.value
    }

    /// Eine Serie: TMDB-ID ermitteln (falls nötig), dann die Folgen holen.
    /// nil-Folgen = Abruf fehlgeschlagen (wird nicht 6 h gecacht); [] = Serie bei TMDB nicht gefunden.
    nonisolated static func fetchUpcoming(_ id: String, known: Int?, tmdb: TMDBClient,
                                          from: String, through: String, airtimes: Bool = false) async -> (String, Int?, [UpcomingEpisode]?) {
        var n = known
        if n == nil {
            if id.hasPrefix("tmdb:") { n = Int(id.dropFirst(5)) }
            else if id.hasPrefix("tt") {
                do { n = try await tmdb.tmdbID(imdb: id, series: true) } catch { return (id, nil, nil) }
            }
        }
        guard let n else { return (id, nil, []) }
        guard let eps = try? await tmdb.nextEpisodes(tmdbID: n, from: from, through: through) else { return (id, n, nil) }
        return (id, n, await withAirtimes(eps.map { var e = $0; e.seriesID = id; return e }, id: id, enabled: airtimes))
    }

    /// Reihe „Heute neu“: heute erscheinende Folgen als Serienkacheln, die Folge steht in `releaseInfo` („S2 F5“).
    func upcomingToday() async -> [MetaPreview] {
        let today = Upcoming.today(await upcoming(), today: Date(), calendar: Upcoming.localCalendar)
        var order: [String] = []
        var bySeries: [String: [UpcomingEpisode]] = [:]
        for e in today {
            if bySeries[e.seriesID] == nil { order.append(e.seriesID) }
            bySeries[e.seriesID, default: []].append(e)
        }
        return order.compactMap { id in
            guard let eps = bySeries[id], let first = eps.first else { return nil }
            let label = eps.count > 1 ? "\(first.episodeLabel) +\(eps.count - 1)" : first.episodeLabel
            return MetaPreview(id: id, type: "series", name: first.seriesName, poster: first.poster,
                               background: first.still ?? first.background, releaseInfo: label)
        }
    }
}

extension UpcomingEpisode {
    /// Ziel für die Detailseite der Serie.
    var seriesPreview: MetaPreview {
        MetaPreview(id: seriesID, type: "series", name: seriesName, poster: poster, background: background)
    }
}
