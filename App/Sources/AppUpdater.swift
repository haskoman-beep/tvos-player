import Foundation
import Network
import CryptoKit
import PlayerCore

/// „App aktualisieren“: neuesten main-Build auf GitHub suchen und über atvloadly am Pi installieren lassen.
/// Logik/Parsing in PlayerCore (`AppUpdateClient`); hier nur Zustand, Bonjour-Suche und Log.
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    enum Phase: Equatable {
        case idle
        case checking
        case checked(UpdateState)
        case starting
        case installing(String)
        case done(String)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var searching = false
    @Published private(set) var addressNote: String?
    /// Zuletzt gefundenes installierbares Paket. Bleibt über Start, Installation und Fehler hinweg stehen,
    /// damit die Installieren-Zeile unter dem Fokus nicht verschwindet (F-B-6); neu gesetzt bei jeder Prüfung.
    @Published private(set) var offered: ReleaseBuild?

    /// Build dieser App (CI-Laufnummer, Commit, Branch aus der Info.plist).
    let current = AppBuildInfo(info: Bundle.main.infoDictionary)
    private let client = AppUpdateClient(accountID: AppUpdater.md5)
    private var poll: Task<Void, Never>?
    private var workstations: [String] = []

    private init() {}

    var busy: Bool {
        switch phase {
        case .checking, .starting, .installing: return true
        default: return false
        }
    }

    /// atvloadly will die Apple-ID als md5 (hex, klein) – der Klartext verlässt die App nicht.
    nonisolated static func md5(_ s: String) -> String {
        Insecure.MD5.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func text(_ error: Error) -> String {
        if let e = error as? AppUpdateError { return e.text }
        return AppUpdateLog.redact(error.localizedDescription)
    }

    // MARK: Suche

    func check() {
        guard !busy else { return }
        phase = .checking
        Task {
            do {
                let s = try await client.check(current: current)
                if case .available(let r, _) = s { offered = r } else { offered = nil }
                phase = .checked(s)
                RemoteLog.info("update", "Prüfung: installiert Build \(current.buildLabel) · \(Self.describe(s))")
            } catch {
                let m = Self.text(error)
                offered = nil
                phase = .failed(m)
                RemoteLog.error("update", "Prüfung fehlgeschlagen: \(m)")
            }
        }
    }

    private static func describe(_ s: UpdateState) -> String {
        switch s {
        case .upToDate(let b): return "aktuell (main \(b.number))"
        case .available(let r, let b):
            let n = r.number.map { String($0) } ?? "?"
            return "Paket Build \(n) verfügbar (main \(b.number) · \(b.shortCommit))"
        case .notPublished(let b): return "main \(b.number) ohne Paket im Release"
        case .newerInstalled(let main): return "installiert ist neuer als main (Build \(main))"
        }
    }

    // MARK: Installation

    func install(_ release: ReleaseBuild, base: URL) {
        guard !busy else { return }
        phase = .starting
        let bundleID = Bundle.main.bundleIdentifier ?? "de.haskoman.player"
        let n = release.number.map { String($0) } ?? "?"
        Task {
            do {
                let s = try await client.start(base: base, bundleID: bundleID, release: release)
                let way: String
                switch s.route {
                case .sourceUpdate: way = "Quelle"
                case .mcp: way = "MCP install_app"
                }
                let hash = release.sha256.map { " · SHA256 \($0.prefix(12))…" } ?? ""
                RemoteLog.info("update", "atvloadly übernimmt Build \(n)\(hash) über \(way) (Eintrag \(s.appID)): \(AppUpdateLog.redact(s.message))")
                phase = .installing("atvloadly installiert Build \(n) … Die App wird dabei beendet – danach neu öffnen.")
                watch(base: base, appID: s.appID, bundleID: bundleID, ipaURL: release.ipaURL)
            } catch {
                let m = Self.text(error)
                phase = .failed(m)
                RemoteLog.error("update", "Installation nicht gestartet: \(m)")
            }
        }
    }

    /// Alle 3 s nachsehen, ob atvloadly noch installiert (Auswertung: `InstallWatch`).
    /// Gelingt die Installation, beendet tvOS die App vorher.
    private func watch(base: URL, appID: Int, bundleID: String, ipaURL: URL) {
        poll?.cancel()
        poll = Task {
            var w = InstallWatch(appID: appID, bundleID: bundleID, ipaURL: ipaURL)
            let start = Date()
            var first = true
            while !Task.isCancelled {
                if !first { try? await Task.sleep(nanoseconds: 3_000_000_000) }
                first = false
                let outcome: InstallWatch.Outcome
                var detail = ""
                do {
                    let list = try await client.installing(base: base)
                    outcome = w.observe(list, elapsed: Date().timeIntervalSince(start))
                } catch {
                    detail = Self.text(error)
                    outcome = w.failed(elapsed: Date().timeIntervalSince(start))
                }
                guard outcome.isFinal, let text = outcome.text, !Task.isCancelled else { continue }
                phase = .failed(outcome == .unreachable && !detail.isEmpty ? "\(text) \(detail)" : text)
                RemoteLog.error("update", "Installation: \(text) \(detail) – App läuft mit Build \(current.buildLabel)")
                return
            }
        }
    }

    // MARK: atvloadly-Adresse

    /// Bonjour `_workstation._tcp` kurz durchsuchen und Rechner per `GET /api/version` prüfen.
    /// (atvloadly selbst meldet sich nicht per Bonjour; der Pi meldet sich als Workstation.)
    /// Gibt alle Treffer zurück und speichert nichts – die Seite lässt auswählen (SEC-11).
    func discover() async -> [AtvloadlyCandidate] {
        guard !searching else { return [] }
        searching = true
        addressNote = nil
        defer { searching = false }
        workstations = []
        let b = NWBrowser(for: .bonjour(type: "_workstation._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { results, _ in
            let names = results.compactMap { r -> String? in
                if case let .service(name, _, _, _) = r.endpoint { return name }
                return nil
            }
            Task { @MainActor in AppUpdater.shared.workstations = names }
        }
        b.start(queue: .main)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        b.cancel()
        let names = workstations
        let urls = AtvloadlyAddress.candidates(workstations: names)
        // Alle Prüfadressen gleichzeitig (je 4 s), Reihenfolge der Suche bleibt erhalten.
        let versions = await withTaskGroup(of: (Int, String?).self, returning: [String?].self) { group in
            for (i, u) in urls.enumerated() { group.addTask { (i, await AppUpdater.probe(u)) } }
            var out = [String?](repeating: nil, count: urls.count)
            for await (i, v) in group { out[i] = v }
            return out
        }
        let found = zip(urls, versions).compactMap { u, v -> AtvloadlyCandidate? in
            guard let v else { return nil }
            return AtvloadlyCandidate(name: u.host ?? u.absoluteString, url: u, version: v)
        }
        if !found.isEmpty {
            RemoteLog.info("update", "atvloadly-Suche: \(found.count) Treffer (\(names.count) Workstation(s))")
            return found
        }
        addressNote = names.isEmpty
            ? "Kein Rechner per Bonjour gefunden – Adresse über die Handy-Seite eintragen."
            : "Kein atvloadly unter \(names.count) Rechner(n) gefunden – Adresse über die Handy-Seite eintragen."
        RemoteLog.info("update", "atvloadly-Suche ohne Treffer (\(names.count) Workstation(s))")
        return []
    }

    /// Eingetragene Adresse prüfen (Hinweis unter dem Feld). Liegt sie nicht erkennbar im Heimnetz,
    /// steht davor eine Warnung (keine Sperre).
    func verify(_ base: URL) {
        let warn = AtvloadlyAddress.isHomeNetwork(base) ? "" : AtvloadlyAddress.notHomeWarning + ". "
        if !warn.isEmpty { RemoteLog.info("update", "atvloadly-Adresse außerhalb des Heimnetzes eingetragen") }
        addressNote = warn + "Prüfe …"
        Task {
            if let v = await Self.probe(base) { addressNote = warn + "atvloadly \(v) erreichbar" }
            else { addressNote = warn + "Unter dieser Adresse antwortet kein atvloadly." }
        }
    }

    /// Kurzer Test (4 s ohne Daten, 8 s insgesamt) über den gemeinsamen HTTPClient (Task 3.10), nie aus dem Cache.
    private nonisolated static func probe(_ base: URL) async -> String? {
        let r = URLRequest(url: base.appendingPathComponent("api/version"))
        let limits = HTTPLimits(requestTimeout: 4, resourceTimeout: 8, maxBytes: HTTPLimits.json.maxBytes)
        guard let res = try? await LimitedHTTPClient.shared.data(r, limits: limits, fresh: true) else { return nil }
        guard res.1.statusCode == 200 else { return nil }
        return try? Atvloadly.parseVersion(res.0)
    }
}
