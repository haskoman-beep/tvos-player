import Foundation

/// Minimaler HTTP/1.1-Parser für die Handy-Eingabeseite (Spec §5). Kein Keep-Alive, eine Anfrage pro Verbindung.
public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    public var query: [String: String]
    public var headers: [String: String]   // Schlüssel klein geschrieben
    public var body: Data

    public enum ParseResult: Equatable, Sendable { case incomplete, invalid, tooLarge, complete(HTTPRequest) }

    public static let maxBody = 8 * 1024 * 1024

    public static func parse(_ data: Data) -> ParseResult {
        let sep = Data("\r\n\r\n".utf8)
        guard let r = data.range(of: sep) else { return data.count > 64 * 1024 ? .invalid : .incomplete }
        guard let head = String(data: data[..<r.lowerBound], encoding: .utf8) else { return .invalid }
        var lines = head.components(separatedBy: "\r\n")
        let first = lines.removeFirst().split(separator: " ")
        guard first.count >= 2 else { return .invalid }
        var headers: [String: String] = [:]
        for l in lines {
            guard let c = l.firstIndex(of: ":") else { continue }
            headers[l[..<c].trimmingCharacters(in: .whitespaces).lowercased()] = l[l.index(after: c)...].trimmingCharacters(in: .whitespaces)
        }
        let len = Int(headers["content-length"] ?? "0") ?? -1
        guard len >= 0 else { return .invalid }
        guard len <= maxBody else { return .tooLarge }
        let bodyStart = r.upperBound
        guard data.count - bodyStart >= len else { return .incomplete }
        let target = String(first[1])
        let comps = URLComponents(string: target)
        var q: [String: String] = [:]
        for i in comps?.queryItems ?? [] { q[i.name] = i.value ?? "" }
        return .complete(HTTPRequest(method: String(first[0]), path: comps?.path ?? target, query: q, headers: headers,
                                     body: data.subdata(in: bodyStart..<(bodyStart + len))))
    }

    /// application/x-www-form-urlencoded
    public var form: [String: String] {
        guard let s = String(data: body, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for pair in s.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map { String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? "" }
            if let k = kv.first, !k.isEmpty { out[k] = kv.count > 1 ? kv[1] : "" }
        }
        return out
    }
}

public struct HTTPResponse: Equatable, Sendable {
    public var status: Int
    public var contentType: String
    public var body: Data
    public var extraHeaders: [String: String] = [:]

    public init(status: Int, contentType: String = "text/html; charset=utf-8", body: Data, extraHeaders: [String: String] = [:]) {
        self.status = status; self.contentType = contentType; self.body = body; self.extraHeaders = extraHeaders
    }

    public var serialized: Data {
        let reason = [200: "OK", 303: "See Other", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 413: "Payload Too Large"][status] ?? "OK"
        var h = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n"
        for (k, v) in extraHeaders.sorted(by: { $0.key < $1.key }) { h += "\(k): \(v)\r\n" }
        return Data((h + "\r\n").utf8) + body
    }
}

/// Was die Handy-Seite an die App weitergibt.
public enum PhoneCommand: Equatable, Sendable {
    case addAddon(String)
    case setKey(service: String, value: String)
    case importNuvioURL(String)
    case importNuvioJSON(Data)
    case addTMDBLink(String)
    case importBackup(Data)
    /// Fusion-Kit-Datei („Copy JSON URL“ auf kit.betterer.cc): Reihen auf die Startseite.
    case importFusionURL(String)
}

/// Seitenlogik ohne Netzwerk: Token prüfen, Formular lesen, Befehle erzeugen.
public struct PhoneInputPage: Sendable {
    public let token: String
    public static let services = ["tmdb", "mdblist", "tvdb", "trakt_id", "trakt_secret", "simkl_id"]

    public init(token: String) { self.token = token }

    public static func randomToken() -> String {
        let chars = Array("abcdefghjkmnpqrstuvwxyz23456789")
        return String((0..<10).map { _ in chars.randomElement()! })
    }

    /// `backup` liefert den Profil-Export für GET /export.
    public func handle(_ r: HTTPRequest, profileName: String, backup: () -> Data) -> (HTTPResponse, [PhoneCommand]) {
        guard r.query["t"] == token || r.form["t"] == token else {
            return (HTTPResponse(status: 403, body: Data(Self.html("Kein Zugang", "<p>Bitte den QR-Code am Fernseher neu scannen.</p>").utf8)), [])
        }
        switch (r.method, r.path) {
        case ("GET", "/"):
            return (HTTPResponse(status: 200, body: Data(page(profileName: profileName, note: r.query["ok"]).utf8)), [])
        case ("GET", "/export"):
            return (HTTPResponse(status: 200, contentType: "application/json", body: backup(),
                                 extraHeaders: ["Content-Disposition": "attachment; filename=\"player-profile.json\""]), [])
        case ("POST", "/submit"):
            let f = r.form
            var cmds: [PhoneCommand] = []
            func val(_ k: String) -> String? { f[k].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 } }
            if let a = val("addon") { cmds.append(.addAddon(a)) }
            for s in Self.services { if let v = val("key_\(s)") { cmds.append(.setKey(service: s, value: v)) } }
            if let n = val("nuvio_url") { cmds.append(.importNuvioURL(n)) }
            if let j = val("nuvio_json") { cmds.append(.importNuvioJSON(Data(j.utf8))) }
            if let l = val("tmdb_link") { cmds.append(.addTMDBLink(l)) }
            if let b = val("backup_json") { cmds.append(.importBackup(Data(b.utf8))) }
            if let k = val("kit_url") { cmds.append(.importFusionURL(k)) }
            let note = cmds.isEmpty ? "leer" : "\(cmds.count)"
            return (HTTPResponse(status: 303, body: Data(), extraHeaders: ["Location": "/?t=\(token)&ok=\(note)"]), cmds)
        default:
            return (HTTPResponse(status: 404, body: Data(Self.html("Nicht gefunden", "").utf8)), [])
        }
    }

    func page(profileName: String, note: String?) -> String {
        let msg: String
        switch note {
        case nil: msg = ""
        case "leer": msg = "<p class=ok>Nichts ausgefüllt.</p>"
        case let n?: msg = "<p class=ok>✓ \(n) Eingabe(n) an den Fernseher geschickt. Ergebnis siehst du dort.</p>"
        }
        func field(_ name: String, _ label: String, _ ph: String, area: Bool = false) -> String {
            area ? "<label>\(label)<textarea name=\(name) rows=4 placeholder=\"\(ph)\"></textarea></label>"
                 : "<label>\(label)<input name=\(name) autocapitalize=off autocorrect=off placeholder=\"\(ph)\"></label>"
        }
        let body = """
        \(msg)
        <form method=post action="/submit?t=\(token)">
        <h2>Addon</h2>\(field("addon", "Manifest-URL", "https://…/manifest.json"))
        <h2>Schlüssel</h2>\(field("key_tmdb", "TMDB-API-Key", ""))\(field("key_mdblist", "MDBList-Key", ""))\(field("key_tvdb", "TVDB-Key", ""))
        \(field("key_trakt_id", "Trakt Client ID", ""))\(field("key_trakt_secret", "Trakt Client Secret", ""))\(field("key_simkl_id", "Simkl Client ID", ""))
        <h2>Collections</h2>\(field("nuvio_url", "Nuvio-Export (URL)", "https://…json"))\(field("nuvio_json", "… oder Nuvio-JSON einfügen", "{…}", area: true))
        \(field("tmdb_link", "TMDB- oder Trakt-Liste, Filmreihe, Studio als Reihe", "https://www.themoviedb.org/list/… oder https://trakt.tv/users/…/lists/…"))
        \(field("kit_url", "Fusion-Kit: „Copy JSON URL“ einfügen (braucht meist die Trakt Client ID)", "https://raw.githubusercontent.com/…json"))
        <p><a href="\(FusionKitCatalog.siteURL)">Kit-Katalog öffnen</a></p>
        <h2>Sicherung</h2><p><a href="/export?t=\(token)">Alle Profile herunterladen (JSON)</a></p>
        \(field("backup_json", "Sicherung wiederherstellen (ersetzt alle Profile!)", "{…}", area: true))
        <button>An den Fernseher senden</button>
        </form>
        """
        return Self.html("Player · \(Self.escape(profileName))", body)
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func html(_ title: String, _ body: String) -> String {
        """
        <!doctype html><html lang=de><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
        <title>\(title)</title><style>
        body{font:17px -apple-system,system-ui,sans-serif;margin:0 auto;max-width:640px;padding:16px;background:#111;color:#eee}
        h1{font-size:24px}h2{font-size:18px;margin-top:28px;color:#aaa}label{display:block;margin:10px 0}
        input,textarea{display:block;width:100%;box-sizing:border-box;margin-top:4px;padding:10px;font:inherit;border-radius:10px;border:1px solid #444;background:#222;color:#eee}
        button{margin-top:24px;width:100%;padding:14px;font:inherit;font-weight:600;border:0;border-radius:12px;background:#0a84ff;color:#fff}
        a{color:#0a84ff}.ok{background:#1d3b23;padding:10px;border-radius:10px}
        </style><h1>\(title)</h1>\(body)</html>
        """
    }
}
