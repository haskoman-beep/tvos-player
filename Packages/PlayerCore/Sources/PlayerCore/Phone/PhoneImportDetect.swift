import Foundation

/// Welle C-d: ein gemeinsames Import-Feld auf der Handy-Seite. Erkennt, was eingefügt wurde, und macht daraus
/// denselben Befehl wie das passende Einzelfeld. Sicherungen (ersetzen alle Profile) werden nie hier erkannt.
public enum PhoneImportDetect {
    public enum Result: Equatable, Sendable {
        case command(PhoneCommand)
        /// Erkannt, aber bewusst nicht hier (z. B. Sicherung); Text für die Rückmeldung.
        case refused(String)
        case unknown
    }

    public static func detect(_ raw: String) -> Result {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return .unknown }
        if s.hasPrefix("{") || s.hasPrefix("[") { return detectJSON(s) }
        var t = s
        if t.lowercased().hasPrefix("stremio://") { t = "https://" + t.dropFirst("stremio://".count) }
        guard let u = URL(string: t), let scheme = u.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = u.host?.lowercased() else { return .unknown }
        let path = u.path.lowercased()
        if path.hasSuffix("/manifest.json") { return .command(.addAddon(t)) }
        if TMDBLink.source(from: t) != nil || TraktLink.source(from: t) != nil { return .command(.addTMDBLink(t)) }
        if path.hasSuffix(".json") {
            let low = t.lowercased()
            if low.contains("fusion") || host.hasSuffix("betterer.cc") { return .command(.importFusionURL(t)) }
            return .command(.importNuvioURL(t))
        }
        return .unknown
    }

    static func detectJSON(_ s: String) -> Result {
        guard let o = try? JSONSerialization.jsonObject(with: Data(s.utf8)) else { return .unknown }
        if let d = o as? [String: Any] {
            if d["profiles"] != nil { return .refused("Sicherung erkannt: bitte das Feld „Sicherung wiederherstellen“ nutzen.") }
            if d["widgets"] != nil || d["exportType"] != nil { return .refused("Fusion-Kit als Text: bitte die „Copy JSON URL“ einfügen.") }
            return .unknown
        }
        if let arr = o as? [[String: Any]], let first = arr.first {
            if first["folders"] != nil { return .command(.importNuvioJSON(Data(s.utf8))) }
            if first["dataSources"] != nil { return .refused("Fusion-Kit als Text: bitte die „Copy JSON URL“ einfügen.") }
        }
        return .unknown
    }
}
