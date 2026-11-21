import Foundation

/// Welle C-d: ein gemeinsames Import-Feld auf der Handy-Seite. Erkennt, was eingefügt wurde, und macht daraus
/// denselben Befehl wie das passende Einzelfeld. Sicherungen (ersetzen alle Profile) werden nie hier erkannt.
public enum PhoneImportDetect {
    public enum Result: Equatable, Sendable {
        case command(PhoneCommand)
        /// Erkannt, aber bewusst nicht hier (z. B. Sicherung).
        case refused(Refusal)
        case unknown
    }

    /// Grund der Ablehnung; `rawValue` geht als Kennung in die Rückmeldung der Seite.
    public enum Refusal: String, Equatable, Sendable {
        case backup, kitText
        public var text: String {
            switch self {
            case .backup: "Sicherung erkannt: bitte das Feld „Sicherung wiederherstellen“ nutzen."
            case .kitText: "Fusion-Kit als Text: bitte die „Copy JSON URL“ einfügen."
            }
        }
    }

    /// Text der Rückmeldung zur Kennung (`unknown` bzw. ein `Refusal`).
    public static func noteText(_ code: String) -> String? {
        if code == "unknown" { return "Schnell-Import nicht erkannt. Möglich: Addon-Manifest, TMDB-/Trakt-Liste, Fusion-Kit- oder Nuvio-URL, Nuvio-JSON." }
        return Refusal(rawValue: code)?.text
    }

    public static func detect(_ raw: String) -> Result {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return .unknown }
        if s.hasPrefix("{") || s.hasPrefix("[") { return detectJSON(s) }
        var t = s
        // stremio:// nur für Manifest-Adressen umschreiben.
        if t.lowercased().hasPrefix("stremio://") {
            t = "https://" + t.dropFirst("stremio://".count)
            guard URL(string: t)?.path.lowercased().hasSuffix("/manifest.json") == true else { return .unknown }
        }
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
            if d["profiles"] != nil { return .refused(.backup) }
            if d["widgets"] != nil || d["exportType"] != nil { return .refused(.kitText) }
            return .unknown
        }
        if let arr = o as? [[String: Any]], let first = arr.first {
            if first["folders"] != nil { return .command(.importNuvioJSON(Data(s.utf8))) }
            if first["dataSources"] != nil { return .refused(.kitText) }
        }
        return .unknown
    }
}
