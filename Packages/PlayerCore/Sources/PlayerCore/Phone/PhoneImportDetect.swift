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
        /// Task 4.3: a configurator export (`schema` matches) that `LookImport` cannot read.
        case lookInvalid
        public var text: String {
            switch self {
            case .lookInvalid: "Aussehen nicht übernommen: keine lesbare Aussehen-Datei aus dem Konfigurator."
            case .backup: "Sicherung erkannt: bitte das Feld „Sicherung wiederherstellen“ nutzen."
            case .kitText: "Fusion-Kit als Text: bitte die „Copy JSON URL“ einfügen."
            }
        }
    }

    /// Text der Rückmeldung zur Kennung (`unknown` bzw. ein `Refusal`).
    public static func noteText(_ code: String) -> String? {
        if code == "unknown" { return "Schnell-Import nicht erkannt. Möglich: Addon-Manifest, TMDB-/Trakt-Liste, Collection-Link oder -Code (Widget-Export, Preview Pack, Collection-Export)." }
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
        // Wave F-o round 2: every other JSON link is a collection link; the TV detects the format from the content.
        _ = host
        if path.hasSuffix(".json") { return .command(.importCollectionLink(t)) }
        return .unknown
    }

    static func detectJSON(_ s: String) -> Result {
        let data = Data(s.utf8)
        // Task 4.3: `"schema":"player.appearance.preset"` is a look from the configurator.
        if LookImport.claims(data) {
            guard let look = try? LookImport.parse(data).look else { return .refused(.lookInvalid) }
            return .command(.look(look))
        }
        switch CollectionImportFormat.detect(data) {
        case .widgets, .collectionList, .previewPack, .collections: return .command(.importCollectionCode(data))
        case .backup: return .refused(.backup)
        case .iconPack, .invalidJSON, .unknown: return .unknown
        }
    }
}
