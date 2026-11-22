import Foundation

/// Eine abspielbare Datei aus dem TorBox-Konto (Torrents, Usenet, Web-Downloads).
public struct TorBoxFile: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case torrent, usenet, webdl
        /// Pfad der Listen- und Link-Endpunkte, Name des ID-Parameters für `requestdl`.
        var path: String { switch self { case .torrent: "torrents"; case .usenet: "usenet"; case .webdl: "webdl" } }
        var idParam: String { switch self { case .torrent: "torrent_id"; case .usenet: "usenet_id"; case .webdl: "web_id" } }
    }
    public var kind: Kind
    public var itemID: Int
    public var fileID: Int
    /// Dateiname ohne Ordner.
    public var name: String
    /// Name des Downloads (Ordner), für die Anzeige.
    public var folder: String
    public var size: Int64
    /// Zeitpunkt des Hinzufügens (neueste zuerst).
    public var added: Date?

    public var id: String { "\(kind.rawValue):\(itemID):\(fileID)" }
    /// "12,3 GB".
    public var sizeLabel: String { DesignText.decimal(Double(size) / 1_000_000_000) + " GB" }
}

/// TorBox-API (`https://api.torbox.app`): eigene Dateien (`mylist`) und Abspiel-Link (`requestdl`).
/// Der Schlüssel geht im Authorization-Kopf mit. Ausnahme: `requestdl` ist nur mit dem Parameter `token` dokumentiert,
/// darum steht er dort zusätzlich in der Adresse – mit `redirect=false`, die Adresse geht nie an Player, Log oder
/// Bildschirm (Fehler nur über `userMessage`, Alert und Log schwärzen zusätzlich).
public struct TorBoxClient: Sendable {
    static let base = "https://api.torbox.app/v1/api"
    static let videoExtensions: Set<String> = ["mkv", "mp4", "m4v", "avi", "mov", "ts", "m2ts", "webm", "wmv", "mpg", "mpeg"]
    let apiKey: String
    let http: APISending
    let sleep: APISleep

    public init(apiKey: String, http: APISending = URLSessionSender(), sleep: @escaping APISleep = defaultAPISleep) {
        self.apiKey = apiKey; self.http = http; self.sleep = sleep
    }

    /// Alle fertigen Video-Dateien aus Torrents, Usenet und Web-Downloads, neueste zuerst.
    /// Fällt eine der drei Listen aus, kommen die anderen trotzdem; scheitern alle, wird der erste Fehler geworfen.
    /// `fresh` = an TorBox vorbei neu lesen (`bypass_cache`), nur beim manuellen Neuladen.
    public func files(fresh: Bool = false) async throws -> [TorBoxFile] {
        var out: [TorBoxFile] = []
        var firstError: Error?
        for kind in TorBoxFile.Kind.allCases {
            do { out += try await files(kind, fresh: fresh) } catch { if firstError == nil { firstError = error } }
        }
        if out.isEmpty, let firstError { throw firstError }
        return out.sorted { ($0.added ?? .distantPast, $1.name) > ($1.added ?? .distantPast, $0.name) }
    }

    func files(_ kind: TorBoxFile.Kind, fresh: Bool) async throws -> [TorBoxFile] {
        guard let u = URL(string: "\(Self.base)/\(kind.path)/mylist" + (fresh ? "?bypass_cache=true" : "")) else { return [] }
        return Self.parseList(try await data(u), kind: kind)
    }

    /// Direktlink zum Abspielen (gilt einige Stunden).
    public func link(for f: TorBoxFile) async throws -> URL {
        var c = URLComponents(string: "\(Self.base)/\(f.kind.path)/requestdl")
        c?.queryItems = [URLQueryItem(name: "token", value: apiKey), URLQueryItem(name: f.kind.idParam, value: String(f.itemID)),
                         URLQueryItem(name: "file_id", value: String(f.fileID)), URLQueryItem(name: "redirect", value: "false")]
        guard let u = c?.url else { throw APIError.decoding("url") }
        let o = (try? JSONSerialization.jsonObject(with: try await data(u))) as? [String: Any]
        guard let s = o?["data"] as? String, let link = URL(string: s), link.scheme == "https" || link.scheme == "http" else {
            throw APIError.decoding("requestdl")
        }
        return link
    }

    /// Kurze Meldung je Fehlerart für den Bildschirm, ohne Adresse (und damit ohne Schlüssel).
    public static func userMessage(_ error: Error) -> String {
        switch error {
        case APIError.status(401), APIError.status(403): return "TorBox lehnt den Schlüssel ab"
        case APIError.status(let n): return "TorBox antwortet mit Fehler \(n)"
        case APIError.decoding: return "TorBox-Antwort unverständlich"
        case let e as URLError:
            switch e.code {
            case .timedOut: return "TorBox antwortet nicht (Zeitüberschreitung)"
            case .notConnectedToInternet, .networkConnectionLost: return "Keine Internetverbindung"
            default: return "TorBox nicht erreichbar"
            }
        default: return "TorBox nicht erreichbar"
        }
    }

    private func data(_ u: URL) async throws -> Data {
        let r = try await http.sendRespectingRateLimit(APIRequest(method: "GET", url: u, headers: ["Authorization": "Bearer \(apiKey)"]), sleep: sleep)
        guard (200..<300).contains(r.status) else { throw APIError.status(r.status) }
        return r.data
    }

    static func parseList(_ data: Data, kind: TorBoxFile.Kind) -> [TorBoxFile] {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let items = o["data"] as? [[String: Any]] else { return [] }
        var out: [TorBoxFile] = []
        for it in items {
            guard let id = it["id"] as? Int, it["download_finished"] as? Bool ?? true else { continue }
            let folder = it["name"] as? String ?? ""
            let added = (it["created_at"] as? String).flatMap(ISODate.dateTime)
            for f in it["files"] as? [[String: Any]] ?? [] {
                guard let fid = f["id"] as? Int else { continue }
                let full = (f["short_name"] as? String) ?? (f["name"] as? String) ?? ""
                let name = full.split(separator: "/").last.map(String.init) ?? full
                let ext = name.split(separator: ".").last.map { $0.lowercased() } ?? ""
                guard videoExtensions.contains(ext), !name.lowercased().contains("sample") else { continue }
                let size = (f["size"] as? NSNumber)?.int64Value ?? 0
                out.append(TorBoxFile(kind: kind, itemID: id, fileID: fid, name: name, folder: folder, size: size, added: added))
            }
        }
        return out
    }
}
