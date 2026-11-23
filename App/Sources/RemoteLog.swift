import Foundation
import Network
import os
import PlayerCore
import UIKit

/// Ereignis-Log: os_log, Verlauf auf dem Gerät (`LogRing`, Caches/log-ring.json, alle 30 s) und – nur wenn
/// eingeschaltet – Sendung an den am Fernseher gewählten Log-Empfänger im Heimnetz (Bonjour `_playerlog._tcp`).
/// Task 1.5 (SEC-2): Fern-Log standardmäßig aus; gesendet wird nur an den Dienstnamen aus den Geräte-Einstellungen,
/// jede Sendung trägt `X-Player-Sig` (HMAC-SHA256 mit dem Geheimnis von der Handy-Seite). Bis zur Sendung bleiben
/// die letzten 500 Zeilen im Speicher.
@MainActor
final class RemoteLog {
    static let shared = RemoteLog()
    private let os = Logger(subsystem: "de.haskoman.player", category: "app")
    private var pending: [LogLine] = []
    private var ring: LogRing
    private var ringDirty = false
    private let ringURL: URL?
    private var browser: NWBrowser?
    /// Angekündigte Empfänger nach Dienstname.
    private var found: [String: NWEndpoint] = [:]
    private var enabled = false
    private var receiver: String?
    private var secret: String?
    private var sending = false
    private let session = String(UUID().uuidString.prefix(8))
    private let iso = ISO8601DateFormatter()

    private init() {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(LogRing.fileName)
        ringURL = url
        ring = Self.loadRing(url)
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in Task { @MainActor in RemoteLog.shared.flush() } }
        Timer.scheduledTimer(withTimeInterval: LogRing.saveInterval, repeats: true) { _ in
            Task { @MainActor in RemoteLog.shared.saveRing() }
        }
        // Also on the way into the background (same observer pattern as FocusVideoPlayer): tvOS may end a suspended
        // app without notice, the last up to 30 s of lines would be lost otherwise.
        _ = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil,
                                                   queue: .main) { _ in
            // queue .main: already on the main thread, so save right here instead of in a later Task.
            MainActor.assumeIsolated { RemoteLog.shared.saveRing(now: true) }
        }
    }

    static func info(_ cat: String, _ msg: String) { shared.add("info", cat, msg) }
    static func error(_ cat: String, _ msg: String) { shared.add("error", cat, msg) }

    // MARK: Einstellungen

    /// Vom AppModel bei jeder Änderung der Geräte-Einstellungen oder der Profile (Geheimnis `playerlog`).
    func configure(enabled: Bool, receiver: String?, secret: String?) {
        let changed = enabled != self.enabled || receiver != self.receiver || secret != self.secret
        self.enabled = enabled
        self.receiver = receiver
        self.secret = secret
        if enabled { startBrowsing() }
        if changed { flush() }
    }

    /// Sucht Empfänger (Auswahl in Einstellungen › System › Fern-Log und zum Senden). Läuft danach weiter.
    func startBrowsing() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjour(type: "_playerlog._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { results, _ in
            let named = Dictionary(results.compactMap { r -> (String, NWEndpoint)? in
                if case let .service(name, _, _, _) = r.endpoint { return (name, r.endpoint) }
                return nil
            }, uniquingKeysWith: { a, _ in a })
            Task { @MainActor in
                RemoteLog.shared.found = named
                RemoteLog.shared.flush()
            }
        }
        b.start(queue: .main)
        browser = b
    }

    /// Gefundene Dienstnamen, sortiert.
    var foundReceivers: [String] { found.keys.sorted() }

    var status: RemoteLogTarget.Status {
        RemoteLogTarget.status(enabled: enabled, receiver: receiver, secret: secret, found: Array(found.keys))
    }

    /// Verlauf für die Seite „Diagnose“, neueste Zeile zuerst.
    func recent(_ limit: Int, errorsOnly: Bool) -> [LogLine] { ring.recent(limit, errorsOnly: errorsOnly) }

    // MARK: Zeilen

    /// Jede Zeile läuft durch `LogRedact.text`: Adressen nur mit Schema + Host (+ Dateiname/IMDb-ID),
    /// Schlüssel in Pfad/Query (Debrid, AIOStreams, Torrentio) landen weder im os_log, im Verlauf noch beim Empfänger.
    private func add(_ level: String, _ cat: String, _ raw: String) {
        let msg = LogRedact.text(raw)
        if level == "error" { os.error("\(cat, privacy: .public): \(msg, privacy: .public)") }
        else { os.info("\(cat, privacy: .public): \(msg, privacy: .public)") }
        let line = LogLine(time: iso.string(from: Date()), session: session, level: level, category: cat, message: msg)
        ring.append(line)
        ringDirty = true
        pending.append(line)
        if pending.count > 500 { pending.removeFirst(pending.count - 500) }
    }

    func flush() {
        guard !sending, !pending.isEmpty, let key = secret,
              let name = RemoteLogTarget.pick(enabled: enabled, receiver: receiver, secret: key, found: Array(found.keys)),
              let target = found[name] else { return }
        let batch = pending
        guard let body = try? JSONEncoder().encode(batch) else { return }
        let sig = LogSignature.sign(body: body, secret: key)
        sending = true
        let c = NWConnection(to: target, using: .tcp)
        let head = "POST /log HTTP/1.1\r\nHost: player\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n"
            + "\(LogSignature.header): \(sig)\r\nConnection: close\r\n\r\n"
        var req = Data(head.utf8)
        req.append(body)
        c.stateUpdateHandler = { st in
            switch st {
            case .ready:
                c.send(content: req, completion: .contentProcessed { err in
                    c.receive(minimumIncompleteLength: 1, maximumLength: 512) { data, _, _, _ in
                        let ok = err == nil && (data.map { String(decoding: $0, as: UTF8.self).contains(" 200 ") } ?? false)
                        c.cancel()
                        Task { @MainActor in RemoteLog.shared.finished(ok: ok, count: batch.count) }
                    }
                })
            case .failed, .waiting:
                c.cancel()
                Task { @MainActor in RemoteLog.shared.finished(ok: false, count: 0) }
            default: break
            }
        }
        c.start(queue: .main)
    }

    private func finished(ok: Bool, count: Int) {
        if ok { pending.removeFirst(min(count, pending.count)) }
        sending = false
    }

    // MARK: Verlauf auf dem Gerät

    /// `now`: write at once on the calling thread (going into the background), otherwise off the main thread.
    private func saveRing(now: Bool = false) {
        guard ringDirty, let url = ringURL, let data = try? JSONEncoder().encode(ring) else { return }
        ringDirty = false
        if now { try? data.write(to: url, options: .atomic); return }
        Task.detached(priority: .utility) { try? data.write(to: url, options: .atomic) }
    }

    /// Gespeicherter Verlauf (die neuesten Zeilen bis zur aktuellen Größe), sonst leer.
    private static func loadRing(_ url: URL?) -> LogRing {
        var ring = LogRing()
        guard let url, let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(LogRing.self, from: data) else { return ring }
        for line in stored.snapshot().suffix(ring.capacity) { ring.append(line) }
        return ring
    }
}
