import Foundation
import PlayerCore

/// Wave L: the per-profile sync queue (PlayerCore `SyncQueue`), kept outside AppModel's stored properties.
@MainActor
final class SyncQueueHolder {
    static let shared = SyncQueueHolder()
    var profileID: UUID?
    var queue = SyncQueue()
    var store: SyncQueueStore?
    /// Processing runs once at a time; a request while it runs schedules one more pass.
    var running = false
    var again = false
}

// Wave L: long-press actions on tiles (watchlist, watched, Continue Watching) and the sync queue behind them.
// - Every action shows at once locally and is queued until Trakt/Simkl confirm it.
// - Pulls (watchlist, playback) are filtered against the queue, so a removed title does not come back meanwhile.
extension AppModel {
    /// Queue of the active profile (loaded on first use and after a profile switch).
    var syncQueue: SyncQueue {
        get { ensureSyncQueue(); return SyncQueueHolder.shared.queue }
        set { ensureSyncQueue(); SyncQueueHolder.shared.queue = newValue }
    }

    private func ensureSyncQueue() {
        let h = SyncQueueHolder.shared
        if h.store == nil { h.store = SyncQueueStore(storage: progressStore.storage) }
        guard h.profileID != profile.id, let store = h.store else { return }
        h.profileID = profile.id
        h.queue = store.load(profile: profile.id)
        let gone = h.queue.prune()
        if !h.queue.changes.isEmpty || gone > 0 {
            RemoteLog.info("sync", "Warteschlange: \(h.queue.pendingCount) ausstehend, \(h.queue.changes.count) gemerkt, \(gone) abgelaufen")
        }
    }

    private func saveSyncQueue() {
        ensureSyncQueue()
        do { try SyncQueueHolder.shared.store?.save(SyncQueueHolder.shared.queue, profile: profile.id) }
        catch { RemoteLog.error("sync", "Warteschlange nicht gespeichert: \(error)") }
    }

    /// A service with a watchlist is connected.
    var watchlistAvailable: Bool { Self.syncServices.contains(where: isConnected) }

    /// Watchlist state for the menu: last pull plus pending local changes.
    func isOnWatchlist(_ m: MetaPreview) -> Bool {
        let imdb = cachedIMDbID(for: m)
        let remote = cache[CatalogSource.watchlist.id]?.contains { $0.id == m.id || (imdb != nil && $0.id == imdb) } ?? false
        let q = syncQueue, byTile = q.isOnWatchlist(m.id, remote: remote)
        guard let imdb, imdb != m.id, byTile == remote else { return byTile }
        return q.isOnWatchlist(imdb, remote: remote)
    }

    /// Menu entries for a tile. The watchlist entry needs a title the services can address: an IMDb ID, or a TMDB
    /// ID that resolves to one (addon-only IDs would stay local forever, so they get no watchlist entry).
    func tileMenu(for m: MetaPreview, inContinueRow: Bool) -> [TileMenuAction] {
        let addressable = m.id.hasPrefix("tt") || m.id.hasPrefix("tmdb:") || cachedIMDbID(for: m) != nil
        return TileMenuAction.menu(watchlistAvailable: watchlistAvailable && addressable, onWatchlist: isOnWatchlist(m),
                            watched: progress.isTileWatched(m.id) || cachedIMDbID(for: m).map(progress.isTileWatched) == true,
                            inContinueRow: inContinueRow)
    }

    /// Pulled list with the queue applied (watchlist only; other sources pass unchanged).
    func applySyncQueue(_ source: CatalogSource, _ items: [MetaPreview]) -> [MetaPreview] {
        guard case .watchlist = source.kind else { return items }
        return syncQueue.applyWatchlist(items)
    }

    /// Pulled playback with the queue applied (removed/marked titles stay as the user left them).
    func applySyncQueue(_ remote: [RemoteProgress]) -> [RemoteProgress] {
        let out = syncQueue.filterRemote(remote)
        if out.count < remote.count { RemoteLog.info("sync", "\(remote.count - out.count) abgeholte Einträge durch Warteschlange zurückgehalten") }
        return out
    }

    /// Runs a tile action: local effect first, then queue it for the services.
    func perform(_ action: TileMenuAction, on m: MetaPreview) async {
        guard let kind = action.change else { return }
        let profileID = profile.id
        let imdb = await imdbID(for: m)
        guard profile.id == profileID else { return }
        let series = ContentKind.isEpisodic(type: m.type)
        // Canonical ID, as playback records it for Continue Watching and history: IMDb first, else the tile's own.
        var canonical = m
        canonical.id = imdb ?? m.id
        switch kind {
        case .markWatched:
            editProgress { b in
                if canonical.id != m.id { _ = b.removeFromContinueWatching(itemID: m.id) }
                b.markWatched(item: canonical, series: series)
            }
        case .markUnwatched:
            // A catalog tile may carry a TMDB ID while playback recorded the IMDb ID: clear both.
            editProgress { b in
                b.markUnwatched(itemID: m.id)
                if let imdb, imdb != m.id { b.markUnwatched(itemID: imdb) }
            }
        case .removeFromContinue:
            editProgress { b in
                _ = b.removeFromContinueWatching(itemID: canonical.id)
                if canonical.id != m.id { _ = b.removeFromContinueWatching(itemID: m.id) }
            }
        case .watchlistAdd, .watchlistRemove: break
        }
        let services = Set(Self.syncServices.filter(isConnected))
        var q = syncQueue
        q.record(kind, item: m, imdb: imdb, series: series, services: services)
        syncQueue = q
        saveSyncQueue()
        for s in [CatalogSource.watchlist, CatalogSource.continueWatching] { catalogRevisions[s.id, default: 0] += 1 }
        RemoteLog.info("sync", "Kachel: \(action.title) · \(m.name) (\(imdb ?? "ohne IMDb"))"
                       + (services.isEmpty || imdb == nil ? " · nur lokal" : " · ausstehend: \(services.sorted().joined(separator: ", "))"))
        await processSyncQueue()
    }

    /// Sends what is pending, service by service, oldest first. A retry stops that service until the next pass.
    func processSyncQueue() async {
        let h = SyncQueueHolder.shared
        if h.running { h.again = true; return }
        h.running = true
        defer { h.running = false }
        repeat {
            h.again = false
            await processSyncQueueOnce()
        } while h.again
    }

    private func processSyncQueueOnce() async {
        let profileID = profile.id
        var q = syncQueue
        q.prune()
        for s in Self.syncServices where !isConnected(s) { q.drop(service: s) }
        syncQueue = q
        for s in Self.syncServices where isConnected(s) {
            let due = syncQueue.due(for: s)
            guard !due.isEmpty, let t = await token(s) else { continue }
            for c in due {
                let r: SyncWriteResult
                if s == "trakt", let trakt { r = await trakt.apply(c, token: t) }
                else if s == "simkl", let simkl { r = await simkl.apply(c, token: t) }
                else { continue }
                guard profile.id == profileID else { return }   // everything confirmed so far is saved already
                let name = "\(s == "trakt" ? "Trakt" : "Simkl") \(c.kind.logName) · \(c.item.name)"
                switch r {
                case .confirmed:
                    RemoteLog.info("sync", "\(name): bestätigt")
                    syncQueue.confirm(c.id, service: s, createdAt: c.createdAt)
                case .skipped(let why):
                    RemoteLog.info("sync", "\(name): übersprungen – \(why)")
                    syncQueue.confirm(c.id, service: s, createdAt: c.createdAt)
                case .unconfirmed(let why):
                    RemoteLog.info("sync", "\(why) · \(c.item.name): bleibt lokal bis zu 30 Tage gemerkt")
                    syncQueue.confirm(c.id, service: s, createdAt: c.createdAt, held: true)
                case .rejected(let status):
                    RemoteLog.error("sync", "\(name): vom Dienst abgelehnt (HTTP \(status)), wird nicht erneut gesendet")
                    syncQueue.confirm(c.id, service: s, createdAt: c.createdAt)
                case .retry:
                    RemoteLog.info("sync", "\(name): nicht erreicht, später erneut")
                }
                if r == .retry { break }
                saveSyncQueue()
            }
        }
        saveSyncQueue()
    }

    /// A watchlist pull that started at `startedAt` is in the catalog cache: confirmed entries older than it can go.
    func noteWatchlistPull(startedAt: Date) {
        var q = syncQueue
        guard q.notePull(watchlistStartedAt: startedAt) > 0 else { return }
        syncQueue = q
        saveSyncQueue()
    }

    /// Profile deleted: its queue file goes too.
    func removeSyncQueue(profile id: UUID) {
        let h = SyncQueueHolder.shared
        if h.store == nil { h.store = SyncQueueStore(storage: progressStore.storage) }
        h.store?.remove(profile: id)
        if h.profileID == id { h.profileID = nil; h.queue = SyncQueue() }
    }
}

extension Route {
    /// Wave L: the title a tile stands for (nil for folders, collections, people).
    var tileItem: MetaPreview? {
        switch self {
        case .detail(let m): m
        case .streams(let r): r.item
        case .folder, .collection, .person: nil
        }
    }
}
