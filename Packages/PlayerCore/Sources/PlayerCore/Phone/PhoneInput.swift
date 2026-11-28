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

    public enum HeadResult: Equatable, Sendable { case incomplete, invalid, complete(RequestHead) }

    /// Task 1.4 (SEC-5): request line and headers only, before any body is accepted. The server checks access and the
    /// body limit of the path (`PhoneLimits`) on this, so a body is read only for an admitted request.
    public static func parseHead(_ data: Data) -> HeadResult {
        let sep = Data("\r\n\r\n".utf8)
        guard let r = data.range(of: sep) else { return data.count > PhoneLimits.maxHead ? .invalid : .incomplete }
        guard r.lowerBound - data.startIndex <= PhoneLimits.maxHead,
              let head = String(data: data[..<r.lowerBound], encoding: .utf8) else { return .invalid }
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
        let target = String(first[1])
        let comps = URLComponents(string: target)
        var q: [String: String] = [:]
        for i in comps?.queryItems ?? [] { q[i.name] = i.value ?? "" }
        return .complete(RequestHead(method: String(first[0]), path: comps?.path ?? target, query: q, headers: headers,
                                     contentLength: len, bodyStart: r.upperBound - data.startIndex))
    }

    public static func parse(_ data: Data) -> ParseResult {
        let h: RequestHead
        switch parseHead(data) {
        case .incomplete: return .incomplete
        case .invalid: return .invalid
        case .complete(let x): h = x
        }
        guard h.contentLength <= maxBody else { return .tooLarge }
        let bodyStart = data.startIndex + h.bodyStart
        guard data.count - h.bodyStart >= h.contentLength else { return .incomplete }
        return .complete(HTTPRequest(method: h.method, path: h.path, query: h.query, headers: h.headers,
                                     body: data.subdata(in: bodyStart..<(bodyStart + h.contentLength))))
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

/// Task 1.4: request line and headers of a request whose body has not been read yet.
public struct RequestHead: Equatable, Sendable {
    public var method: String
    public var path: String
    public var query: [String: String]
    public var headers: [String: String]   // Schlüssel klein geschrieben
    public var contentLength: Int
    /// Offset of the body in the received bytes.
    public var bodyStart: Int
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
        let reason = [200: "OK", 303: "See Other", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 409: "Conflict", 413: "Payload Too Large", 503: "Service Unavailable"][status] ?? "OK"
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
    /// Reihe ausblenden: von der Startseite nehmen und vollständig unter „Ausgeblendet“ merken.
    case removeRow(UUID)
    /// Welle F-f: Reihe endgültig löschen (nicht unter „Ausgeblendet“); die Seite fragt vorher nach.
    case deleteRow(UUID)
    /// Ausgeblendete Reihe unverändert wieder einblenden (gleiche ID und Stil), kommt ans Ende.
    case restoreRow(UUID)
    /// Weitere Reihe aus den Angeboten (`RowContent.key`) hinzufügen, kommt ans Ende.
    case addRow(key: String)
    /// Welle F-a (E7): Adresse eines eigenen Bewertungs-Icon-Satzes (JSON); am Fernseher gibt es kein Feld mehr.
    case setRatingIconSet(String)
    /// Wave F-o round 2: collection link (widget export, preview pack, collection export); the TV fetches it,
    /// detects the format and keeps the link for "Aktualisieren".
    case importCollectionLink(String)
    /// Wave F-o round 2: pasted collection code (same formats as the link).
    case importCollectionCode(Data)
    /// Task 1.4: `GET /export?secrets=1` – after the TV allowed it, the TV seals the full backup with a code it shows
    /// and the phone fetches the file from `PhoneInputPage.sealedPath`.
    case exportSecrets
    /// Task 4.3: a look from the configurator (`LookImport`); sets the active profile's look. Changes only the
    /// appearance, never keys or addons, so it needs no confirmation on the TV.
    case look(Look)
    /// plan_nuvio_konto T1: sign in to a Nuvio account with the e-mail and password typed on the phone
    /// (`POST /nuvio`). Both stay wrapped, so a log of the command never shows them; the TV confirms first.
    case nuvioSignIn(email: PhoneSecret, password: PhoneSecret)
}

/// plan_nuvio_konto T1: a value from the phone that must never reach a log, a notice or a dump (the Nuvio e-mail and
/// password). Not `Codable` on purpose; printing, debug printing and reflection show only `‹verborgen›`. It lives
/// from the POST until the sign-in call returns and is never stored.
public struct PhoneSecret: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public static let masked = "‹verborgen›"
    public let value: String
    public init(_ value: String) { self.value = value }
    public var description: String { Self.masked }
    public var debugDescription: String { Self.masked }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

/// plan_nuvio_konto T1: what the section „Nuvio-Konto“ on the phone page shows. The form only when signed out.
public enum PhoneNuvioState: Equatable, Sendable {
    case signedOut
    /// `profileName`: the chosen Nuvio profile, nil while none is chosen.
    case connected(profileName: String?)
    /// A sign-in runs on the TV.
    case busy
}

/// Task 1.4: what the page may do with backups right now.
public struct PhoneBackupState: Equatable, Sendable {
    /// Task 1.3 interface: the stored profiles are unreadable (`AppModel.storeState`). Then the profiles in memory are
    /// the stand-in default profile: no export and no restore over the phone until the TV has chosen a version.
    public var blocked: Bool
    /// The sealed full backup after the TV allowed it (`PhoneCommand.exportSecrets`), ready for one download.
    public var sealedFile: Data?
    /// The sealed file was fetched already: the download page stops waiting.
    public var sealedDelivered: Bool
    /// Fix round 1: the sealed export ended without a file; the download page stops waiting and says why.
    public var sealedOutcome: PhoneSealedOutcome?
    /// Fix round 1: a request already waits on the TV (`PhoneConfirmGate.current`). New requests that need a
    /// confirmation are refused with a note on the phone instead of only on the TV.
    public var requestOpen: Bool

    public init(blocked: Bool = false, sealedFile: Data? = nil, sealedDelivered: Bool = false,
                sealedOutcome: PhoneSealedOutcome? = nil, requestOpen: Bool = false) {
        self.blocked = blocked; self.sealedFile = sealedFile; self.sealedDelivered = sealedDelivered
        self.sealedOutcome = sealedOutcome; self.requestOpen = requestOpen
    }
}

/// Fix round 1: why the sealed export ended without a file.
public enum PhoneSealedOutcome: String, Equatable, Sendable {
    /// „Ablehnen“ on the TV (or Menu).
    case declined
    /// No answer on the TV within `PhoneConfirmGate.lifetime`, or the file was not fetched in time.
    case lapsed
    /// Another request was still waiting on the TV.
    case busy
    /// The TV could not seal the backup (it says why).
    case failed

    public var text: String {
        switch self {
        case .declined: return "Am Fernseher abgelehnt. Es wurde keine Sicherung erstellt."
        case .lapsed: return "Die Anfrage ist abgelaufen. Bitte erneut auf „verschlüsselt herunterladen“ tippen."
        case .busy: return PhoneInputPage.busyText
        case .failed: return "Die Sicherung konnte am Fernseher nicht erstellt werden. Der Grund steht dort."
        }
    }
}

/// Seitenlogik ohne Netzwerk: Formular lesen, Befehle erzeugen. Task 1.4: access is checked before, on the request
/// head (`PhoneSession.admit`); the page never carries the token.
public struct PhoneInputPage: Sendable {
    public static let services = ["tmdb", "mdblist", "trakt_id", "trakt_secret", "simkl_id", "atvloadly", "torbox", "playerlog"]
    /// Download address of the sealed backup (waits with a refresh until the TV allowed it).
    public static let sealedPath = "/export/sicherung"
    static let blockedText = "Die Profile am Fernseher sind gerade nicht lesbar. Sichern und Wiederherstellen sind gesperrt, bis dort eine Fassung geladen oder neu angefangen wurde."
    public static let busyText = "Am Fernseher wartet schon eine Anfrage. Bitte zuerst dort antworten und dann erneut senden."
    /// plan_nuvio_konto T1: own form for the Nuvio sign-in (password only in the POST body, never in a URL).
    public static let nuvioPath = "/nuvio"
    /// Longest accepted e-mail and password (characters each).
    static let nuvioFieldLimit = 256
    static let nuvioSentText = "Gesendet. Bitte am Fernseher „Erlauben“ wählen."
    static let nuvioEmptyText = "Bitte E-Mail und Passwort eingeben."
    static let nuvioHintText = "Der Fernseher fragt nach, bevor er sich anmeldet. Das Passwort wird nicht gespeichert."
    /// Residual risk of the plain-HTTP LAN form (plan section 2), same words as the hint on the TV.
    static let nuvioRiskText = "Es geht einmal unverschlüsselt durch dein WLAN zum Fernseher und von dort verschlüsselt an Nuvio. Nutze ein Passwort, das du nur für Nuvio verwendest."
    static let nuvioConnectedText = "Mit Nuvio verbunden. Abmelden geht am Fernseher unter Einstellungen › Konten."
    static let nuvioBusyText = "Anmeldung läuft …"

    public init() {}

    public static func randomToken() -> String {
        let chars = Array("abcdefghjkmnpqrstuvwxyz23456789")
        return String((0..<10).map { _ in chars.randomElement()! })
    }

    /// `backup` liefert den Profil-Export ohne Geheimnisse für GET /export; `home` den Stand für „Startseite ordnen“.
    public func handle(_ r: HTTPRequest, profileName: String, home: PhoneHomeState = .empty,
                       backups: PhoneBackupState = PhoneBackupState(), nuvio: PhoneNuvioState = .signedOut,
                       backup: () -> Data) -> (HTTPResponse, [PhoneCommand]) {
        switch (r.method, r.path) {
        case ("GET", "/"):
            return (HTTPResponse(status: 200, body: Data(page(profileName: profileName, note: r.query["ok"], importNote: r.query["imp"],
                                                              lookNote: r.query["lk"], lookUnknown: r.query["lku"],
                                                              home: home, backupBlocked: backups.blocked,
                                                              requestWaiting: r.query["wt"] == "offen",
                                                              nuvio: nuvio, nuvioNote: r.query["nv"]).utf8)), [])
        case ("GET", "/export"), ("GET", Self.sealedPath):
            guard !backups.blocked else {
                return (HTTPResponse(status: 409, body: Data(Self.html("Gesperrt", "<p>\(Self.blockedText)</p>").utf8)), [])
            }
            if r.path == Self.sealedPath {
                guard let file = backups.sealedFile else {
                    if backups.sealedDelivered {
                        return (HTTPResponse(status: 200, body: Data(Self.html("Sicherung", "<p>Die Datei \(BackupCrypto.fileName) wurde geladen. Den Code zeigt der Fernseher.</p><p><a href=\"/\">Zurück</a></p>").utf8)), [])
                    }
                    // Fix round 1: declined, lapsed, refused or failed – no further refresh.
                    if let o = backups.sealedOutcome { return (Self.sealedEnd(o.text), []) }
                    return (HTTPResponse(status: 200, body: Data(Self.html("Sicherung", Self.sealedWaitBody, refresh: 3).utf8)), [])
                }
                return (HTTPResponse(status: 200, contentType: "application/octet-stream", body: file,
                                     extraHeaders: ["Content-Disposition": "attachment; filename=\"\(BackupCrypto.fileName)\""]), [])
            }
            if r.query["secrets"] == "1" {
                if backups.requestOpen { return (Self.sealedEnd(Self.busyText), []) }
                return (HTTPResponse(status: 200, body: Data(Self.html("Sicherung", Self.sealedWaitBody, refresh: 3).utf8)), [.exportSecrets])
            }
            return (HTTPResponse(status: 200, contentType: "application/json", body: backup(),
                                 extraHeaders: ["Content-Disposition": "attachment; filename=\"player-profile.json\""]), [])
        case ("POST", "/submit"):
            let f = r.form
            var cmds: [PhoneCommand] = []
            func val(_ k: String) -> String? { f[k].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 } }
            var importNote: String?
            // Task 4.3: answer to a look ("lk" = number of deviations or a failure code, "lku" = unknown values).
            // Task 4.5-base fix round 1 (I1): deviations from the baseline, the same count as the settings row.
            var lookParams: [String] = []
            func takeLook(_ text: String) {
                do {
                    let (look, report) = try LookImport.parse(Data(text.utf8))
                    cmds.append(.look(look))
                    lookParams = ["lk=\(LookPreset.baselineDeviationCount(look))"] + (report.isEmpty ? [] : ["lku=\(report.ignored.count)"])
                } catch {
                    lookParams = ["lk=\((error as? LookImport.Failure ?? .notAnExport).code)"]
                }
            }
            if let x = val("import") {   // gemeinsames Feld, Erkennung in PhoneImportDetect
                switch PhoneImportDetect.detect(x) {
                case .command(.look): takeLook(x)
                case .command(let c): cmds.append(c)
                case .refused(let why): importNote = why.rawValue
                case .unknown: importNote = "unknown"
                }
            }
            if let a = val("addon") { cmds.append(.addAddon(a)) }
            for s in Self.services { if let v = val("key_\(s)") { cmds.append(.setKey(service: s, value: v)) } }
            // Wave F-o round 2: the collection fields take every collection format (detected on the TV).
            if let n = val("nuvio_url") { cmds.append(.importCollectionLink(n)) }
            if let j = val("nuvio_json") { cmds.append(.importCollectionCode(Data(j.utf8))) }
            if let l = val("tmdb_link") { cmds.append(.addTMDBLink(l)) }
            var backupRefused = false
            if let b = val("backup_json") {
                if backups.blocked { backupRefused = true } else { cmds.append(.importBackup(Data(b.utf8))) }
            }
            if let k = val("kit_url") { cmds.append(.importFusionURL(k)) }
            if let i = val("icon_set") { cmds.append(.setRatingIconSet(i)) }
            if let l = val("look_json") { takeLook(l) }
            // Fix round 1: while a request waits on the TV, everything that needs a confirmation is refused here, so
            // the phone hears of it; plain entries still go through.
            var busy = false
            if backups.requestOpen {
                let kept = cmds.filter { if case .plain = $0.sensitivity { return true } else { return false } }
                busy = kept.count != cmds.count
                cmds = kept
            }
            let note = cmds.isEmpty ? "leer" : "\(cmds.count)"
            // Rückmeldung zum Schnell-Import immer mitgeben; „Nichts ausgefüllt“ entfällt, wenn nur er etwas meldet.
            var params: [String] = []
            if !(cmds.isEmpty && (importNote != nil || backupRefused || busy || !lookParams.isEmpty)) { params.append("ok=\(note)") }
            if let importNote { params.append("imp=\(importNote)") }
            params += lookParams
            if backupRefused { params.append("bk=gesperrt") }
            if busy { params.append("wt=offen") }
            let loc = "/" + (params.isEmpty ? "" : "?" + params.joined(separator: "&"))
            return (HTTPResponse(status: 303, body: Data(), extraHeaders: ["Location": loc]), cmds)
        case ("POST", "/home"):
            // Welle F-e: ein Zug je Anfrage (Knopf oder Ziehen); Stand vom Fernseher, nicht vom Handy.
            let cmds = home.command(op: r.form["op"] ?? "").map { [$0] } ?? []
            let loc = "/?ok=\(cmds.isEmpty ? "home0" : "home")#order"
            return (HTTPResponse(status: 303, body: Data(), extraHeaders: ["Location": loc]), cmds)
        case ("POST", Self.nuvioPath):
            // plan_nuvio_konto T1: one sign-in per request. The answer never carries a value, also not on an error.
            let f = r.form
            let email = (f["email"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines), password = f["password"] ?? ""
            var cmds: [PhoneCommand] = []
            let loc: String
            if nuvio != .signedOut {
                loc = "/#nuvio"   // the form is not shown in this state: an old page sent it
            } else if email.isEmpty || password.isEmpty || email.count > Self.nuvioFieldLimit || password.count > Self.nuvioFieldLimit {
                loc = "/?nv=leer#nuvio"
            } else if backups.requestOpen {
                loc = "/?wt=offen#nuvio"   // as on /submit: the phone hears that a request already waits on the TV
            } else {
                cmds = [.nuvioSignIn(email: PhoneSecret(email), password: PhoneSecret(password))]
                loc = "/?nv=gesendet#nuvio"
            }
            return (HTTPResponse(status: 303, body: Data(), extraHeaders: ["Location": loc]), cmds)
        default:
            return (HTTPResponse(status: 404, body: Data(Self.html("Nicht gefunden", "").utf8)), [])
        }
    }

    /// Task 4.3: the page's answer to an imported look. `note` is the number of deviations from
    /// `LookPreset.baseline` or a failure code
    /// (`LookImport.Failure.code`), `unknown` the number of values this build did not know.
    static func lookText(_ note: String?, unknown: String?) -> String? {
        guard let note else { return nil }
        guard let n = Int(note) else {
            return note == LookImport.Failure.foreignSchema("").code
                ? "Aussehen nicht übernommen: die Datei hat ein fremdes Format, keine Aussehen-Datei aus dem Konfigurator."
                : "Aussehen nicht übernommen: keine lesbare Aussehen-Datei aus dem Konfigurator."
        }
        var t = "Aussehen übernommen · \(n) " + (n == 1 ? "Abweichung" : "Abweichungen")
        if let k = unknown.flatMap(Int.init), k > 0 {
            t += " · \(k) " + (k == 1 ? "Wert" : "Werte") + " kannte" + " diese App-Version nicht"
        }
        return t
    }

    static let sealedWaitBody = """
    <p>Am Fernseher „Erlauben“ wählen. Danach lädt diese Seite die verschlüsselte Datei von selbst \
    (<a href="\(sealedPath)">sonst hier tippen</a>).</p><p>Den Code (12 Zeichen in drei Vierergruppen, etwa K7QM-2XPA-9DRT) \
    zeigt nur der Fernseher; zum Wiederherstellen wird er dort eingegeben.</p>
    """

    /// Fix round 1: end of the sealed-export wait, without a refresh.
    static func sealedEnd(_ text: String) -> HTTPResponse {
        HTTPResponse(status: 200, body: Data(html("Sicherung", "<p>\(escape(text))</p><p><a href=\"/\">Zurück</a></p>").utf8))
    }

    func page(profileName: String, note: String?, importNote: String? = nil, lookNote: String? = nil,
              lookUnknown: String? = nil, home: PhoneHomeState = .empty,
              backupBlocked: Bool = false, requestWaiting: Bool = false,
              nuvio: PhoneNuvioState = .signedOut, nuvioNote: String? = nil) -> String {
        var msg: String
        switch note {
        case nil, "home", "home0": msg = ""   // Rückmeldung von „Startseite ordnen“ steht in dessen Abschnitt
        case "leer": msg = "<p class=ok>Nichts ausgefüllt.</p>"
        case let n?: msg = "<p class=ok>✓ \(Self.escape(n)) Eingabe(n) an den Fernseher geschickt. Ergebnis siehst du dort.</p>"
        }
        if let t = importNote.flatMap(PhoneImportDetect.noteText) { msg += "<p class=ok>\(Self.escape(t))</p>" }
        if let t = Self.lookText(lookNote, unknown: lookUnknown) { msg += "<p class=ok>\(Self.escape(t))</p>" }
        if backupBlocked { msg += "<p class=ok>\(Self.blockedText)</p>" }
        if requestWaiting { msg += "<p class=ok>\(Self.busyText)</p>" }
        func field(_ name: String, _ label: String, _ ph: String, area: Bool = false) -> String {
            area ? "<label>\(label)<textarea name=\(name) rows=4 placeholder=\"\(ph)\"></textarea></label>"
                 : "<label>\(label)<input name=\(name) autocapitalize=off autocorrect=off placeholder=\"\(ph)\"></label>"
        }
        func head(_ s: PhoneSection) -> String { "<h2>\(s.title)</h2>" }
        let backupPart = backupBlocked ? "<h3>Sicherung</h3><p class=hint>\(Self.blockedText)</p>" : """
        <h3>Sicherung</h3><p><a href="/export">Alle Profile ohne Schlüssel herunterladen (JSON)</a></p>
        <p><a href="/export?secrets=1">Alle Profile mit Schlüsseln herunterladen (verschlüsselt, Bestätigung am Fernseher)</a></p>
        <label>Sicherungsdatei wählen (.json oder .enc)<input type=file id=backupfile accept=".json,.enc,application/json,application/octet-stream"></label>
        \(field("backup_json", "Sicherung wiederherstellen (ersetzt alle Profile, Bestätigung am Fernseher)", "{…}", area: true))
        """
        let nav = PhoneSection.allCases.map { "<a href=\"#\($0.rawValue)\">\($0.title)</a>" }.joined(separator: " · ")
        let body = """
        \(msg)<nav>\(nav)</nav>
        <form method=post action="/submit">
        <section id=\(PhoneSection.quickImport.rawValue)>\(head(.quickImport))\(field("import", "Link oder Code einfügen – wird erkannt (Addon, TMDB-/Trakt-Liste, Widget-Export, Preview Pack, Collection-Export)", "https://…", area: true))</section>
        <section id=\(PhoneSection.addon.rawValue)>\(head(.addon))\(field("addon", "Addon hinzufügen: Manifest-URL", "https://…/manifest.json"))</section>
        <section id=\(PhoneSection.keys.rawValue)>\(head(.keys))\(field("key_tmdb", "TMDB-API-Key", ""))\(field("key_mdblist", "MDBList-Key", ""))
        \(field("key_trakt_id", "Trakt Client ID", ""))\(field("key_trakt_secret", "Trakt Client Secret", ""))\(field("key_simkl_id", "Simkl Client ID", ""))
        \(field("key_torbox", "TorBox-API-Key (Bibliothek „Meine TorBox-Dateien“)", ""))</section>
        <section id=\(PhoneSection.nuvio.rawValue)>\(head(.nuvio))\(nuvioSection(nuvio, note: nuvioNote))</section>
        <section id=\(PhoneSection.home.rawValue)>\(head(.home))<h3>Collections importieren</h3>
        \(field("nuvio_url", "Collection-Link: Widget-Export, Preview Pack oder Collection-Export (wird gemerkt, am Fernseher „Aktualisieren“)", "https://…json"))\(field("nuvio_json", "… oder den Code (JSON-Text) einfügen", "[…] oder {…}", area: true))
        \(field("tmdb_link", "TMDB- oder Trakt-Liste, Filmreihe, Studio als Reihe", "https://www.themoviedb.org/list/… oder https://trakt.tv/users/…/lists/…"))
        \(field("kit_url", "Fusion-Kit: „Copy JSON URL“ einfügen (braucht meist die Trakt Client ID)", "https://raw.githubusercontent.com/…json"))
        <p><a href="\(FusionKitCatalog.siteURL)">Kit-Katalog öffnen</a></p>
        \(orderSection(home, note: note))</section>
        <section id=\(PhoneSection.look.rawValue)>\(head(.look))\(field("look_json", "Aussehen aus dem Konfigurator: exportierte JSON-Datei einfügen (ändert nur das Aussehen des Profils)", "{…}", area: true))</section>
        <section id=\(PhoneSection.system.rawValue)>\(head(.system))\(field("key_atvloadly", "App-Update: atvloadly-Adresse (Pi)", "http://pi-name.local:5533"))
        \(field("key_playerlog", "Fern-Log: gemeinsames Geheimnis (dasselbe wie PLAYERLOG_SECRET am Log-Rechner)", ""))
        \(field("icon_set", "Eigener Bewertungs-Icon-Satz (JSON-Adresse, nur https)", "https://…/icons.json"))
        \(backupPart)</section>
        <button>An den Fernseher senden</button>
        </form>
        <form id=homeform method=post action="/home"></form>\(nuvio == .signedOut ? "<form id=nuvioform method=post action=\"\(Self.nuvioPath)\" autocomplete=off></form>" : "")
        <script>\(Self.orderScript)\(Self.fileScript)</script>
        """
        return Self.html("Player · \(Self.escape(profileName))", body)
    }

    /// plan_nuvio_konto T1: section „Nuvio-Konto“. The fields belong to the own form `nuvioform` (outside the main
    /// form, via `form=`), so „An den Fernseher senden“ never carries them. No field ever gets a `value`.
    func nuvioSection(_ state: PhoneNuvioState, note: String?) -> String {
        var out = ""
        switch note {
        case "gesendet": out += "<p class=ok>\(Self.nuvioSentText)</p>"
        case "leer": out += "<p class=ok>\(Self.nuvioEmptyText)</p>"
        default: break
        }
        switch state {
        case .signedOut:
            out += "<label>E-Mail<input form=nuvioform name=email type=\"email\" autocomplete=off autocapitalize=off autocorrect=off spellcheck=false></label>"
            out += "<label>Passwort<input form=nuvioform name=password type=\"password\" autocomplete=off></label>"
            out += "<p class=hint>\(Self.nuvioHintText) \(Self.nuvioRiskText)</p>"
            out += "<button form=nuvioform>Anmelden</button>"
        case .connected(let name):
            out += "<p>\(Self.nuvioConnectedText)</p>"
            if let name { out += "<p class=hint>Verbunden · \(Self.escape(name))</p>" }
        case .busy:
            out += "<p>\(Self.nuvioBusyText)</p>"
        }
        return out
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
        func button(_ op: String, _ sym: String, _ label: String, disabled: Bool = false, confirm: String? = nil) -> String {
            "<button form=homeform name=op value=\"\(Self.escape(op))\" aria-label=\"\(label)\" title=\"\(label)\"\(disabled ? " disabled" : "")"
                + (confirm.map { " data-confirm=\"\(Self.escape($0))\"" } ?? "") + ">\(sym)</button>"
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
                // Nur absolute Ziele: ein wiederholter Zug wirkt nicht doppelt.
                out += button("to:\(r.id):0", "⤒", "Ganz nach oben", disabled: i == 0)
                out += button("to:\(r.id):\(max(i - 1, 0))", "↑", "Nach oben", disabled: i == 0)
                out += button("to:\(r.id):\(min(i + 1, last))", "↓", "Nach unten", disabled: i == last)
                out += button("to:\(r.id):\(last)", "⤓", "Ganz nach unten", disabled: i == last)
                out += button("hide:\(r.id)", "✕", "Ausblenden")
                out += button("delete:\(r.id)", "🗑", "Löschen",
                              confirm: "„\(r.title)“ löschen? Die Reihe steht danach nicht unter „Ausgeblendet“.")
                out += "</span></li>"
            }
            out += "</ol>"
        }
        if !home.hidden.isEmpty {
            out += "<h3>Ausgeblendet (\(home.hidden.count))</h3><p class=hint>Kommt unverändert unten wieder an.</p><ul class=rows>"
            for r in home.hidden {
                out += "<li>\(text(r))<span class=btns>\(button("restore:\(r.id)", "↩", "Wieder einblenden"))</span></li>"
            }
            out += "</ul>"
        }
        if !home.more.isEmpty {
            out += "<details><summary>Weitere Reihen (\(home.more.count)) – hängt unten an</summary><ul class=rows>"
            for r in home.more {
                out += "<li>\(text(r))<span class=btns>\(button("show:\(r.id)", "＋", "Hinzufügen"))</span></li>"
            }
            out += "</ul></details>"
        }
        return out + "</div>"
    }

    /// Ziehen per Touch (Pointer-Events am Griff) und Knöpfe ohne Neuladen: Zug per fetch an /home,
    /// danach wird nur der Abschnitt `#order` aus der Antwortseite ersetzt. Während eines Zugs ist die Liste gesperrt;
    /// ein Fehler lädt die Seite neu, statt den Zug noch einmal zu senden.
    static let orderScript = """
    (function(){var f=document.getElementById('homeform');if(!f||!window.fetch)return;var busy=false;
    function reload(){location.replace('/?r='+Date.now()+'#order');}
    function send(op){if(busy)return;busy=true;var o=document.getElementById('order');if(o)o.classList.add('busy');
    fetch(f.action,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'op='+encodeURIComponent(op)})
    .then(function(r){if(!r.ok)throw 0;return r.text();}).then(function(h){var n=new DOMParser().parseFromString(h,'text/html').getElementById('order'),o=document.getElementById('order');
    if(!n||!o)throw 0;var d=o.querySelector('details'),open=d&&d.open;o.replaceWith(n);var d2=n.querySelector('details');if(d2&&open)d2.open=true;busy=false;bind();})
    .catch(function(){reload();});}
    function bind(){var o=document.getElementById('order');if(!o)return;
    o.querySelectorAll('button[name=op]').forEach(function(b){b.addEventListener('click',function(e){e.preventDefault();if(b.dataset.confirm&&!window.confirm(b.dataset.confirm))return;send(b.value);});});
    var list=document.getElementById('rowlist');if(!list)return;
    list.querySelectorAll('.grip').forEach(function(g){g.addEventListener('pointerdown',function(e){if(busy)return;var li=g.parentNode,kids=function(){return[].slice.call(list.children);},from=kids().indexOf(li),next=li.nextSibling;
    e.preventDefault();try{g.setPointerCapture(e.pointerId);}catch(x){}li.classList.add('drag');
    function move(ev){var y=ev.clientY,before=null,s=kids().filter(function(x){return x!==li;});
    for(var i=0;i<s.length;i++){var r=s[i].getBoundingClientRect();if(y<r.top+r.height/2){before=s[i];break;}}
    list.insertBefore(li,before);if(y<60)window.scrollBy(0,-12);else if(y>window.innerHeight-60)window.scrollBy(0,12);}
    function end(ev){g.removeEventListener('pointermove',move);g.removeEventListener('pointerup',end);g.removeEventListener('pointercancel',end);li.classList.remove('drag');
    if(ev.type==='pointercancel'){list.insertBefore(li,next);return;}var to=kids().indexOf(li);if(to!==from)send('to:'+li.getAttribute('data-id')+':'+to);}
    g.addEventListener('pointermove',move);g.addEventListener('pointerup',end);g.addEventListener('pointercancel',end);});});}
    bind();})();
    """

    /// Task 1.4: a chosen backup file goes as text into „Sicherung wiederherstellen“ (both formats are text).
    static let fileScript = """
    (function(){var i=document.getElementById('backupfile'),t=document.querySelector('textarea[name=backup_json]');if(!i||!t||!window.FileReader)return;
    i.addEventListener('change',function(){var f=i.files&&i.files[0];if(!f)return;var r=new FileReader();r.onload=function(){t.value=r.result;};r.readAsText(f);});})();
    """

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func html(_ title: String, _ body: String, refresh: Int? = nil) -> String {
        """
        <!doctype html><html lang=de><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer">\(refresh.map { "<meta http-equiv=\"refresh\" content=\"\($0);url=\(sealedPath)\">" } ?? "")
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
        summary{margin-top:12px;color:#ccc}.busy{pointer-events:none;opacity:.6}
        </style><h1>\(title)</h1>\(body)</html>
        """
    }
}
