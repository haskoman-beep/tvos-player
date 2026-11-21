import Foundation
import PlayerCore

extension AppModel {
    /// Link der laufenden Quelle neu auflösen (abgelaufener Debrid-Link): das Addon der gemerkten Quelle
    /// frisch fragen (am Quellen-Cache vorbei) und genau dieselbe Datei suchen; mit den Kopfzeilen der frischen
    /// Quelle. nil = nicht gefunden.
    func freshStream(for r: PlayRequest) async -> (url: URL, headers: [String: String])? {
        guard let last = progress.lastSource(for: r.id), last.contentID == r.id else {
            RemoteLog.info("player", "Neu auflösen: keine gemerkte Quelle für \(r.id)"); return nil
        }
        guard let addon = profile.addons.first(where: { $0.manifest.name == last.addon }) else {
            RemoteLog.info("player", "Neu auflösen: Addon \(last.addon) nicht installiert"); return nil
        }
        do {
            let list = try await addons.streams(addon, type: r.type, id: r.id)
            let hit = last.exactStream(in: list)
            RemoteLog.info("player", "Neu auflösen bei \(last.addon): \(list.count) Quellen · \(hit == nil ? "Datei nicht mehr da" : "frischer Link")")
            guard let hit, let url = hit.url.flatMap(URL.init(string:)) else { return nil }
            return (url, hit.behaviorHints?.proxyHeaders?.request ?? [:])
        } catch {
            RemoteLog.error("player", "Neu auflösen fehlgeschlagen: \(error)")
            return nil
        }
    }
}
