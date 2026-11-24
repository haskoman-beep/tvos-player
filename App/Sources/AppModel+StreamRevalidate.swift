import Foundation
import PlayerCore

/// Welle C-b (#29): Quellen-Cache nach „alten Stand sofort zeigen, im Hintergrund erneuern“
/// (`RevalidationPolicy.streams`). Die Erneuerung läuft als normale Abfrage ohne Cache-Blick; ihr Ergebnis
/// ersetzt den Stand erst vollständig (`storeStreams` über `StreamCacheUpdate`). Eine leere Antwort ersetzt keinen vorhandenen Stand,
/// Addons ohne Antwort behalten ihre alten Einträge (`StreamListMerge`). Nach einer leeren Antwort oder
/// „alle Addons leer“ wird eine Weile nicht erneuert (Ratenbegrenzung nicht verschärfen); Task 3.7: die Pause nach
/// „alle Addons leer“ gilt nur fürs Vorladen, nie für eine geöffnete Seite.
/// Eine schon offene Quellenliste behält ihre Liste (kein Springen unter dem Fokus); die nächste Öffnung
/// und die Technik-Plaketten bekommen den neuen Stand.
extension AppModel {
    /// true = frisch, false = veraltet (Erneuerung angestoßen), nil = abgelaufen (neu laden).
    /// Task 3.7 (A-A-4): the pause after „alle Addons leer“ holds back only renewals the prefetch asks for; an open
    /// page renews (the 120-s empty mark of this title still applies).
    func streamCacheHit(type: String, id: String, at: Date, caller: StreamCaller = .page) -> Bool? {
        switch RevalidationPolicy.streams.state(storedAt: at) {
        case .fresh: return true
        case .expired: return nil
        case .stale:
            let now = Date()
            if RevalidationPolicy.revalidationAllowed(emptyUntil: streamEmptyUntil[id],
                                                      allEmptyAt: caller == .page ? nil : streamsAllEmptyAt,
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

    /// Für Weiterschauen mit letzter Quelle und automatische nächste Folge: ist der Stand veraltet und läuft
    /// die Erneuerung, auf sie warten (frischer Cache-Status, gültige Links). Leere Erneuerung → alter Stand.
    /// Task 3.7: at most `autoplayRenewalWait` (3 s), then the start goes on with the stale state; the renewal keeps
    /// running and fills the cache. Not held back by the prefetch pause (the user starts playback).
    func streamsForAutoplay(type: String, id: String) async -> [(addon: String, stream: StreamItem)] {
        let list = await streams(type: type, id: id)
        guard let c = streamCache[id], RevalidationPolicy.streams.state(storedAt: c.at) == .stale,
              RevalidationPolicy.revalidationAllowed(emptyUntil: streamEmptyUntil[id], allEmptyAt: nil,
                                                     pause: StreamPrefetcher.allEmptyPause) else { return list }
        RemoteLog.info("streams", "\(id): Start aus veraltetem Stand, warte höchstens \(Int(Self.autoplayRenewalWait)) s auf Erneuerung")
        let scope = scopes.current   // Task 3.1: the wait belongs to this profile and epoch
        let t0 = ProcessInfo.processInfo.systemUptime
        // Legt sich über `streamTasks` mit der eben angestoßenen Hintergrund-Erneuerung zusammen.
        let renewal = Task { () -> [(addon: String, stream: StreamItem)]? in
            await self.streams(type: type, id: id, revalidate: true)
        }
        let fresh = await AddonMetaFetch.wait(for: renewal, atMost: Self.autoplayRenewalWait)
        let ms = Int((ProcessInfo.processInfo.systemUptime - t0) * 1000)
        guard scopes.isCurrent(scope) else {
            RemoteLog.info("profil", "Ergebnis verworfen (Epoche) · Autostart \(id)")
            return []
        }
        guard let fresh else {
            RemoteLog.info("streams", "autostart: gewartet \(ms) ms · Erneuerung noch offen, Start aus vorhandenem Stand")
            return list
        }
        RemoteLog.info("streams", "autostart: gewartet \(ms) ms · \(fresh.isEmpty ? "Erneuerung leer, alter Stand" : "erneuert")")
        return fresh.isEmpty ? list : fresh
    }

    /// Task 3.7: longest wait of an autostart for the renewal of a stale state.
    static let autoplayRenewalWait: Double = 3

    /// Welle D-b (M3): Stand wurde lückenhaft abgelegt und ist inzwischen veraltet (Erneuerung erlaubt).
    /// Task 3.7: `forPage` = an open source list asks; the prefetch pause does not hold it back.
    func partialNeedsRefresh(id: String, now: Date = Date(), forPage: Bool = false) -> Bool {
        guard let c = streamCache[id] else { return false }
        return StreamCacheUpdate.awaitsPartialRefresh(partial: streamPartial.contains(id), storedAt: c.at,
                                                      emptyUntil: streamEmptyUntil[id],
                                                      allEmptyAt: forPage ? nil : streamsAllEmptyAt,
                                                      pause: StreamPrefetcher.allEmptyPause, now: now)
    }

    /// Welle D-b (M3): Zeigt die Quellenliste einen veralteten, lückenhaften Stand, wartet sie danach auf dessen
    /// Erneuerung (legt sich mit der schon angestoßenen zusammen) und übernimmt sie. nil = nichts zu übernehmen
    /// (Stand vollständig, frisch, gesperrt oder Erneuerung leer).
    func refreshedPartialStreams(type: String, id: String) async -> [(addon: String, stream: StreamItem)]? {
        guard partialNeedsRefresh(id: id, forPage: true) else { return nil }
        RemoteLog.info("streams", "\(id): lückenhafter Stand gezeigt, Liste übernimmt die Erneuerung")
        let fresh = await streams(type: type, id: id, revalidate: true)
        return fresh.isEmpty ? nil : fresh
    }
}
