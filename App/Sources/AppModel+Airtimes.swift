import Foundation
import PlayerCore

/// Neue Kalenderdaten (z. B. nach dem Nachziehen der Sendezeiten): der Kalender lädt dann aus dem Cache neu.
@MainActor
final class UpcomingRevision: ObservableObject {
    static let shared = UpcomingRevision()
    @Published private(set) var value = 0
    func bump() { value += 1 }
}

/// Welle C-d: Kalender-Sendezeiten über TVmaze (Plattencache: IDs dauerhaft, Zeitpunkte 6 h).
extension AppModel {
    nonisolated static let airtimes = TVmazeAirtimes(file: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                                                        .appendingPathComponent("tvmaze.json"))

    /// Sendezeiten im Hintergrund nachziehen und den Kalender-Eintrag danach ersetzen (nur wenn er noch derselbe ist).
    static func enrichAirtimes(key: String, episodes: [UpcomingEpisode]) {
        let cache = UpcomingCache.shared
        guard let stamp = cache.entries[key]?.at else { return }
        Task { @MainActor in
            var bySeries: [String: [UpcomingEpisode]] = [:]
            var order: [String] = []
            for e in episodes {
                if bySeries[e.seriesID] == nil { order.append(e.seriesID) }
                bySeries[e.seriesID, default: []].append(e)
            }
            var done: [UpcomingEpisode] = []
            await withTaskGroup(of: [UpcomingEpisode].self) { g in
                var queue = order.makeIterator()
                for _ in 0..<4 {
                    if let id = queue.next(), let eps = bySeries[id] { g.addTask { await AppModel.withAirtimes(eps, id: id, enabled: true) } }
                }
                while let r = await g.next() {
                    done += r
                    if let id = queue.next(), let eps = bySeries[id] { g.addTask { await AppModel.withAirtimes(eps, id: id, enabled: true) } }
                }
            }
            // Welle D-b (N-M5): die TVmaze-Datei einmal je Durchgang schreiben, nicht je Serie.
            await airtimes.flush()
            // Welle D-b (N-M4): in die ursprüngliche Reihenfolge zurück, damit der Vergleich den Inhalt prüft.
            let out = TVmazeClient.merged(episodes, updated: done)
            guard cache.entries[key]?.at == stamp, out != episodes else { return }
            cache.entries[key]?.episodes = out
            UpcomingRevision.shared.bump()
            RemoteLog.info("kalender", "Sendezeiten nachgezogen: \(out.filter { $0.airTime != nil }.count) von \(out.count) Folgen")
        }
    }

    /// Folgen einer Serie mit Sendetag/-zeit aus TVmaze; ohne IMDb-ID, ausgeschaltet oder ohne Treffer unverändert.
    nonisolated static func withAirtimes(_ eps: [UpcomingEpisode], id: String, enabled: Bool) async -> [UpcomingEpisode] {
        guard enabled, id.hasPrefix("tt"), !eps.isEmpty else { return eps }
        let stamps = await airtimes.stamps(imdb: id)
        guard !stamps.isEmpty else { return eps }
        let out = TVmazeClient.apply(eps, stamps: stamps, calendar: Upcoming.localCalendar)
        let moved = zip(eps, out).filter { $0.airDate != $1.airDate }.count
        if moved > 0 { await MainActor.run { RemoteLog.info("kalender", "\(id): \(moved) Folge(n) per TVmaze auf anderen Tag") } }
        return out
    }
}
