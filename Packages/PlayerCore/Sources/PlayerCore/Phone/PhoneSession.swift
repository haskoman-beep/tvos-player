import Foundation

// Task 1.4 (SEC-1, SEC-5, SEC-16): who may talk to the phone page, how much it accepts, and what the TV confirms.

/// Limits of the phone server; checked on the request head, before a body is read.
public enum PhoneLimits {
    public static let maxConnections = 4
    /// Seconds per connection from accept to answer.
    public static let requestDeadline: TimeInterval = 10
    /// Request line plus headers.
    public static let maxHead = 64 * 1024

    public static func maxBody(for path: String) -> Int {
        switch path {
        case "/submit": 8 * 1024 * 1024   // backups and pasted collection code
        default: 16 * 1024                // "/home" (one move) and everything else
        }
    }
}

public enum PhoneAuth: Equatable, Sendable {
    /// The one-time address from the QR code was used: the answer sets this cookie (`Set-Cookie` value).
    case firstUse(setCookie: String)
    case ok
    case denied
}

/// Decision on a request head.
public enum PhoneAdmission: Equatable, Sendable {
    /// Answer now and close; the body is not read.
    case respond(HTTPResponse)
    /// Admitted: read this many body bytes, then hand the request to `PhoneInputPage`.
    case readBody(Int)
}

/// One phone session per QR code. Rules: the token in the QR address works exactly once and at most 10 minutes after the
/// code was shown; that first request gets a random session cookie bound to the address of that device; after it only
/// the cookie counts. The session ends 30 minutes after the first use or when the TV view closes (`end()`); then the TV
/// shows a new QR code (`needsNewCode`).
public struct PhoneSession: Sendable {
    public static let tokenLifetime: TimeInterval = 10 * 60
    public static let sessionLifetime: TimeInterval = 30 * 60
    public static let cookieName = "player_sitzung"

    public let token: String
    public let created: Date
    public private(set) var tokenUsed = false
    public private(set) var ended = false
    private var cookie: String?
    private var peer: String?
    private var started: Date?

    public init(token: String, now: Date) { self.token = token; self.created = now }

    /// `cookie` is the raw `Cookie` header, `peer` the address of the connecting device.
    public mutating func authorize(queryToken: String?, cookie header: String?, peer: String, now: Date) -> PhoneAuth {
        guard !ended else { return .denied }
        if let started, now.timeIntervalSince(started) >= Self.sessionLifetime { ended = true; return .denied }
        if let cookie, let sent = Self.cookieValue(header), Self.same(sent, cookie), peer == self.peer { return .ok }
        guard !tokenUsed, let q = queryToken, Self.same(q, token), now.timeIntervalSince(created) < Self.tokenLifetime else { return .denied }
        let c = Self.randomCookie()
        tokenUsed = true; cookie = c; self.peer = peer; started = now
        return .firstUse(setCookie: "\(Self.cookieName)=\(c); Path=/; Max-Age=\(Int(Self.sessionLifetime)); HttpOnly; SameSite=Lax")
    }

    /// Head first (SEC-5): body limit of the path, then access. Only `.readBody` lets the server read on.
    public mutating func admit(_ head: RequestHead, peer: String, now: Date) -> PhoneAdmission {
        guard head.contentLength <= PhoneLimits.maxBody(for: head.path) else {
            return .respond(HTTPResponse(status: 413, body: Data(PhoneInputPage.html("Zu groß", "<p>Die Eingabe ist zu groß.</p>").utf8)))
        }
        switch authorize(queryToken: head.query["t"], cookie: head.headers["cookie"], peer: peer, now: now) {
        case .denied:
            return .respond(HTTPResponse(status: 403, body: Data(PhoneInputPage.html("Kein Zugang",
                "<p>Diese Adresse gilt nicht mehr. Am Fernseher „Neuer QR-Code“ wählen und neu scannen.</p>").utf8)))
        case .firstUse(let set):
            // Token out of the address bar; the anchor (#home …) stays, browsers keep it across the redirect.
            var rest = head.query; rest["t"] = nil
            let q = rest.sorted { $0.key < $1.key }.map { "\(Self.formEscape($0.key))=\(Self.formEscape($0.value))" }.joined(separator: "&")
            let loc = head.method == "GET" ? head.path + (q.isEmpty ? "" : "?" + q) : "/"
            return .respond(HTTPResponse(status: 303, body: Data(), extraHeaders: ["Location": loc, "Set-Cookie": set]))
        case .ok:
            return .readBody(head.contentLength)
        }
    }

    public mutating func end() { ended = true }

    /// Someone is (or was) connected with this code.
    public var isConnected: Bool { tokenUsed && !ended }

    /// The QR code on the TV no longer opens anything.
    public func needsNewCode(now: Date) -> Bool {
        if ended { return true }
        if let started { return now.timeIntervalSince(started) >= Self.sessionLifetime }
        return now.timeIntervalSince(created) >= Self.tokenLifetime
    }

    public static func randomCookie() -> String {
        var g = SystemRandomNumberGenerator()
        let chars = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<32).map { _ in chars[Int(g.next() % UInt64(chars.count))] })
    }

    static func cookieValue(_ header: String?) -> String? {
        for part in (header ?? "").split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, kv[0] == cookieName { return kv[1] }
        }
        return nil
    }

    /// Comparison without an early exit on the first differing character.
    static func same(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        return zip(x, y).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    static func formEscape(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "" }
}

// MARK: Confirmation on the TV

extension PhoneCommand {
    public enum Sensitivity: Equatable, Sendable {
        case plain
        /// The TV shows `summary` with „Erlauben“ / „Ablehnen“ before the command runs.
        case needsConfirmation(summary: String)
    }

    /// Restoring a backup, adding an addon, setting a key (the atvloadly address and the remote-log secret included) and
    /// the export with secrets need a confirmation on the TV. The summary never shows a whole key.
    public var sensitivity: Sensitivity {
        switch self {
        case .addAddon(let u):
            let base = AddonClient.parseManifest(u)?.base ?? u
            let url = URL(string: base)
            let host = url?.host ?? "unbekannte Adresse"
            let plainHTTP = url?.scheme?.lowercased() == "http"
            return .needsConfirmation(summary: "Addon hinzufügen von \(host)"
                + (plainHTTP ? " – unverschlüsselt (http): die Adresse samt Zugangsdaten geht offen durchs WLAN." : ""))
        case .setKey(let s, let v):
            if s == AtvloadlyAddress.key {
                return .needsConfirmation(summary: "App-Update: atvloadly-Adresse setzen auf \(AtvloadlyAddress.normalize(v)?.host ?? "unbekannte Adresse")")
            }
            let label = Self.keyLabels[s] ?? s
            return .needsConfirmation(summary: "\(label) setzen" + (v.count >= 8 ? " (endet auf …\(v.suffix(2)))" : ""))
        case .importBackup(let d):
            if BackupCrypto.isSealed(d) {
                return .needsConfirmation(summary: "Verschlüsselte Sicherung wiederherstellen – ersetzt alle Profile. Code der Sicherung eingeben.")
            }
            guard let s = try? ProfileStore.decode(d) else {
                return .needsConfirmation(summary: "Sicherung wiederherstellen – die Datei ist nicht lesbar.")
            }
            let names = s.profiles.prefix(3).map(\.name).joined(separator: ", ") + (s.profiles.count > 3 ? ", …" : "")
            let noSecrets = s.profiles.allSatisfy { $0.apiKeys.isEmpty && $0.syncTokens.isEmpty }
            return .needsConfirmation(summary: "Sicherung wiederherstellen – ersetzt alle Profile durch \(s.profiles.count) Profil(e): \(names)."
                + (noSecrets ? " Sie enthält keine Schlüssel und Anmeldungen." : ""))
        case .exportSecrets:
            return .needsConfirmation(summary: "Sicherung mit allen Schlüsseln und Anmeldungen verschlüsselt an das Handy geben. Den Code zeigt danach nur der Fernseher.")
        case .importNuvioURL, .importNuvioJSON, .addTMDBLink, .importFusionURL, .moveRow, .removeRow, .deleteRow, .restoreRow, .addRow,
             .setRatingIconSet, .importCollectionLink, .importCollectionCode:
            return .plain
        }
    }

    /// A sealed backup: the TV asks for its code before it can restore it.
    public var needsBackupCode: Bool {
        if case .importBackup(let d) = self { return BackupCrypto.isSealed(d) }
        return false
    }

    static let keyLabels = ["tmdb": "TMDB-API-Key", "mdblist": "MDBList-Key", "trakt_id": "Trakt Client ID",
                            "trakt_secret": "Trakt Client Secret", "simkl_id": "Simkl Client ID", "torbox": "TorBox-API-Key",
                            LogSignature.secretKey: "Fern-Log-Geheimnis"]
}

/// An open request on the TV: what runs on „Erlauben“.
public struct PhoneConfirmation: Equatable, Sendable {
    public let commands: [PhoneCommand]
    public let summary: [String]
    public let expires: Date
    public var needsCode: Bool { commands.contains(where: \.needsBackupCode) }
}

extension PhoneConfirmation {
    /// Task 1.8: how an open request ended, for the log line `handy: Bestätigung <Art> <Ausgang>`.
    public enum Outcome: String, Sendable { case allowed = "erlaubt", declined = "abgelehnt", lapsed = "abgelaufen" }

    /// Short kind of the request: Addon, Schlüssel, Adresse (atvloadly), Import (restore a backup), Sicherung (export
    /// with keys); several kinds in their order joined with „+“. Never a value, host or key.
    public var logKind: String {
        var kinds: [String] = []
        for c in commands {
            let k: String
            switch c {
            case .addAddon: k = "Addon"
            case .setKey(let s, _): k = s == AtvloadlyAddress.key ? "Adresse" : "Schlüssel"
            case .importBackup: k = "Import"
            case .exportSecrets: k = "Sicherung"
            default: k = "Befehl"
            }
            if !kinds.contains(k) { kinds.append(k) }
        }
        return kinds.isEmpty ? "Befehl" : kinds.joined(separator: "+")
    }

    /// The message part after the category `handy`.
    public func logLine(_ outcome: Outcome) -> String { "Bestätigung \(logKind) \(outcome.rawValue)" }
}

/// Only one open request at a time; it lapses after 60 s without an answer.
public struct PhoneConfirmGate: Sendable {
    public static let lifetime: TimeInterval = 60
    private var pending: PhoneConfirmation?

    public init() {}

    /// Plain commands come back to run now; sensitive ones become the open request, or are refused while one is open.
    public mutating func offer(_ commands: [PhoneCommand], now: Date) -> (plain: [PhoneCommand], refused: [PhoneCommand]) {
        var plain: [PhoneCommand] = [], sensitive: [PhoneCommand] = [], summary: [String] = []
        for c in commands {
            if case .needsConfirmation(let s) = c.sensitivity { sensitive.append(c); summary.append(s) } else { plain.append(c) }
        }
        guard !sensitive.isEmpty else { return (plain, []) }
        if current(now: now) != nil { return (plain, sensitive) }
        pending = PhoneConfirmation(commands: sensitive, summary: summary, expires: now.addingTimeInterval(Self.lifetime))
        return (plain, [])
    }

    public mutating func current(now: Date) -> PhoneConfirmation? {
        if let p = pending, now >= p.expires { pending = nil }
        return pending
    }

    /// Ends the open request; its commands if allowed in time, otherwise nothing.
    public mutating func resolve(allow: Bool, now: Date) -> [PhoneCommand] {
        guard let p = current(now: now) else { return [] }
        pending = nil
        return allow ? p.commands : []
    }
}
