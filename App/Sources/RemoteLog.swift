import Foundation
import Network
import os

/// Ereignis-Log: os_log + Sendung ans Log-Programm im Heimnetz (per Bonjour `_playerlog._tcp` gefunden).
/// Ohne Empfänger bleiben die letzten 500 Zeilen im Speicher und gehen raus, sobald einer auftaucht.
@MainActor
final class RemoteLog {
    static let shared = RemoteLog()
    private let os = Logger(subsystem: "de.haskoman.player", category: "app")
    private var pending: [[String: String]] = []
    private var browser: NWBrowser?
    private var target: NWEndpoint?
    private var sending = false
    private let session = String(UUID().uuidString.prefix(8))
    private let iso = ISO8601DateFormatter()

    private init() {
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let b = NWBrowser(for: .bonjour(type: "_playerlog._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { results, _ in
            Task { @MainActor in
                RemoteLog.shared.target = results.first?.endpoint
                RemoteLog.shared.flush()
            }
        }
        b.start(queue: .main)
        browser = b
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in Task { @MainActor in RemoteLog.shared.flush() } }
    }

    static func info(_ cat: String, _ msg: String) { shared.add("info", cat, msg) }
    static func error(_ cat: String, _ msg: String) { shared.add("error", cat, msg) }

    private func add(_ level: String, _ cat: String, _ msg: String) {
        if level == "error" { os.error("\(cat, privacy: .public): \(msg, privacy: .public)") }
        else { os.info("\(cat, privacy: .public): \(msg, privacy: .public)") }
        pending.append(["t": iso.string(from: Date()), "s": session, "l": level, "c": cat, "m": msg])
        if pending.count > 500 { pending.removeFirst(pending.count - 500) }
    }

    func flush() {
        guard let target, !sending, !pending.isEmpty else { return }
        let batch = pending
        guard let body = try? JSONSerialization.data(withJSONObject: batch) else { return }
        sending = true
        let c = NWConnection(to: target, using: .tcp)
        var req = Data("POST /log HTTP/1.1\r\nHost: player\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
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
}
