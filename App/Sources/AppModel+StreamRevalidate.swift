import Foundation
import PlayerCore

/// Welle C-b (#29): Quellen-Cache nach „alten Stand sofort zeigen, im Hintergrund erneuern“
/// (`RevalidationPolicy.streams`). Die Erneuerung läuft als normale Abfrage ohne Cache-Blick; ihr Ergebnis
/// ersetzt den Stand erst vollständig (`storeStreams`). Eine leere Antwort ersetzt keinen vorhandenen Stand.
/// Eine schon offene Quellenliste behält ihre Liste (kein Springen unter dem Fokus); die nächste Öffnung
/// und die Technik-Plaketten bekommen den neuen Stand.
extension AppModel {
    /// true = frisch, false = veraltet (Erneuerung angestoßen), nil = abgelaufen (neu laden).
    func streamCacheHit(type: String, id: String, at: Date) -> Bool? {
        switch RevalidationPolicy.streams.state(storedAt: at) {
        case .fresh: return true
        case .expired: return nil
        case .stale:
            revalidateStreams(type: type, id: id)
            return false
        }
    }

    /// Höchstens eine Abfrage je ID gleichzeitig (`streamTasks` legt gleiche Abfragen ohnehin zusammen).
    func revalidateStreams(type: String, id: String) {
        guard streamTasks[id] == nil else { return }
        let before = streamCache[id]?.list.count ?? 0
        let t0 = Date()
        Task { @MainActor in
            let list = await streams(type: type, id: id, revalidate: true)
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            if list.isEmpty {
                RemoteLog.info("streams", "\(id): Erneuerung leer (\(ms) ms), alter Stand bleibt (\(before) Quellen)")
            } else {
                RemoteLog.info("streams", "\(id): im Hintergrund erneuert (\(ms) ms) · \(before) → \(list.count) Quellen")
            }
        }
    }
}
