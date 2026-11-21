import UIKit
import PlayerCore

/// Katalog-Cache mit Ablauf (24 h): abgelaufene Reihen zeigen sofort den alten Stand,
/// die Erneuerung läuft im Hintergrund; danach laden nur die betroffenen Reihen neu.
extension AppModel {
    /// Teil der `.task(id:)` einer Reihe: ändert sich nach einer Erneuerung dieser Quelle
    /// oder beim Zurückkehren in die App, wenn Kataloge abgelaufen sind.
    func catalogStamp(_ c: RowContent) -> String {
        guard case .list(let s) = c else { return "" }
        return "|\(catalogWake).\(catalogRevisions[s.id, default: 0])"
    }

    /// Höchstens eine Erneuerung je Quelle gleichzeitig; nach Fehlschlag frühestens nach 10 min erneut.
    func refreshCatalogIfStale(_ s: CatalogSource) {
        guard cache.needsRefresh(s.id), catalogRefreshing.insert(s.id).inserted else { return }
        let before = cache.storedAt(s.id)
        Task { @MainActor in
            let out = await items(s, refresh: true)
            catalogRefreshing.remove(s.id)
            guard let at = cache.storedAt(s.id) else { return }   // inzwischen geleert (Profilwechsel …)
            guard at != before else {
                cache.markFailed(s.id)
                RemoteLog.info("katalog", "\(s.title): Erneuerung ohne neuen Stand (Fehler oder leer), alter Stand bleibt")
                return
            }
            catalogRevisions[s.id, default: 0] += 1
            RemoteLog.info("katalog", "\(s.title): im Hintergrund erneuert (\(out.count) Einträge)")
        }
    }

    /// Apple TV beendet Apps selten: beim Zurückkehren abgelaufene Reihen anstoßen (sie rufen `items` erneut auf).
    func observeCatalogWake() {
        _ = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.cache.keysNeedingRefresh().isEmpty else { return }
                self.catalogWake += 1
            }
        }
    }
}
