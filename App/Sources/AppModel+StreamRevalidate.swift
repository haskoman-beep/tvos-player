import Foundation
import PlayerCore

/// Welle C-b (#29): Quellen-Cache nach „alten Stand sofort zeigen, im Hintergrund erneuern“
/// (`RevalidationPolicy.streams`). Die Erneuerung läuft als normale Abfrage ohne Cache-Blick; ihr Ergebnis
/// ersetzt den Stand erst vollständig (`storeStreams`). Eine leere Antwort ersetzt keinen vorhandenen Stand,
/// Addons ohne Antwort behalten ihre alten Einträge (`StreamListMerge`). Nach einer leeren Antwort oder
/// „alle Addons leer“ wird eine Weile nicht erneuert (Ratenbegrenzung nicht verschärfen).
/// Eine schon offene Quellenliste behält ihre Liste (kein Springen unter dem Fokus); die nächste Öffnung
/// und die Technik-Plaketten bekommen den neuen Stand.
extension AppModel {
    /// true = frisch, false = veraltet (Erneuerung angestoßen), nil = abgelaufen (neu laden).
    func streamCacheHit(type: String, id: String, at: Date) -> Bool? {
        switch RevalidationPolicy.streams.state(storedAt: at) {
        case .fresh: return true
        case .expired: return nil
        case .stale:
            let now = Date()
            if RevalidationPolicy.revalidationAllowed(emptyUntil: streamEmptyUntil[id], allEmptyAt: streamsAllEmptyAt,
                                                      pause: StreamPrefetcher.allEmptyPause, now: now) {
                revalidateStreams(type: type, id: id)
            }
            return false
        }
    }

    /// Höchstens eine Abfrage je ID gleichzeitig (`streamTasks` legt gleiche Abfragen ohnehin zusammen).
    func revalidateStreams(type: String, id: String) {
        guard streamTasks[id] == nil else { return }
        let before = streamCache[id]?.list.count ?? 0
        let t0 = Date()
        Task { @MainActor in
            // Inzwischen schon erneuert (z. B. von `streamsForAutoplay`): keine zweite Vollabfrage.
            if let c = streamCache[id], RevalidationPolicy.streams.state(storedAt: c.at) == .fresh { return }
            let list = await streams(type: type, id: id, revalidate: true)
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            if list.isEmpty {
                RemoteLog.info("streams", "\(id): Erneuerung leer (\(ms) ms), alter Stand bleibt (\(before) Quellen)")
            } else {
                RemoteLog.info("streams", "\(id): im Hintergrund erneuert (\(ms) ms) · \(before) → \(list.count) Quellen")
            }
        }
    }

    /// Abfrage-Ergebnis mit dem bisherigen Stand zusammenführen: Addons, die nicht geantwortet haben
    /// (in `answered` fehlen), behalten ihre alten Einträge bis 30 min nach ihrer eigenen letzten Antwort
    /// (`RevalidationPolicy.streams.usableFor`). Ein leeres Ergebnis bleibt leer (alter Stand + Pause bleiben).
    func keepingFailedAddonStreams(id: String, answered: [String], list: [(addon: String, stream: StreamItem)]) -> [(addon: String, stream: StreamItem)] {
        let now = Date()
        let old = streamCache[id].flatMap { RevalidationPolicy.streams.isUsable(storedAt: $0.at, now: now) ? $0 : nil }
        let r = StreamListMerge.keepingFailed(fresh: list, previous: old?.list, previousStoredAt: old?.at ?? now,
                                              previousFetchedAt: streamAddonFetchedAt[id] ?? [:], answered: Set(answered),
                                              configured: Set(profile.addons.map { $0.manifest.name }),
                                              now: now, maxAge: RevalidationPolicy.streams.usableFor)
        if !r.list.isEmpty {
            streamAddonFetchedAt = streamAddonFetchedAt.filter { streamCache[$0.key] != nil }
            streamAddonFetchedAt[id] = r.fetchedAt
        }
        if r.list.count != list.count {
            RemoteLog.info("streams", "\(id): \(r.list.count - list.count) Quellen ohne Antwort ihres Addons aus dem alten Stand behalten")
        }
        return r.list
    }

    /// Für Weiterschauen mit letzter Quelle und automatische nächste Folge: ist der Stand veraltet und läuft
    /// die Erneuerung, auf sie warten (frischer Cache-Status, gültige Links). Leere Erneuerung → alter Stand.
    func streamsForAutoplay(type: String, id: String) async -> [(addon: String, stream: StreamItem)] {
        let list = await streams(type: type, id: id)
        guard let c = streamCache[id], RevalidationPolicy.streams.state(storedAt: c.at) == .stale,
              RevalidationPolicy.revalidationAllowed(emptyUntil: streamEmptyUntil[id], allEmptyAt: streamsAllEmptyAt,
                                                     pause: StreamPrefetcher.allEmptyPause) else { return list }
        RemoteLog.info("streams", "\(id): Start aus veraltetem Stand, warte auf Erneuerung")
        // Legt sich über `streamTasks` mit der eben angestoßenen Hintergrund-Erneuerung zusammen.
        let fresh = await streams(type: type, id: id, revalidate: true)
        return fresh.isEmpty ? list : fresh
    }
}
