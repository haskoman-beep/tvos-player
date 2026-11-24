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
    /// A-B-5: also when the local day changed since the last wake (on activation or at midnight while active), so
    /// "Heute neu", the calendar and day-dependent rows recompute with the current date.
    func observeCatalogWake() {
        let day = WakeDay(Upcoming.dayKey(Date(), calendar: Upcoming.localCalendar))
        let center = NotificationCenter.default
        for name in [UIApplication.didBecomeActiveNotification, UIApplication.significantTimeChangeNotification] {
            _ = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let now = Date(), cal = Upcoming.localCalendar
                    // Nur je gezeigte Reihen: übernommene, nie gezeigte Plattencache-Reihen erneuern sich beim ersten Zeigen.
                    let due = !self.cache.keysNeedingRefresh(includingRestored: false).isEmpty
                    guard Upcoming.wakeNeeded(lastDay: day.value, now: now, calendar: cal, cacheDue: due) else { return }
                    let today = Upcoming.dayKey(now, calendar: cal)
                    if today != day.value { RemoteLog.info("katalog", "Neuer Tag · Reihen rechnen neu") }
                    day.value = today
                    self.catalogWake += 1
                }
            }
        }
    }
}

/// Last local day seen by `observeCatalogWake` (main queue only).
private final class WakeDay: @unchecked Sendable {
    var value: String
    init(_ value: String) { self.value = value }
}
