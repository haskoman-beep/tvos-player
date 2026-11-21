import Foundation

/// Adressen fürs Log entschärfen: Debrid-/Addon-Adressen tragen Schlüssel im Pfad
/// (Torrentio `realdebrid=…`, AIOStreams-UUID + Konfiguration) oder in der Query (TorBox `token=…`).
/// Übrig bleibt Schema + Host (+ Port) und – wenn sie nicht nach Schlüssel aussieht – die letzte
/// Pfadkomponente, gekürzt. Query, Fragment, Zugangsdaten und alle übrigen Pfadteile fallen weg.
public enum LogRedact {
    /// Längste gezeigte letzte Pfadkomponente (danach „…“).
    public static let maxLastComponent = 40

    public static func url(_ url: URL) -> String { self.url(url.absoluteString) }

    /// Eine Adresse als Text. Ohne `schema://` kommt der Text unverändert zurück.
    public static func url(_ s: String) -> String {
        guard let sep = s.range(of: "://") else { return s }
        let scheme = s[..<sep.lowerBound].lowercased()
        var rest = s[sep.upperBound...]
        if let cut = rest.firstIndex(where: { $0 == "?" || $0 == "#" }) { rest = rest[..<cut] }
        let authority: Substring
        let path: Substring
        if let slash = rest.firstIndex(of: "/") {
            authority = rest[..<slash]
            path = rest[rest.index(after: slash)...]
        } else {
            authority = rest
            path = ""
        }
        // Zugangsdaten (user:pass@) weglassen.
        let host = authority.lastIndex(of: "@").map { authority[authority.index(after: $0)...] } ?? authority
        let base = "\(scheme)://\(host.lowercased())"
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let last = parts.last else { return base }
        // Prüfen am entschlüsselten Text (realdebrid%3DKEY), zeigen roh (bleibt beim zweiten Durchlauf gleich).
        if last == "…" || looksSecret(last.removingPercentEncoding ?? last) { return "\(base)/…" }
        let shown = shorten(last)
        return parts.count > 1 ? "\(base)/…/\(shown)" : "\(base)/\(shown)"
    }

    /// Freitext (Logzeile, Fehlerbeschreibung): jede enthaltene Adresse über `url(_:)` kürzen.
    /// Mehrfaches Anwenden ändert nichts mehr.
    public static func text(_ s: String) -> String {
        guard s.contains("://") else { return s }
        let ns = s as NSString
        let matches = pattern.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return s }
        var out = ""
        var pos = 0
        for m in matches {
            var r = m.range
            // Satzzeichen am Ende gehören nicht zur Adresse („…, siehe https://x/y.“).
            while r.length > 0, let c = ns.substring(with: NSRange(location: r.location + r.length - 1, length: 1)).first,
                  ".,;:!)'\"".contains(c) {
                r.length -= 1
            }
            out += ns.substring(with: NSRange(location: pos, length: r.location - pos))
            out += url(ns.substring(with: r))
            pos = r.location + r.length
        }
        out += ns.substring(from: pos)
        return out
    }

    // MARK: - intern

    nonisolated(unsafe) private static let pattern = try! NSRegularExpression(
        pattern: #"[A-Za-z][A-Za-z0-9+.\-]*://[^\s"'<>{}\[\]|\\^`]+"#)

    private static func shorten(_ s: String) -> String {
        s.count > maxLastComponent ? String(s.prefix(maxLastComponent - 1)) + "…" : s
    }

    /// Sieht die Komponente nach Schlüssel/Konfiguration aus? (lieber zu viel weglassen als zu wenig)
    static func looksSecret(_ c: String) -> Bool {
        if c.contains("=") || c.contains("@") { return true }                  // realdebrid=KEY, key=value|…, Base64-Polster
        if UUID(uuidString: c) != nil { return true }                          // AIOStreams-Nutzer, TorBox-Dateien
        // Dateiendung abtrennen (manifest.json, tt0111161.json, Film.2023.mkv).
        var stem = Substring(c)
        if let dot = c.lastIndex(of: "."), c.distance(from: dot, to: c.endIndex) <= 6, dot != c.startIndex {
            stem = c[..<dot]
        }
        if UUID(uuidString: String(stem)) != nil { return true }
        let tokenChars = stem.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        let hasDigit = stem.contains { $0.isNumber }
        let hasLetter = stem.contains { $0.isLetter }
        // Lange Zeichenkette ohne Punkte/Leerzeichen mit Buchstaben und Ziffern: Token, Hash, Base64.
        if tokenChars && stem.count >= 16 && hasDigit && hasLetter { return true }
        if tokenChars && stem.count >= 32 { return true }
        return false
    }
}
