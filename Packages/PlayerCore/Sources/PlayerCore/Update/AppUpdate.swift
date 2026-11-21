import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// „App aktualisieren“: neuesten erfolgreichen main-Build auf GitHub erkennen und über atvloadly (Pi) installieren.
//
// Ablauf: Die CI (build.yml) stempelt Laufnummer/Commit/Branch in die Info.plist und legt das IPA auf main
// zusätzlich in das öffentliche Release `app-main` (das Actions-Artefakt „Player-ipa“ braucht zum Laden eine
// Anmeldung und ist gezippt – atvloadly kann es nicht laden). Die App fragt die Actions-API nach dem letzten
// erfolgreichen main-Lauf, vergleicht mit dem eigenen Commit und lässt atvloadly das Release-IPA installieren:
// über die REST-Quelle (`POST /api/apps/{id}/source/update`), wenn der Eintrag am Pi mit dem Repo verknüpft ist,
// sonst über das MCP-Werkzeug `install_app` (läuft am Pi als Hintergrundaufgabe weiter, wenn die App beim
// Installieren beendet wird). Keine Änderung am Pi nötig.

// MARK: - Eigener Build

/// Build-Stand dieser App aus der Info.plist. Die CI setzt CFBundleVersion = Laufnummer, dazu Commit und Branch.
public struct AppBuildInfo: Sendable, Equatable {
    public var version: String
    /// CI-Laufnummer (`github.run_number`); bei lokalem Build ohne CI der Standardwert 1.
    public var build: Int?
    /// Voller Commit (klein geschrieben); leer = Build ohne CI-Angaben.
    public var commit: String
    public var branch: String

    public init(version: String, build: Int?, commit: String, branch: String) {
        self.version = version; self.build = build; self.commit = commit.lowercased(); self.branch = branch
    }

    /// Aus `Bundle.main.infoDictionary`. Nicht ersetzte Platzhalter `$(…)` gelten als leer.
    public init(info: [String: Any]?) {
        func s(_ k: String) -> String {
            let v = (info?[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return v.hasPrefix("$(") ? "" : v
        }
        self.init(version: s("CFBundleShortVersionString"), build: Int(s("CFBundleVersion")),
                  commit: s("PlayerBuildCommit"), branch: s("PlayerBuildBranch"))
    }

    public var shortCommit: String { String(commit.prefix(7)) }

    /// „40 · main · e293096“; ohne CI-Angaben „1 (ohne CI)“.
    public var buildLabel: String {
        let b = build.map(String.init) ?? "?"
        guard !commit.isEmpty else { return "\(b) (ohne CI)" }
        return ([b] + (branch.isEmpty ? [] : [branch]) + [shortCommit]).joined(separator: " · ")
    }
}

// MARK: - GitHub (öffentliches Repo, ohne Anmeldung: 60 Anfragen/Stunde)

/// Ein erfolgreicher CI-Lauf auf main.
public struct CIBuild: Sendable, Equatable {
    public var number: Int
    public var commit: String
    public var date: Date?
    public init(number: Int, commit: String, date: Date? = nil) {
        self.number = number; self.commit = commit.lowercased(); self.date = date
    }
    public var shortCommit: String { String(commit.prefix(7)) }
}

/// Installationspaket im Release `app-main` (Text der CI: „Build 40 · Commit <sha> · Branch main“).
public struct ReleaseBuild: Sendable, Equatable {
    public var number: Int?
    public var commit: String?
    public var ipaURL: URL
    public var size: Int
    public init(number: Int?, commit: String?, ipaURL: URL, size: Int = 0) {
        self.number = number; self.commit = commit?.lowercased(); self.ipaURL = ipaURL; self.size = size
    }
}

public enum GitHubBuilds {
    public static let repo = "haskoman-beep/tvos-player"
    public static let branch = "main"
    public static let workflow = "build.yml"
    public static let releaseTag = "app-main"
    public static let ipaName = "Player.ipa"

    public static var latestRunURL: URL {
        URL(string: "https://api.github.com/repos/\(repo)/actions/workflows/\(workflow)/runs?branch=\(branch)&status=success&per_page=1")!
    }
    public static var releaseURL: URL { URL(string: "https://api.github.com/repos/\(repo)/releases/tags/\(releaseTag)")! }
    public static let headers = ["Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "Player-tvOS"]

    private struct Runs: Decodable {
        struct Run: Decodable {
            let run_number: Int
            let head_sha: String
            let head_branch: String?
            let conclusion: String?
            let created_at: String?
        }
        let workflow_runs: [Run]
    }

    private struct Release: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: String; let size: Int? }
        let name: String?
        let body: String?
        let draft: Bool?
        let assets: [Asset]
    }

    /// Neuester erfolgreicher main-Lauf aus `…/actions/workflows/build.yml/runs`.
    public static func parseLatestRun(_ data: Data) -> CIBuild? {
        guard let runs = try? JSONDecoder().decode(Runs.self, from: data) else { return nil }
        guard let r = runs.workflow_runs.first(where: { ($0.conclusion ?? "success") == "success" && ($0.head_branch ?? branch) == branch }),
              !r.head_sha.isEmpty else { return nil }
        return CIBuild(number: r.run_number, commit: r.head_sha, date: r.created_at.flatMap(parseDate))
    }

    /// Release `app-main` mit dem Asset `Player.ipa`; nil, wenn das Asset fehlt.
    public static func parseRelease(_ data: Data) -> ReleaseBuild? {
        guard let rel = try? JSONDecoder().decode(Release.self, from: data), rel.draft != true,
              let a = rel.assets.first(where: { $0.name == ipaName }), let url = URL(string: a.browser_download_url) else { return nil }
        let notes = rel.body ?? ""
        let number = token(after: "Build ", in: notes, \.isNumber).flatMap { Int($0) }
            ?? token(after: "Build ", in: rel.name ?? "", \.isNumber).flatMap { Int($0) }
        let commit = token(after: "Commit ", in: notes, \.isHexDigit).flatMap { $0.count >= 7 ? $0 : nil }
        return ReleaseBuild(number: number, commit: commit, ipaURL: url, size: a.size ?? 0)
    }

    static func token(after key: String, in s: String, _ allowed: (Character) -> Bool) -> String? {
        guard let r = s.range(of: key) else { return nil }
        let t = s[r.upperBound...].prefix(while: allowed)
        return t.isEmpty ? nil : String(t)
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

/// Ergebnis der Suche nach einem neuen Build.
public enum UpdateState: Sendable, Equatable {
    /// Installiert ist schon der Stand des neuesten main-Builds.
    case upToDate(CIBuild)
    /// Release-Paket installierbar; `latest` ist der neueste erfolgreiche main-Lauf.
    case available(ReleaseBuild, latest: CIBuild)
    /// Neuester Lauf hat (noch) kein passendes Paket im Release `app-main`.
    case notPublished(CIBuild)

    public static func decide(current: AppBuildInfo, latest: CIBuild, release: ReleaseBuild?) -> UpdateState {
        if sameCommit(current.commit, latest.commit) { return .upToDate(latest) }
        guard let release, let rc = release.commit else { return .notPublished(latest) }
        // Paket ist der installierte Stand, der neuere Lauf ist noch nicht veröffentlicht.
        if sameCommit(current.commit, rc) { return .notPublished(latest) }
        return .available(release, latest: latest)
    }

    /// Commits gleich (auch gekürzt, mindestens 7 Zeichen). Leer = unbekannt = nie gleich.
    public static func sameCommit(_ a: String, _ b: String) -> Bool {
        let a = a.lowercased(), b = b.lowercased()
        guard min(a.count, b.count) >= 7 else { return false }
        return a.hasPrefix(b) || b.hasPrefix(a)
    }
}

// MARK: - atvloadly-Adresse

public enum AtvloadlyAddress {
    /// Schlüssel in `Profile.apiKeys` (Handy-Seite `key_atvloadly`).
    public static let key = "atvloadly"
    public static let defaultPort = 5533
    /// Standard-Hostname eines Raspberry Pi OS (nur als Probe bei der Suche).
    public static let fallbackHosts = ["raspberrypi.local"]

    /// Eingabe → Basisadresse. Ohne Schema `http://`, ohne Port bei http 5533, ohne Schrägstrich am Ende.
    public static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(" ") else { return nil }
        if !s.contains("://") { s = "http://" + s }
        guard var c = URLComponents(string: s), let scheme = c.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = c.host, !host.isEmpty else { return nil }
        c.scheme = scheme
        if c.port == nil && scheme == "http" { c.port = defaultPort }
        var path = c.path
        while path.hasSuffix("/") { path.removeLast() }
        c.path = path
        c.query = nil
        c.fragment = nil
        return c.url
    }

    /// Bonjour `_workstation._tcp`-Name („raspberrypi [aa:bb:…]“) → „raspberrypi.local“.
    public static func host(fromWorkstation name: String) -> String? {
        var n = name
        if let b = n.range(of: " [") { n = String(n[..<b.lowerBound]) }
        n = n.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        return n + ".local"
    }

    /// Prüfadressen: gefundene Rechner zuerst, dann die Standard-Namen; ohne Doppelte.
    public static func candidates(workstations: [String]) -> [URL] {
        var seen = Set<String>(), out: [URL] = []
        for h in workstations.compactMap(host(fromWorkstation:)) + fallbackHosts {
            guard seen.insert(h.lowercased()).inserted, let u = normalize(h) else { continue }
            out.append(u)
        }
        return out
    }
}

// MARK: - atvloadly-REST (Antworten `{"code":200,"msg":"success","data":…}`)

public struct AtvloadlyApp: Sendable, Equatable {
    public var id: Int
    public var bundleID: String
    public var version: String
    public var udid: String
    /// Apple-ID des Eintrags – nie loggen oder anzeigen.
    public var account: String
    public var ipaPath: String
    public var enabled: Bool
    public var sourceKind: String
    public var sourceURL: String
    public init(id: Int, bundleID: String, version: String = "", udid: String = "", account: String = "", ipaPath: String = "",
                enabled: Bool = true, sourceKind: String = "", sourceURL: String = "") {
        self.id = id; self.bundleID = bundleID; self.version = version; self.udid = udid; self.account = account
        self.ipaPath = ipaPath; self.enabled = enabled; self.sourceKind = sourceKind; self.sourceURL = sourceURL
    }
}

public struct AtvloadlyDevice: Sendable, Equatable {
    public var id: String
    public var name: String
    public var udid: String
    public init(id: String, name: String, udid: String) { self.id = id; self.name = name; self.udid = udid }
}

public enum AppUpdateError: Error, Equatable, Sendable {
    case noAddress
    case github(Int)
    case noBuild
    case http(Int)
    case invalidResponse
    case atvloadly(String)
    case noApp
    case noDevice
    case noAccount
    case busy
    case needsChoice(String)
    case mcp(String)

    /// Text für Einstellungen/Log (ohne Konten oder Schlüssel).
    public var text: String {
        switch self {
        case .noAddress: return "atvloadly-Adresse fehlt (Handy-Seite oder „Pi im Netz suchen“)."
        case .github(let s) where s == 403 || s == 429: return "GitHub-Abfragegrenze erreicht (60 pro Stunde) – später erneut versuchen."
        case .github(let s): return "GitHub antwortet mit \(s)."
        case .noBuild: return "Kein erfolgreicher main-Build gefunden."
        case .http(let s): return "atvloadly antwortet mit HTTP \(s)."
        case .invalidResponse: return "Unerwartete Antwort von atvloadly."
        case .atvloadly(let m): return "atvloadly: \(AppUpdateLog.redact(m))"
        case .noApp: return "Player ist in atvloadly nicht eingetragen – einmal über die atvloadly-Seite installieren."
        case .noDevice: return "Das Apple TV ist in atvloadly gerade nicht verbunden."
        case .noAccount: return "Der atvloadly-Eintrag hat kein Apple-Konto."
        case .busy: return "atvloadly installiert die App bereits."
        case .needsChoice(let s): return "atvloadly verlangt eine Auswahl (\(s)) – bitte über die atvloadly-Seite installieren."
        case .mcp(let m): return "atvloadly-MCP: \(AppUpdateLog.redact(m))"
        }
    }
}

public enum Atvloadly {
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let msg: String?; let data: T? }
    private struct Version: Decodable { let version: String }
    private struct RawApp: Decodable {
        struct Source: Decodable { let kind: String?; let url: String? }
        let ID: Int
        let bundle_identifier: String?
        let version: String?
        let udid: String?
        let account: String?
        let ipa_path: String?
        let enabled: Bool?
        let source: Source?
    }
    private struct RawDevice: Decodable { let id: String; let name: String?; let udid: String? }
    private struct SourceUpdate: Decodable { let status: String?; let version: String?; let build_name: String? }

    private static func payload<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        guard let e = try? JSONDecoder().decode(Envelope<T>.self, from: data) else { throw AppUpdateError.invalidResponse }
        guard e.code == 200 else { throw AppUpdateError.atvloadly(e.msg ?? "Fehler \(e.code)") }
        guard let d = e.data else { throw AppUpdateError.invalidResponse }
        return d
    }

    /// `GET /api/version` → „v0.8.5“.
    public static func parseVersion(_ data: Data) throws -> String { try payload(Version.self, data).version }

    /// `GET /api/apps` bzw. `GET /api/apps/installing`.
    public static func parseApps(_ data: Data) throws -> [AtvloadlyApp] {
        try payload([RawApp].self, data).map {
            AtvloadlyApp(id: $0.ID, bundleID: $0.bundle_identifier ?? "", version: $0.version ?? "", udid: $0.udid ?? "",
                         account: $0.account ?? "", ipaPath: $0.ipa_path ?? "", enabled: $0.enabled ?? true,
                         sourceKind: $0.source?.kind ?? "", sourceURL: $0.source?.url ?? "")
        }
    }

    /// `GET /api/devices`.
    public static func parseDevices(_ data: Data) throws -> [AtvloadlyDevice] {
        try payload([RawDevice].self, data).map { AtvloadlyDevice(id: $0.id, name: $0.name ?? "", udid: $0.udid ?? "") }
    }

    /// `POST /api/apps/{id}/source/update` → „0.4.0 (Player Build 40)“.
    public static func parseSourceUpdate(_ data: Data) throws -> String {
        let r = try payload(SourceUpdate.self, data)
        guard r.status == "installing" else { throw AppUpdateError.atvloadly(r.status ?? "ohne Status") }
        return [r.version, r.build_name.map { "(\($0))" }].compactMap { $0 }.filter { !$0.isEmpty && $0 != "()" }.joined(separator: " ")
    }

    /// Repo-Angabe einer Quelle („owner/repo“, „https://github.com/owner/repo/…“) → „owner/repo“ klein.
    public static func repoSlug(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for p in ["https://", "http://", "www.", "github.com/"] where t.hasPrefix(p) { t.removeFirst(p.count) }
        let parts = t.split(separator: "/").prefix(2).map(String.init)
        guard parts.count == 2 else { return t }
        let repo = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
        return parts[0] + "/" + repo
    }

    /// Läuft für diese App gerade eine Installation? (MCP-Einträge haben noch keine ID/Bundle-ID, nur die IPA-Adresse.)
    public static func isInstalling(_ installing: [AtvloadlyApp], appID: Int?, bundleID: String, ipaURL: URL?) -> Bool {
        installing.contains { a in
            (appID != nil && a.id == appID) || (!a.bundleID.isEmpty && a.bundleID == bundleID)
                || (ipaURL != nil && a.ipaPath == ipaURL?.absoluteString)
        }
    }
}

/// Weg der Installation.
public enum InstallRoute: Sendable, Equatable {
    /// Eintrag ist mit dem GitHub-Repo verknüpft: atvloadly lädt das neueste Release selbst.
    case sourceUpdate(appID: Int)
    /// MCP `install_app` mit Gerät und Konto des bestehenden Eintrags (ersetzt dessen IPA).
    case mcp(deviceID: String, account: String)

    /// Bestehenden Eintrag dieser App wählen und den Weg bestimmen.
    public static func plan(apps: [AtvloadlyApp], devices: [AtvloadlyDevice], bundleID: String,
                            repo: String = GitHubBuilds.repo) throws -> (app: AtvloadlyApp, route: InstallRoute) {
        let mine = apps.filter { $0.bundleID == bundleID }
        guard !mine.isEmpty else { throw AppUpdateError.noApp }
        let udids = Set(devices.map(\.udid))
        func linked(_ a: AtvloadlyApp) -> Bool { a.sourceKind == "github" && Atvloadly.repoSlug(a.sourceURL) == repo.lowercased() }
        // Verbundenes Gerät vor allem, dann aktiv, dann verknüpft, dann neuester Eintrag.
        let app = mine.max { a, b in
            func rank(_ x: AtvloadlyApp) -> [Int] { [udids.contains(x.udid) ? 1 : 0, x.enabled ? 1 : 0, linked(x) ? 1 : 0, x.id] }
            return rank(a).lexicographicallyPrecedes(rank(b))
        }!
        if linked(app) { return (app, .sourceUpdate(appID: app.id)) }
        guard let dev = devices.first(where: { $0.udid == app.udid }) else { throw AppUpdateError.noDevice }
        guard !app.account.isEmpty else { throw AppUpdateError.noAccount }
        return (app, .mcp(deviceID: dev.id, account: app.account))
    }
}

// MARK: - atvloadly-MCP (Streamable HTTP, JSON-RPC; Antwort als JSON oder SSE)

public enum AtvloadlyMCP {
    public static let protocolVersion = "2025-06-18"
    public static let accept = "application/json, text/event-stream"

    private struct RPC<P: Encodable>: Encodable {
        let jsonrpc = "2.0"
        let id: Int?
        let method: String
        let params: P?
    }
    private struct Empty: Encodable {}
    private struct ClientInfo: Encodable { let name: String; let version: String }
    private struct InitParams: Encodable {
        let protocolVersion: String
        let capabilities: [String: String]
        let clientInfo: ClientInfo
    }
    private struct Call<A: Encodable>: Encodable { let name: String; let arguments: A }
    private struct InstallArgs: Encodable {
        let ipa_url: String
        let device_id: String
        let account_id: String
    }

    private static func encode<P: Encodable>(_ r: RPC<P>) -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(r)) ?? Data()
    }

    public static func initialize(id: Int, client: String, version: String) -> Data {
        encode(RPC(id: id, method: "initialize",
                   params: InitParams(protocolVersion: protocolVersion, capabilities: [:], clientInfo: ClientInfo(name: client, version: version))))
    }

    public static func initialized() -> Data { encode(RPC<Empty>(id: nil, method: "notifications/initialized", params: nil)) }

    /// `install_app`; `accountID` = md5 (hex, klein) der Apple-ID des Eintrags.
    public static func installApp(id: Int, ipaURL: URL, deviceID: String, accountID: String) -> Data {
        encode(RPC(id: id, method: "tools/call",
                   params: Call(name: "install_app", arguments: InstallArgs(ipa_url: ipaURL.absoluteString, device_id: deviceID, account_id: accountID))))
    }

    public static func callTool(id: Int, name: String) -> Data {
        encode(RPC(id: id, method: "tools/call", params: Call(name: name, arguments: Empty())))
    }

    /// JSON-RPC-Nachrichten im Körper: ein JSON-Objekt oder SSE-Ereignisse (`data:`-Zeilen).
    static func messages(_ body: Data) -> [[String: Any]] {
        guard let text = String(data: body, encoding: .utf8) else { return [] }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            return [(try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any]].compactMap { $0 }
        }
        var out: [[String: Any]] = [], data: [String] = []
        func flush() {
            if !data.isEmpty, let o = (try? JSONSerialization.jsonObject(with: Data(data.joined(separator: "\n").utf8))) as? [String: Any] {
                out.append(o)
            }
            data = []
        }
        // „\r\n“ ist in Swift ein einziges Zeichen – daher nach isNewline trennen (LF, CRLF und CR).
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("data:") {
                var v = line.dropFirst(5)
                if v.hasPrefix(" ") { v = v.dropFirst() }
                data.append(String(v))
            }
        }
        flush()
        return out
    }

    /// `result` der Antwort mit dieser ID; JSON-RPC-Fehler werfen `.mcp`.
    static func result(_ body: Data, id: Int) throws -> [String: Any] {
        for m in messages(body) {
            guard let mid = m["id"] as? Int, mid == id else { continue }
            if let e = m["error"] as? [String: Any] { throw AppUpdateError.mcp(e["message"] as? String ?? "Fehler") }
            if let r = m["result"] as? [String: Any] { return r }
        }
        throw AppUpdateError.invalidResponse
    }

    /// Ausgehandelte Protokollversion aus der `initialize`-Antwort.
    public static func negotiatedVersion(_ body: Data, id: Int) throws -> String {
        (try result(body, id: id)["protocolVersion"] as? String) ?? protocolVersion
    }

    /// Ergebnis eines Werkzeugaufrufs (nur Status/Meldung – Konto-/Geräteangaben bleiben unbeachtet).
    public struct ToolResult: Sendable, Equatable {
        public var isError: Bool
        public var text: String
        public var status: String?
        public var message: String?
        public var inProgress: Bool?
    }

    public static func toolResult(_ body: Data, id: Int) throws -> ToolResult {
        let r = try result(body, id: id)
        let text = ((r["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        let s = r["structuredContent"] as? [String: Any] ?? [:]
        return ToolResult(isError: r["isError"] as? Bool ?? false, text: text,
                          status: (s["status"] as? String) ?? (s["install_state"] as? String),
                          message: s["message"] as? String, inProgress: s["install_in_progress"] as? Bool)
    }

    /// `install_app`-Ergebnis prüfen: nur „installing“ ist ein Start.
    public static func checkInstall(_ r: ToolResult) throws -> String {
        if r.isError { throw AppUpdateError.mcp(r.text) }
        switch r.status {
        case "installing": return r.message ?? "installing"
        case let s? where s.hasPrefix("require_"): throw AppUpdateError.needsChoice(s)
        default: throw AppUpdateError.mcp(r.status ?? r.text)
        }
    }
}

// MARK: - Log

public enum AppUpdateLog {
    /// Wörter mit „@“ (E-Mail) oder 32 Hex-Zeichen (md5 der Apple-ID) durch „…“ ersetzen.
    public static func redact(_ s: String) -> String {
        s.split(separator: " ", omittingEmptySubsequences: false).map { w -> String in
            let core = w.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;()[]\"'"))
            if core.contains("@") || (core.count == 32 && core.allSatisfy(\.isHexDigit)) { return "…" }
            return String(w)
        }.joined(separator: " ")
    }
}

// MARK: - Ablauf (Netz über APISending, in Tests ersetzbar)

public struct AppUpdateClient: Sendable {
    public let http: any APISending
    /// md5 (hex, klein) der Apple-ID – kommt aus der App (CryptoKit), PlayerCore bleibt ohne Krypto.
    public let accountID: @Sendable (String) -> String

    public init(http: any APISending = URLSessionSender(), accountID: @escaping @Sendable (String) -> String) {
        self.http = http; self.accountID = accountID
    }

    // GitHub

    public func check(current: AppBuildInfo) async throws -> UpdateState {
        let runs = try await http.sendFull(APIRequest(url: GitHubBuilds.latestRunURL, headers: GitHubBuilds.headers))
        guard runs.status == 200 else { throw AppUpdateError.github(runs.status) }
        guard let latest = GitHubBuilds.parseLatestRun(runs.data) else { throw AppUpdateError.noBuild }
        let rel = try await http.sendFull(APIRequest(url: GitHubBuilds.releaseURL, headers: GitHubBuilds.headers))
        guard rel.status == 200 || rel.status == 404 else { throw AppUpdateError.github(rel.status) }
        return UpdateState.decide(current: current, latest: latest, release: rel.status == 200 ? GitHubBuilds.parseRelease(rel.data) : nil)
    }

    // atvloadly

    private func get(_ base: URL, _ path: String) async throws -> Data {
        let r = try await http.sendFull(APIRequest(url: base.appendingPathComponent(path)))
        guard (200..<300).contains(r.status) else { throw AppUpdateError.http(r.status) }
        return r.data
    }

    /// `GET /api/version` – zum Prüfen einer Adresse.
    public func version(base: URL) async throws -> String { try Atvloadly.parseVersion(try await get(base, "api/version")) }

    public func installing(base: URL) async throws -> [AtvloadlyApp] { try Atvloadly.parseApps(try await get(base, "api/apps/installing")) }

    public struct Started: Sendable, Equatable {
        public var route: InstallRoute
        public var appID: Int
        public var message: String
    }

    /// Installation des Release-Pakets anstoßen. Kehrt zurück, sobald atvloadly die Aufgabe angenommen hat.
    public func start(base: URL, bundleID: String, release: ReleaseBuild) async throws -> Started {
        let busy = try await installing(base: base)
        if Atvloadly.isInstalling(busy, appID: nil, bundleID: bundleID, ipaURL: release.ipaURL) { throw AppUpdateError.busy }
        let apps = try Atvloadly.parseApps(try await get(base, "api/apps"))
        let devices = try Atvloadly.parseDevices(try await get(base, "api/devices"))
        let (app, route) = try InstallRoute.plan(apps: apps, devices: devices, bundleID: bundleID)
        if Atvloadly.isInstalling(busy, appID: app.id, bundleID: bundleID, ipaURL: nil) { throw AppUpdateError.busy }
        switch route {
        case .sourceUpdate(let id):
            let r = try await http.sendFull(APIRequest(method: "POST", url: base.appendingPathComponent("api/apps/\(id)/source/update"),
                                                       headers: ["Content-Type": "application/json"], body: Data("{}".utf8)))
            guard (200..<300).contains(r.status) else { throw AppUpdateError.http(r.status) }
            return Started(route: route, appID: app.id, message: try Atvloadly.parseSourceUpdate(r.data))
        case .mcp(let deviceID, let account):
            let msg = try await mcpInstall(base: base, ipaURL: release.ipaURL, deviceID: deviceID, accountID: accountID(account))
            return Started(route: route, appID: app.id, message: msg)
        }
    }

    private func mcpInstall(base: URL, ipaURL: URL, deviceID: String, accountID: String) async throws -> String {
        let url = base.appendingPathComponent("mcp")
        var h = ["Content-Type": "application/json", "Accept": AtvloadlyMCP.accept]
        let ini = try await http.sendFull(APIRequest(method: "POST", url: url, headers: h,
                                                     body: AtvloadlyMCP.initialize(id: 1, client: "player-tvos", version: SyncAppInfo.version)))
        guard ini.status == 200 else { throw AppUpdateError.http(ini.status) }
        guard let session = ini.headers["mcp-session-id"], !session.isEmpty else { throw AppUpdateError.invalidResponse }
        h["Mcp-Session-Id"] = session
        let outcome: Result<String, any Error>
        do {
            h["Mcp-Protocol-Version"] = try AtvloadlyMCP.negotiatedVersion(ini.data, id: 1)
            let note = try await http.sendFull(APIRequest(method: "POST", url: url, headers: h, body: AtvloadlyMCP.initialized()))
            guard (200..<300).contains(note.status) else { throw AppUpdateError.http(note.status) }
            let call = try await http.sendFull(APIRequest(method: "POST", url: url, headers: h,
                                                          body: AtvloadlyMCP.installApp(id: 2, ipaURL: ipaURL, deviceID: deviceID, accountID: accountID)))
            guard call.status == 200 else { throw AppUpdateError.http(call.status) }
            outcome = .success(try AtvloadlyMCP.checkInstall(try AtvloadlyMCP.toolResult(call.data, id: 2)))
        } catch {
            outcome = .failure(error)
        }
        // Sitzung schließen; die Installation läuft am Pi unabhängig davon weiter.
        _ = try? await http.sendFull(APIRequest(method: "DELETE", url: url, headers: ["Mcp-Session-Id": session]))
        return try outcome.get()
    }
}
