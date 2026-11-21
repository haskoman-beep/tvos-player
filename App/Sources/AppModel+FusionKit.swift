import Foundation
import PlayerCore

// Fusion-Startseiten-Kit: Trakt nur mit Client ID (öffentliche Listen) und Handy-Import einer Kit-URL.
extension AppModel {
    /// Trakt nur mit Client ID (ohne Secret/Anmeldung) – reicht für öffentliche Listen, wie sie das Kit nutzt.
    var traktPublic: TraktClient? {
        guard let id = profile.apiKeys["trakt_id"], !id.isEmpty else { return nil }
        return TraktClient(clientID: id, clientSecret: "")
    }

    var hasTraktID: Bool { !(profile.apiKeys["trakt_id"] ?? "").isEmpty }

    /// „Copy JSON URL“ aus kit.betterer.cc (oder eine andere Fusion-Datei): Reihen wählen und auf die Startseite.
    func importFusionKit(from urlString: String) async {
        let u = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: u), url.scheme == "https" || url.scheme == "http", url.host != nil else {
            lastError = "Kit-URL ungültig: \(u)"; return
        }
        if let e = await FusionKitStore.shared.importURL(u) { lastError = "Kit nicht geladen: \(e)" }
    }
}
