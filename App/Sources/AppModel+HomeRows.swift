import Foundation
import Combine
import PlayerCore

/// Ergebnis einer Katalog-Ladung (Welle F-f): Einträge, Fehlschlag (leer wegen Fehler), Stand aus dem Cache.
struct CatalogLoad: Sendable {
    var items: [MetaPreview]
    var failed = false
    var fromCache = false
}

// Welle F-f: Laden der Startseiten-Reihen.
// - Eine Ladung je Quelle: Reihe, Hero und Vorladen warten auf dieselbe Abfrage (keine Doppelten).
// - Die Abfrage läuft als eigene Aufgabe weiter, wenn die Reihe aus dem Bild scrollt (LazyVStack baut sie ab);
//   bisher brach das die Abfrage ab (-999) und sie begann beim nächsten Zeigen von vorn.
// - Vorladen in der Reihenfolge der Startseite mit höchstens `HomeRowPreload.limit` gleichzeitig, damit Reihen
//   unter dem sichtbaren Bereich schon fertig sind, wenn man hinscrollt. Keine Reihe wartet auf eine andere.
extension AppModel {
    /// Einträge einer Reihe; misst und loggt die Dauer jeder echten Abfrage („Reihe geladen <titel> <ms> ms“).
    func homeRowItems(_ s: CatalogSource) async -> CatalogLoad {
        if case .continueWatching = s.kind { return await loadItems(s) }   // lokal, sofort
        let key = "\(profile.id.uuidString)|\(s.id)"
        if let running = homeRowLoads[key] { return await running.value }
        // Build 7 review (L4): failed within 30 s and nothing stored: no new request (a row's retry forgets it first).
        if cache[s.id] == nil, recentLoadFailures.isRecent(s.id) { return CatalogLoad(items: [], failed: true) }
        let t0 = Date()
        let task = Task { @MainActor in await self.loadItems(s) }
        homeRowLoads[key] = task
        let r = await task.value
        if homeRowLoads[key] == task { homeRowLoads[key] = nil }
        if r.failed { recentLoadFailures.mark(s.id) } else { recentLoadFailures.forget(s.id) }
        homeRowLoadDone.send((id: s.id, load: r))
        if !r.fromCache {
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            RemoteLog.info("home", "Reihe geladen \(s.title) \(ms) ms" + (r.failed ? " (Fehler)" : " (\(r.items.count) Einträge)"))
        }
        return r
    }

    /// Alle Listen der Startseite vorladen (oben zuerst, gleichzeitig höchstens `HomeRowPreload.limit`).
    /// Nur, was noch gar keinen Stand hat: Reihen aus dem Plattencache erneuern sich weiter erst beim ersten Zeigen
    /// (sonst stieße das Vorladen beim Start alle Erneuerungen auf einmal an).
    func preloadHomeRows(_ rows: [HomeRow]) async {
        await awaitCatalogSnapshot()
        let sources = HomeRowPreload.sources(rows).filter { $0.kind == .upcoming || cache[$0.id] == nil }
        guard !sources.isEmpty else { return }
        let t0 = Date()
        await withTaskGroup(of: Void.self) { group in
            var running = 0
            for s in sources {
                if Task.isCancelled { break }
                if running >= HomeRowPreload.limit { await group.next(); running -= 1 }
                group.addTask { _ = await self.homeRowItems(s) }
                running += 1
            }
        }
        RemoteLog.info("home", "Vorladen: \(sources.count) Reihen in \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
    }

    /// Build 7 (folder): a folder tile rested in focus (home rows: after the hero's rest, folder pages after
    /// `FocusRest.prefetchMilliseconds`): its first two rows start loading now, through the shared `homeRowItems`, so the
    /// page joins the running loads. Device test b6-1: AIOMetadata catalogs took 3–11 s on the first open, and the
    /// tile rested 1–5 s before the click. Cached sources (memory or disk) and recent failures are skipped.
    func prefetchFolder(_ f: Folder) {
        let key = profile.id.uuidString
        if let last = folderPrefetches[f.id]?.at, Date().timeIntervalSince(last) < 60 { return }
        // Review b7 M1: many row loads running already (home preload …): no warm-up on top.
        guard FolderPage.mayPrefetch(runningLoads: homeRowLoads.count) else { return }
        Task { @MainActor in
            await awaitCatalogSnapshot()
            guard key == profile.id.uuidString else { return }
            guard FolderPage.mayPrefetch(runningLoads: homeRowLoads.count) else { return }
            // Build 8: a studio / streaming tile opens the TMDB grid: warm its first pages (start filter first; the
            // grid shows the cached page at once). Review: an unknown studio runs its company search first, then
            // warms what the page will show (TMDB page, addon grid or row page sources).
            let hasTMDB = tmdb != nil
            let lookup: (String) -> MediaCollection? = { self.collection($0) }
            var page = BrandPage.resolve(f, collection: lookup, searched: { CompanySearchStore.shared.lookup($0) }, tmdb: hasTMDB)
            if case .search(let query, let searchKey) = page {
                let answer: CompanySearchCache.Lookup? = await CompanySearchStore.shared.search(query, key: searchKey, tmdb: tmdb)
                guard key == profile.id.uuidString else { return }
                if let answer {
                    page = BrandPage.afterSearch(f, collection: lookup, answer: answer)
                } else {
                    page = BrandPage.withoutSearch(f, collection: lookup)
                }
            }
            var candidates = f.sources
            if case .grid(let g) = page { candidates = BrandPage.warmSources(g) }
            let picked = FolderPage.prefetchSources(candidates, isCached: { id in
                self.cache[id] != nil || self.homeRowLoads["\(key)|\(id)"] != nil || self.recentLoadFailures.isRecent(id)
            })
            guard !picked.isEmpty else { return }
            folderPrefetches[f.id] = (count: picked.count, at: Date())
            RemoteLog.info("katalog", "Ordner \(f.title): \(picked.count) \(picked.count == 1 ? "Quelle" : "Quellen") beim Fokus vorgeladen")
            for s in picked { Task { @MainActor in _ = await self.homeRowItems(s) } }
        }
    }
}
