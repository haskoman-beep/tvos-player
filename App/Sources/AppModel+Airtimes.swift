import Foundation
import PlayerCore

/// Welle C-d: Kalender-Sendezeiten über TVmaze (eigener Zwischenspeicher, 6 h je Serie).
extension AppModel {
    nonisolated static let airtimes = TVmazeAirtimes()

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
