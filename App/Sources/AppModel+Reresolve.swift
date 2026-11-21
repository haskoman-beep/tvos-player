import Foundation
import PlayerCore

extension AppModel {
    /// Link der laufenden Quelle neu auflösen (abgelaufener Debrid-Link): das Addon der gemerkten Quelle
    /// frisch fragen (am Quellen-Cache vorbei) und genau dieselbe Datei suchen. nil = nicht gefunden.
    func freshStreamURL(for r: PlayRequest) async -> URL? {
        guard let last = progress.lastSource(for: r.id), last.contentID == r.id else {
            RemoteLog.info("player", "Neu auflösen: keine gemerkte Quelle für \(r.id)"); return nil
        }
        guard let addon = profile.addons.first(where: { $0.manifest.name == last.addon }) else {
            RemoteLog.info("player", "Neu auflösen: Addon \(last.addon) nicht installiert"); return nil
        }
        do {
            let list = try await addons.streams(addon, type: r.type, id: r.id)
            let url = last.exactURL(in: list)
            RemoteLog.info("player", "Neu auflösen bei \(last.addon): \(list.count) Quellen · \(url == nil ? "Datei nicht mehr da" : "frischer Link")")
            return url
        } catch {
            RemoteLog.error("player", "Neu auflösen fehlgeschlagen: \(error)")
            return nil
        }
    }
}
