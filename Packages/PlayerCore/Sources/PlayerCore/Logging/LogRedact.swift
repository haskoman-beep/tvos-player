import Foundation

/// Logzeilen entschärfen: Debrid-/Addon-Adressen tragen Schlüssel im Pfad
/// (Torrentio `providers=…|realdebrid=…`, AIOStreams-UUID + Konfiguration) oder in der Query (TorBox `token=…`).
/// Von einer Adresse bleibt Schema + Host (+ Port) und die letzte Pfadkomponente, gekürzt – aber nur, wenn sie
/// wie ein Dateiname mit bekannter Endung oder eine IMDb-ID (`tt…`) aussieht und nicht nach Schlüssel
/// (Task 1.5, SEC-8). Query, Fragment, Zugangsdaten und alle übrigen Pfadteile fallen weg.
/// Im Freitext zusätzlich: Werte hinter `token=`, `apiKey:`, `refreshToken: Optional("…")`, `sig=`, `Cookie:` usw.,
/// `Bearer …`/`Basic …` und lange undurchsichtige Zeichenketten (≥ 32 Zeichen) werden zu „…“.
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
        // Schon gekürzte Zeile (zweiter Durchlauf): Marke abnehmen, damit sie nie Teil eines Werts wird.
        var input = s
        var wasCut = false
        if input.hasSuffix(cutMarker) { input = String(input.dropLast(cutMarker.count)); wasCut = true }
        let (head, cutNow) = capped(input)
        var out = head
        if out.contains("/") { out = replaceURLs(out) }
        let lower = out.lowercased()
        if keyWords.contains(where: { lower.contains($0) }) { out = maskKeyValues(out) }
        if lower.contains("bearer") || lower.contains("basic") {
            out = bearerPattern.stringByReplacingMatches(
                in: out, range: NSRange(location: 0, length: (out as NSString).length), withTemplate: "$1 …")
        }
        if longestTokenRun(out) >= opaqueRun {
            out = opaquePattern.stringByReplacingMatches(
                in: out, range: NSRange(location: 0, length: (out as NSString).length), withTemplate: "…")
        }
        // „…“ (3 Bytes) kann die Zeile verlängern: Grenze nach dem Entschärfen erneut anwenden.
        // Marke erst ganz am Ende und nur einmal anhängen (mit Leerzeichen davor).
        if wasCut || cutNow || out.utf8.count > maxLineBytes {
            return prefix(out, bytes: maxLineBytes - cutMarker.utf8.count) + cutMarker
        }
        return out
    }

    /// Längste Logzeile in UTF-8-Bytes (samt Kürzungsmarke); begrenzt die Regex-Laufzeit.
    public static let maxLineBytes = 8 * 1024
    public static let cutMarker = " …[gekürzt]"

    // MARK: - intern

    /// Zeilen über `maxLineBytes` so kürzen, dass sie mit Marke höchstens `maxLineBytes` lang sind
    /// (vor jedem Regex: begrenzt Rücksprünge in allen Mustern).
    private static func capped(_ s: String) -> (String, Bool) {
        guard s.utf8.count > maxLineBytes else { return (s, false) }
        return (prefix(s, bytes: maxLineBytes - cutMarker.utf8.count), true)
    }

    /// Längster Anfang aus ganzen Zeichen mit höchstens `bytes` UTF-8-Bytes.
    private static func prefix(_ s: String, bytes: Int) -> String {
        guard s.utf8.count > bytes else { return s }
        var used = 0
        var end = s.startIndex
        for i in s.indices {
            let n = s[i].utf8.count
            if used + n > bytes { break }
            used += n
            end = s.index(after: i)
        }
        return String(s[..<end])
    }

    /// Teil nach `schema://` (bzw. eine Adresse ohne Schema): Host + gekürzter Pfad.
    private static func redactAfterScheme(_ rest: Substring) -> String {
        // Zugangsdaten (user:pass@) zuerst abtrennen, erst dann Query/Fragment. Das Passwort darf „?“/„#“ enthalten
        // (letztes „@“ vor dem ersten „/“) oder „/“ (Task 1.5: letztes „@“ vor dem ersten „?“/„#“). Ein „@“ hinter dem
        // ersten „/“ zählt nur, wenn der Teil davor wie `user:pass` aussieht (Doppelpunkt, danach keine reine
        // Portnummer) – sonst liegt es im Pfad (`h.example/a@KEY/x.mkv`) und der Host bleibt `h.example`.
        let firstSlash = rest.firstIndex(of: "/") ?? rest.endIndex
        let firstQuery = rest.firstIndex(where: { $0 == "?" || $0 == "#" }) ?? rest.endIndex
        let atBeforeSlash = rest[..<firstSlash].lastIndex(of: "@")
        let beforeSlash = rest[..<firstSlash]
        let userinfoShaped = beforeSlash.firstIndex(of: ":").map { colon in
            let after = beforeSlash[beforeSlash.index(after: colon)...]
            return after.isEmpty || !after.allSatisfy(\.isNumber)
        } ?? false
        let atBeforeQuery = userinfoShaped ? rest[..<firstQuery].lastIndex(of: "@") : nil
        let lastAt = [atBeforeSlash, atBeforeQuery].compactMap { $0 }.max()
        let hostStart = lastAt.map { rest.index(after: $0) } ?? rest.startIndex
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
        let plain = last.removingPercentEncoding ?? last
        if last == "…" || looksSecret(plain) || !looksShowable(plain) { return "\(base)/…" }
        let shown = shorten(last)
        return parts.count > 1 ? "\(base)/…/\(shown)" : "\(base)/\(shown)"
    }

    /// Wert hinter einem Schlüsselnamen durch „…“ ersetzen; Anführungszeichen bleiben stehen
    /// (`"…"`, `'…'`). Ungequotete Werte, die mit `schema://` beginnen, sind schon gekürzte Adressen und bleiben.
    private static func maskKeyValues(_ s: String) -> String {
        let ns = s as NSString
        let matches = keyValuePattern.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return s }
        var out = ""
        var pos = 0
        for m in matches {
            let value = m.range(at: 4)
            guard value.location >= pos else { continue }   // inside a header value masked before
            let name = ns.substring(with: m.range(at: 1)).lowercased()
            let v = ns.substring(with: value)
            var end = value.location + value.length
            let masked: String
            if v.hasPrefix("\"") { masked = "\"…\"" }
            else if v.hasPrefix("'") { masked = "'…'" }
            else if headerNames.contains(where: { name.hasSuffix($0) }) {
                // Task 1.5: `Authorization:`/`Cookie:` – the whole value up to the end of the line or a closing
                // bracket (`a=1; b=2`, `Digest username=…, response=…`); the scheme word stays (`Bearer …`).
                end = headerValueEnd(ns, from: value.location)
                let rest = ns.substring(with: NSRange(location: value.location + value.length, length: end - value.location - value.length))
                if authSchemes.contains(v.lowercased()) {
                    masked = rest.trimmingCharacters(in: .whitespaces).isEmpty ? v : v + " …"
                } else {
                    masked = "…"
                }
            }
            else if isNumericCode(name: name, value: v) { masked = v }
            else if v.range(of: #"^[A-Za-z][A-Za-z0-9+.\-]*://"#, options: .regularExpression) != nil { masked = v }
            else { masked = "…" }
            out += ns.substring(with: NSRange(location: pos, length: value.location - pos)) + masked
            pos = end
        }
        out += ns.substring(from: pos)
        return out
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
    /// Torrentio-Konfiguration `providers=…|realdebrid=KEY`, IPv6-Hosts) – oder ohne Schema
    /// `host.tld[:port]/…`, `10.0.0.5[:port]/…`, `localhost[:port]/…`.
    nonisolated(unsafe) private static let urlPattern = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9+.\-])[A-Za-z][A-Za-z0-9+.\-]*://[^\s"'<>]+|(?<![A-Za-z0-9_.@/:%\-])(?:(?:[A-Za-z0-9\-]+\.)+[A-Za-z]{2,}|(?:[0-9]{1,3}\.){3}[0-9]{1,3}|localhost)(?::[0-9]+)?/[^\s"'<>]*"#,
        options: [.caseInsensitive])

    /// Vorprüfung (Teiltext, kleingeschrieben); `pass` deckt `passwd`/`password`, `auth` `authorization`, `sig` `signature`.
    private static let keyWords = ["token", "key", "pass", "secret", "auth", "cookie", "sig", "code", "pin", "hash",
                                   "pwd", "session"]
    /// Kopfzeilen, deren ganzer Wert (bis Zeilenende/Klammer) wegfällt.
    private static let headerNames = ["authorization", "cookie"]
    private static let authSchemes: Set<String> = ["bearer", "basic", "digest"]

    /// Ende eines Kopfzeilenwerts: Zeilenumbruch, schließende Klammer oder Textende.
    private static func headerValueEnd(_ ns: NSString, from start: Int) -> Int {
        var i = start
        while i < ns.length {
            switch ns.character(at: i) {
            case 0x0A, 0x0D, 0x7D, 0x5D, 0x29: return i   // \n \r } ] )
            default: i += 1
            }
        }
        return ns.length
    }

    /// `Code=-1001`, `HTTP code: 404`, `statusCode=503` bleiben lesbar (Fehler- und Statusnummern, keine Kennungen).
    private static func isNumericCode(name: String, value: String) -> Bool {
        guard name == "code" || ["errorcode", "statuscode", "error_code", "status_code", "error-code", "status-code"]
            .contains(where: { name.hasSuffix($0) }) else { return false }
        return value.range(of: #"^-?[0-9]{1,5}$"#, options: .regularExpression) != nil
    }

    /// Schlüsselname (auch mit Vorsilbe/camelCase: `x_api_key`, `userToken`, `clientSecret`, `session_key`),
    /// direkt danach `:`/`=` (sonst kein Treffer – „keyboard“ bleibt). Wert: `"…"`, `'…'` (auch mit Leerzeichen),
    /// `Optional("…")` oder ungequotet bis zum nächsten Trenner. Groß/Klein egal.
    nonisolated(unsafe) private static let keyValuePattern = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_\-])([A-Za-z0-9_\-]*(?:token|key|passwd|password|secret|authorization|auth|cookie|signature|sig|code|pin|hash|pass|pwd|session))(["']?\s*[:=]\s*)(Optional\()?("[^"]*"|'[^']*'|"[^"]*$|'[^']*$|[^\s"',;&)}\]]+)"#,
        options: [.caseInsensitive])

    /// `Bearer <Wert>`, `Basic <Wert>` (Task 1.5) auch ohne Kopfzeilennamen.
    nonisolated(unsafe) private static let bearerPattern = try! NSRegularExpression(
        pattern: #"\b(Bearer|Basic)\s+(?:"[^"]*"|'[^']*'|"[^"]*$|'[^']*$|[A-Za-z0-9._~+/=\-]+)"#, options: [.caseInsensitive])

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

    /// Task 1.5 (SEC-8): Endungen, mit denen die letzte Pfadkomponente als Dateiname sichtbar bleibt.
    static let shownExtensions: Set<String> = [
        "json", "xml", "html", "htm", "txt",
        "mkv", "mp4", "m4v", "mov", "avi", "webm", "ts", "m2ts", "mts", "m3u8", "m3u", "mpd", "iso",
        "mp3", "m4a", "aac", "ac3", "eac3", "flac", "opus",
        "srt", "vtt", "ass", "ssa", "sub", "idx",
        "jpg", "jpeg", "png", "webp", "gif", "svg", "avif", "heic",
        "zip", "ipa",
    ]

    /// Darf die letzte Pfadkomponente stehen bleiben? Nur Dateinamen mit bekannter Endung und IMDb-IDs
    /// (`tt0111161`, auch `tt0944947:1:2`); alles andere (kurze Kennungen, Befehle) wird zu „…“.
    static func looksShowable(_ c: String) -> Bool {
        if c.range(of: #"^tt[0-9]+(:[0-9]+){0,2}$"#, options: .regularExpression) != nil { return true }
        // Already shortened by `shorten` (second pass): it was shown in the first pass.
        if c.hasSuffix("…"), c.count == maxLastComponent { return true }
        guard let dot = c.lastIndex(of: "."), dot != c.startIndex else { return false }
        return shownExtensions.contains(c[c.index(after: dot)...].lowercased())
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
