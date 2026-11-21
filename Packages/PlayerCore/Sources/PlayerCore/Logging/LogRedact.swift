import Foundation

/// Logzeilen entschärfen: Debrid-/Addon-Adressen tragen Schlüssel im Pfad
/// (Torrentio `providers=…|realdebrid=…`, AIOStreams-UUID + Konfiguration) oder in der Query (TorBox `token=…`).
/// Von einer Adresse bleibt Schema + Host (+ Port) und – wenn sie nicht nach Schlüssel aussieht – die letzte
/// Pfadkomponente, gekürzt. Query, Fragment, Zugangsdaten und alle übrigen Pfadteile fallen weg.
/// Im Freitext zusätzlich: Werte hinter `token=`, `apiKey:`, `refreshToken: Optional("…")` usw. und
/// lange undurchsichtige Zeichenketten (≥ 32 Zeichen) werden zu „…“.
public enum LogRedact {
    /// Längste gezeigte letzte Pfadkomponente (danach „…“).
    public static let maxLastComponent = 40
    /// Ab dieser Länge gilt eine Folge aus `[A-Za-z0-9_-]` im Freitext als Schlüssel.
    public static let opaqueRun = 32

    public static func url(_ url: URL) -> String { self.url(url.absoluteString) }

    /// Eine Adresse als Text. Ohne `schema://` kommt der Text unverändert zurück.
    public static func url(_ s: String) -> String {
        guard let sep = s.range(of: "://") else { return s }
        return s[..<sep.lowerBound].lowercased() + "://" + redactAfterScheme(s[sep.upperBound...])
    }

    /// Freitext (Logzeile, Fehlerbeschreibung). Mehrfaches Anwenden ändert nichts mehr.
    public static func text(_ s: String) -> String {
        var out = s
        if out.contains("/") { out = replaceURLs(out) }
        let lower = out.lowercased()
        if keyWords.contains(where: { lower.contains($0) }) {
            out = keyValuePattern.stringByReplacingMatches(
                in: out, range: NSRange(location: 0, length: (out as NSString).length), withTemplate: "$1$2$3$4…")
        }
        if longestTokenRun(out) >= opaqueRun {
            out = opaquePattern.stringByReplacingMatches(
                in: out, range: NSRange(location: 0, length: (out as NSString).length), withTemplate: "…")
        }
        return out
    }

    // MARK: - intern

    /// Teil nach `schema://` (bzw. eine Adresse ohne Schema): Host + gekürzter Pfad.
    private static func redactAfterScheme(_ rest: Substring) -> String {
        // Zugangsdaten (user:pass@) zuerst abtrennen – sie dürfen „?“/„#“ enthalten –, erst dann Query/Fragment.
        let firstSlash = rest.firstIndex(of: "/") ?? rest.endIndex
        let hostStart = rest[..<firstSlash].lastIndex(of: "@").map { rest.index(after: $0) } ?? rest.startIndex
        let afterUser = rest[hostStart...]
        let hostEnd = afterUser.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? afterUser.endIndex
        let base = afterUser[..<hostEnd].lowercased()
        var path = afterUser[hostEnd...]
        guard path.first == "/" else { return base }
        path = path.dropFirst()
        if let cut = path.firstIndex(where: { $0 == "?" || $0 == "#" }) { path = path[..<cut] }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let last = parts.last else { return base }
        // Prüfen am entschlüsselten Text (realdebrid%3DKEY), zeigen roh (bleibt beim zweiten Durchlauf gleich).
        if last == "…" || looksSecret(last.removingPercentEncoding ?? last) { return "\(base)/…" }
        let shown = shorten(last)
        return parts.count > 1 ? "\(base)/…/\(shown)" : "\(base)/\(shown)"
    }

    private static func replaceURLs(_ s: String) -> String {
        let ns = s as NSString
        let matches = urlPattern.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return s }
        var out = ""
        var pos = 0
        for m in matches {
            var r = m.range
            // Satzzeichen/Klammern am Ende gehören nicht zur Adresse („…, siehe https://x/y.“, `UserInfo={…}`).
            while r.length > 0, let c = ns.substring(with: NSRange(location: r.location + r.length - 1, length: 1)).first,
                  ".,;:!)]}'\"".contains(c) {
                r.length -= 1
            }
            let found = ns.substring(with: r)
            out += ns.substring(with: NSRange(location: pos, length: r.location - pos))
            if let sep = found.range(of: "://") {
                out += found[..<sep.lowerBound].lowercased() + "://" + redactAfterScheme(found[sep.upperBound...])
            } else {
                out += redactAfterScheme(Substring(found))   // ohne Schema: host.tld/…
            }
            pos = r.location + r.length
        }
        out += ns.substring(from: pos)
        return out
    }

    /// Adresse mit Schema bis zum nächsten Leerraum/Anführungszeichen (`|`, `{`, `[` gehören dazu:
    /// Torrentio-Konfiguration `providers=…|realdebrid=KEY`, IPv6-Hosts) – oder ohne Schema `host.tld[:port]/…`.
    nonisolated(unsafe) private static let urlPattern = try! NSRegularExpression(
        pattern: #"[A-Za-z][A-Za-z0-9+.\-]*://[^\s"'<>]+|(?<![A-Za-z0-9_.@/:%\-])(?:[A-Za-z0-9\-]+\.)+[A-Za-z]{2,}(?::[0-9]+)?/[^\s"'<>]*"#)

    private static let keyWords = ["token", "key", "password", "secret"]

    /// `token=…`, `apiKey: …`, `"api_key":"…"`, `refreshToken: Optional("…")` (Groß/Klein egal).
    nonisolated(unsafe) private static let keyValuePattern = try! NSRegularExpression(
        pattern: #"\b((?:access|refresh|auth)?[-_]?token|api[-_]?key|apikey|key|password|secret)("?\s*[:=]\s*)(Optional\()?("?)[^\s"',;&)}\]]+"#,
        options: [.caseInsensitive])

    nonisolated(unsafe) private static let opaquePattern = try! NSRegularExpression(
        pattern: "[A-Za-z0-9_-]{\(opaqueRun),}")

    /// Längste Folge aus `[A-Za-z0-9_-]` (billige Vorprüfung vor dem Regex).
    private static func longestTokenRun(_ s: String) -> Int {
        var best = 0, cur = 0
        for b in s.utf8 {
            switch b {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "_"), UInt8(ascii: "-"):
                cur += 1
                if cur > best { best = cur }
            default:
                cur = 0
            }
        }
        return best
    }

    private static func shorten(_ s: String) -> String {
        s.count > maxLastComponent ? String(s.prefix(maxLastComponent - 1)) + "…" : s
    }

    /// Sieht die Komponente nach Schlüssel/Konfiguration aus? (lieber zu viel weglassen als zu wenig)
    static func looksSecret(_ c: String) -> Bool {
        if c.contains("=") || c.contains("@") || c.contains("|") { return true }  // realdebrid=KEY, key=value|…, Base64-Polster
        if UUID(uuidString: c) != nil { return true }                            // AIOStreams-Nutzer, TorBox-Dateien
        // Dateiendung abtrennen (manifest.json, tt0111161.json, Film.2023.mkv).
        var stem = Substring(c)
        if let dot = c.lastIndex(of: "."), c.distance(from: dot, to: c.endIndex) <= 6, dot != c.startIndex {
            stem = c[..<dot]
        }
        if UUID(uuidString: String(stem)) != nil { return true }
        let tokenChars = stem.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "+" || $0 == "~")
        }
        let hasDigit = stem.contains { $0.isNumber }
        let hasLetter = stem.contains { $0.isLetter }
        // Lange Zeichenkette mit Buchstaben und Ziffern: Token, Hash, Base64.
        if tokenChars && stem.count >= 16 && hasDigit && hasLetter { return true }
        if tokenChars && stem.count >= 32 { return true }
        if !stem.contains(".") && stem.count >= 24 && hasDigit && hasLetter { return true }
        return false
    }
}
