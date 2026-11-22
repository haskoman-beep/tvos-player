import Foundation
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
        let t0 = Date()
        let task = Task { @MainActor in await self.loadItems(s) }
        homeRowLoads[key] = task
        let r = await task.value
        if homeRowLoads[key] == task { homeRowLoads[key] = nil }
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
}
