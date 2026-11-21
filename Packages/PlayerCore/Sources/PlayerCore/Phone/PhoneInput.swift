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
    /// Welle F-e, „Startseite ordnen“: Reihe an Position (0-basiert) schieben.
    case moveRow(id: UUID, to: Int)
    /// Reihe ausblenden (von der Startseite nehmen; bleibt einblendbar).
    case removeRow(UUID)
    /// Ausgeblendete Reihe einblenden (`RowContent.key`), kommt ans Ende.
    case addRow(key: String)
}

/// Seitenlogik ohne Netzwerk: Token prüfen, Formular lesen, Befehle erzeugen.
public struct PhoneInputPage: Sendable {
    public let token: String
    public static let services = ["tmdb", "mdblist", "tvdb", "trakt_id", "trakt_secret", "simkl_id", "atvloadly", "torbox"]

    public init(token: String) { self.token = token }

    public static func randomToken() -> String {
        let chars = Array("abcdefghjkmnpqrstuvwxyz23456789")
        return String((0..<10).map { _ in chars.randomElement()! })
    }

    /// `backup` liefert den Profil-Export für GET /export; `home` den Stand für „Startseite ordnen“.
    public func handle(_ r: HTTPRequest, profileName: String, home: PhoneHomeState = .empty,
                       backup: () -> Data) -> (HTTPResponse, [PhoneCommand]) {
        guard r.query["t"] == token || r.form["t"] == token else {
            return (HTTPResponse(status: 403, body: Data(Self.html("Kein Zugang", "<p>Bitte den QR-Code am Fernseher neu scannen.</p>").utf8)), [])
        }
        switch (r.method, r.path) {
        case ("GET", "/"):
            return (HTTPResponse(status: 200, body: Data(page(profileName: profileName, note: r.query["ok"], importNote: r.query["imp"],
                                                              home: home).utf8)), [])
        case ("GET", "/export"):
            return (HTTPResponse(status: 200, contentType: "application/json", body: backup(),
                                 extraHeaders: ["Content-Disposition": "attachment; filename=\"player-profile.json\""]), [])
        case ("POST", "/submit"):
            let f = r.form
            var cmds: [PhoneCommand] = []
            func val(_ k: String) -> String? { f[k].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 } }
            var importNote: String?
            if let x = val("import") {   // gemeinsames Feld, Erkennung in PhoneImportDetect
                switch PhoneImportDetect.detect(x) {
                case .command(let c): cmds.append(c)
                case .refused(let why): importNote = why.rawValue
                case .unknown: importNote = "unknown"
                }
            }
            if let a = val("addon") { cmds.append(.addAddon(a)) }
            for s in Self.services { if let v = val("key_\(s)") { cmds.append(.setKey(service: s, value: v)) } }
            if let n = val("nuvio_url") { cmds.append(.importNuvioURL(n)) }
            if let j = val("nuvio_json") { cmds.append(.importNuvioJSON(Data(j.utf8))) }
            if let l = val("tmdb_link") { cmds.append(.addTMDBLink(l)) }
            if let b = val("backup_json") { cmds.append(.importBackup(Data(b.utf8))) }
            if let k = val("kit_url") { cmds.append(.importFusionURL(k)) }
            let note = cmds.isEmpty ? "leer" : "\(cmds.count)"
            // Rückmeldung zum Schnell-Import immer mitgeben; „Nichts ausgefüllt“ entfällt, wenn nur er etwas meldet.
            var loc = "/?t=\(token)"
            if !(cmds.isEmpty && importNote != nil) { loc += "&ok=\(note)" }
            if let importNote { loc += "&imp=\(importNote)" }
            return (HTTPResponse(status: 303, body: Data(), extraHeaders: ["Location": loc]), cmds)
        case ("POST", "/home"):
            // Welle F-e: ein Zug je Anfrage (Knopf oder Ziehen); Stand vom Fernseher, nicht vom Handy.
            let cmds = home.command(op: r.form["op"] ?? "").map { [$0] } ?? []
            let loc = "/?t=\(token)&ok=\(cmds.isEmpty ? "home0" : "home")#order"
            return (HTTPResponse(status: 303, body: Data(), extraHeaders: ["Location": loc]), cmds)
        default:
            return (HTTPResponse(status: 404, body: Data(Self.html("Nicht gefunden", "").utf8)), [])
        }
    }

    func page(profileName: String, note: String?, importNote: String? = nil, home: PhoneHomeState = .empty) -> String {
        var msg: String
        switch note {
        case nil, "home", "home0": msg = ""   // Rückmeldung von „Startseite ordnen“ steht in dessen Abschnitt
        case "leer": msg = "<p class=ok>Nichts ausgefüllt.</p>"
        case let n?: msg = "<p class=ok>✓ \(Self.escape(n)) Eingabe(n) an den Fernseher geschickt. Ergebnis siehst du dort.</p>"
        }
        if let t = importNote.flatMap(PhoneImportDetect.noteText) { msg += "<p class=ok>\(Self.escape(t))</p>" }
        func field(_ name: String, _ label: String, _ ph: String, area: Bool = false) -> String {
            area ? "<label>\(label)<textarea name=\(name) rows=4 placeholder=\"\(ph)\"></textarea></label>"
                 : "<label>\(label)<input name=\(name) autocapitalize=off autocorrect=off placeholder=\"\(ph)\"></label>"
        }
        func head(_ s: PhoneSection) -> String { "<h2>\(s.title)</h2>" }
        let nav = PhoneSection.allCases.map { "<a href=\"#\($0.rawValue)\">\($0.title)</a>" }.joined(separator: " · ")
        let body = """
        \(msg)<nav>\(nav)</nav>
        <form method=post action="/submit?t=\(token)">
        <section id=\(PhoneSection.quickImport.rawValue)>\(head(.quickImport))\(field("import", "Link oder JSON einfügen – wird erkannt (Addon, TMDB-/Trakt-Liste, Fusion-Kit, Nuvio)", "https://…", area: true))</section>
        <section id=\(PhoneSection.addon.rawValue)>\(head(.addon))\(field("addon", "Addon hinzufügen: Manifest-URL", "https://…/manifest.json"))
        \(field("key_torbox", "TorBox-API-Key (Bibliothek „Meine TorBox-Dateien“)", ""))</section>
        <section id=\(PhoneSection.keys.rawValue)>\(head(.keys))\(field("key_tmdb", "TMDB-API-Key", ""))\(field("key_mdblist", "MDBList-Key", ""))\(field("key_tvdb", "TVDB-Key", ""))
        \(field("key_trakt_id", "Trakt Client ID", ""))\(field("key_trakt_secret", "Trakt Client Secret", ""))\(field("key_simkl_id", "Simkl Client ID", ""))</section>
        <section id=\(PhoneSection.home.rawValue)>\(head(.home))<h3>Collections importieren</h3>
        \(field("nuvio_url", "Nuvio-Export (URL)", "https://…json"))\(field("nuvio_json", "… oder Nuvio-JSON einfügen", "{…}", area: true))
        \(field("tmdb_link", "TMDB- oder Trakt-Liste, Filmreihe, Studio als Reihe", "https://www.themoviedb.org/list/… oder https://trakt.tv/users/…/lists/…"))
        \(field("kit_url", "Fusion-Kit: „Copy JSON URL“ einfügen (braucht meist die Trakt Client ID)", "https://raw.githubusercontent.com/…json"))
        <p><a href="\(FusionKitCatalog.siteURL)">Kit-Katalog öffnen</a></p>
        \(orderSection(home, note: note))</section>
        <section id=\(PhoneSection.system.rawValue)>\(head(.system))\(field("key_atvloadly", "App-Update: atvloadly-Adresse (Pi)", "http://pi-name.local:5533"))
        <h3>Sicherung</h3><p><a href="/export?t=\(token)">Alle Profile herunterladen (JSON)</a></p>
        \(field("backup_json", "Sicherung wiederherstellen (ersetzt alle Profile!)", "{…}", area: true))</section>
        <button>An den Fernseher senden</button>
        </form>
        <form id=homeform method=post action="/home?t=\(token)"></form>
        <script>\(Self.orderScript)</script>
        """
        return Self.html("Player · \(Self.escape(profileName))", body)
    }

    /// Welle F-e: „Startseite ordnen“. Knöpfe gehören über `form=homeform` zum eigenen Formular (ohne die Felder oben,
    /// damit Eingetipptes beim Umsortieren nicht mitgeschickt wird). Ohne Skript geht jeder Knopf per Neuladen.
    func orderSection(_ home: PhoneHomeState, note: String?) -> String {
        var out = "<div id=order><h3>Startseite ordnen</h3>"
        switch note {
        case "home": out += "<p class=ok>✓ Am Fernseher geändert.</p>"
        case "home0": out += "<p class=ok>Nichts geändert (Liste war veraltet, jetzt neu geladen).</p>"
        default: break
        }
        out += "<p class=hint>Am Griff ≡ ziehen oder die Pfeile tippen. Änderungen gelten sofort.</p>"
        func button(_ op: String, _ sym: String, _ label: String, disabled: Bool = false) -> String {
            "<button form=homeform name=op value=\"\(Self.escape(op))\" aria-label=\"\(label)\" title=\"\(label)\"\(disabled ? " disabled" : "")>\(sym)</button>"
        }
        func text(_ r: PhoneHomeRow) -> String {
            "<span class=t>\(Self.escape(r.title))" + (r.detail.isEmpty ? "" : "<small>\(Self.escape(r.detail))</small>") + "</span>"
        }
        if home.shown.isEmpty {
            out += "<p>Keine Reihen auf der Startseite.</p>"
        } else {
            out += "<ol id=rowlist class=rows>"
            let last = home.shown.count - 1
            for (i, r) in home.shown.enumerated() {
                let id = Self.escape(r.id)
                out += "<li data-id=\"\(id)\"><span class=grip role=img aria-label=\"Ziehen zum Verschieben\">≡</span>\(text(r))<span class=btns>"
                out += button("top:\(r.id)", "⤒", "Ganz nach oben", disabled: i == 0)
                out += button("up:\(r.id)", "↑", "Nach oben", disabled: i == 0)
                out += button("down:\(r.id)", "↓", "Nach unten", disabled: i == last)
                out += button("bottom:\(r.id)", "⤓", "Ganz nach unten", disabled: i == last)
                out += button("hide:\(r.id)", "✕", "Ausblenden")
                out += "</span></li>"
            }
            out += "</ol>"
        }
        if !home.hidden.isEmpty {
            out += "<details><summary>Ausgeblendet (\(home.hidden.count)) – Einblenden hängt unten an</summary><ul class=rows>"
            for r in home.hidden {
                out += "<li>\(text(r))<span class=btns>\(button("show:\(r.id)", "＋", "Einblenden"))</span></li>"
            }
            out += "</ul></details>"
        }
        return out + "</div>"
    }

    /// Ziehen per Touch (Pointer-Events am Griff) und Knöpfe ohne Neuladen: Zug per fetch an /home,
    /// danach wird nur der Abschnitt `#order` aus der Antwortseite ersetzt. Fehler → normales Absenden.
    static let orderScript = """
    (function(){var f=document.getElementById('homeform');if(!f||!window.fetch)return;
    function fallback(op){var i=document.createElement('input');i.type='hidden';i.name='op';i.value=op;f.appendChild(i);f.submit();}
    function send(op){fetch(f.action,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'op='+encodeURIComponent(op)})
    .then(function(r){if(!r.ok)throw 0;return r.text();}).then(function(h){var n=new DOMParser().parseFromString(h,'text/html').getElementById('order'),o=document.getElementById('order');
    if(!n||!o)throw 0;var d=o.querySelector('details'),open=d&&d.open;o.replaceWith(n);var d2=n.querySelector('details');if(d2&&open)d2.open=true;bind();})
    .catch(function(){fallback(op);});}
    function bind(){var o=document.getElementById('order');if(!o)return;
    o.querySelectorAll('button[name=op]').forEach(function(b){b.addEventListener('click',function(e){e.preventDefault();send(b.value);});});
    var list=document.getElementById('rowlist');if(!list)return;
    list.querySelectorAll('.grip').forEach(function(g){g.addEventListener('pointerdown',function(e){var li=g.parentNode,kids=function(){return[].slice.call(list.children);},from=kids().indexOf(li),next=li.nextSibling;
    e.preventDefault();try{g.setPointerCapture(e.pointerId);}catch(x){}li.classList.add('drag');
    function move(ev){var y=ev.clientY,before=null,s=kids().filter(function(x){return x!==li;});
    for(var i=0;i<s.length;i++){var r=s[i].getBoundingClientRect();if(y<r.top+r.height/2){before=s[i];break;}}
    list.insertBefore(li,before);if(y<60)window.scrollBy(0,-12);else if(y>window.innerHeight-60)window.scrollBy(0,12);}
    function end(ev){g.removeEventListener('pointermove',move);g.removeEventListener('pointerup',end);g.removeEventListener('pointercancel',end);li.classList.remove('drag');
    if(ev.type==='pointercancel'){list.insertBefore(li,next);return;}var to=kids().indexOf(li);if(to!==from)send('to:'+li.getAttribute('data-id')+':'+to);}
    g.addEventListener('pointermove',move);g.addEventListener('pointerup',end);g.addEventListener('pointercancel',end);});});}
    bind();})();
    """

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
        a{color:#0a84ff}.ok{background:#1d3b23;padding:10px;border-radius:10px}h3{font-size:16px;margin-top:20px;color:#ccc}
        nav{font-size:15px;line-height:1.8}section{scroll-margin-top:12px}.hint{color:#aaa;font-size:15px}
        .rows{list-style:none;padding:0;margin:8px 0}.rows li{display:flex;align-items:center;gap:8px;padding:8px;margin:6px 0;border-radius:10px;background:#222}
        .rows li.drag{background:#2c3e57;box-shadow:0 4px 14px #000}.grip{touch-action:none;user-select:none;-webkit-user-select:none;font-size:24px;padding:4px 8px;color:#aaa;cursor:grab}
        .t{flex:1;min-width:0;overflow-wrap:anywhere}.t small{display:block;color:#999;font-size:13px}.btns{display:flex;gap:4px}
        .btns button{margin:0;width:38px;height:38px;padding:0;font-size:18px;border-radius:8px;background:#333}.btns button:disabled{opacity:.3}
        summary{margin-top:12px;color:#ccc}
        </style><h1>\(title)</h1>\(body)</html>
        """
    }
}
