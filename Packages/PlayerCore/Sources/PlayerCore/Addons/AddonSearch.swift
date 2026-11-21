import Foundation

/// Zustand eines Addons während der Quellensuche.
public enum AddonSearchState: Equatable, Sendable {
    case loading
    case ok(count: Int)
    case failed(reason: String)
    case timedOut

    public var isFinished: Bool { self != .loading }

    /// Deutsche Kurzform für die Quellenliste.
    public var label: String {
        switch self {
        case .loading: "lädt …"
        case .ok(let n): n == 1 ? "1 Quelle" : "\(n) Quellen"
        case .failed(let r): "Fehler: \(r)"
        case .timedOut: "Zeitüberschreitung"
        }
    }
}

/// Ein Addon in der laufenden Suche (Reihenfolge = Reihenfolge der installierten Addons).
public struct AddonSearchStatus: Equatable, Sendable, Identifiable {
    public var index: Int
    public var name: String
    public var state: AddonSearchState
    /// Antwortzeit in Millisekunden (nil = läuft noch).
    public var milliseconds: Int?
    public var id: Int { index }

    public init(index: Int, name: String, state: AddonSearchState = .loading, milliseconds: Int? = nil) {
        self.index = index; self.name = name; self.state = state; self.milliseconds = milliseconds
    }
}

/// Stand einer Quellensuche über mehrere Addons: Status je Addon und die schon eingetroffenen Treffer.
public struct AddonSearchProgress: Sendable {
    public private(set) var statuses: [AddonSearchStatus]
    private var found: [Int: (addon: InstalledAddon, streams: [StreamItem])] = [:]

    public init(addons: [(index: Int, addon: InstalledAddon)]) {
        statuses = addons.map { AddonSearchStatus(index: $0.index, name: $0.addon.manifest.name) }
    }

    /// Ein Addon ist fertig (Treffer, Fehler oder Zeitüberschreitung).
    public mutating func finish(index: Int, addon: InstalledAddon, outcome: AddonSearch.Outcome, milliseconds: Int) {
        guard let i = statuses.firstIndex(where: { $0.index == index }) else { return }
        statuses[i].milliseconds = milliseconds
        switch outcome {
        case .streams(let s): statuses[i].state = .ok(count: s.count); found[index] = (addon, s)
        case .failed(let r): statuses[i].state = .failed(reason: r)
        case .timedOut: statuses[i].state = .timedOut
        }
    }

    /// Bisherige Treffer in Addon-Reihenfolge (wie das Endergebnis).
    public var results: [(addon: InstalledAddon, streams: [StreamItem])] {
        found.sorted { $0.key < $1.key }.map(\.value)
    }

    public var finishedCount: Int { statuses.filter(\.state.isFinished).count }
    public var isComplete: Bool { finishedCount == statuses.count }
    /// Mindestens ein Addon ohne Antwort (Fehler, Zeitüberschreitung): Ergebnis nur kurz zwischenspeichern.
    public var isPartial: Bool {
        statuses.contains { if case .failed = $0.state { return true }; return $0.state == .timedOut }
    }

    /// „Addons 2/3“ während der Suche, nil wenn fertig.
    public var runningSummary: String? {
        isComplete ? nil : "Addons \(finishedCount)/\(statuses.count) fertig"
    }

    /// Fürs Log: „AIOStreams=12 (850 ms), Torrentio=Zeitüberschreitung“.
    public var logText: String {
        statuses.map { s in
            let ms = s.milliseconds.map { " (\($0) ms)" } ?? ""
            switch s.state {
            case .ok(let n): return "\(s.name)=\(n)\(ms)"
            default: return "\(s.name)=\(s.state.label)\(ms)"
            }
        }.joined(separator: ", ")
    }
}

public enum AddonSearch {
    /// Zeitgrenze je Addon (Sekunden). AIOStreams fragt selbst viele Dienste ab und braucht oft über 10 s.
    public static let defaultTimeout: Double = 15
    /// Auswahl in den Einstellungen.
    public static let timeoutChoices: [Double] = [8, 12, 15, 20, 30, 45]
    /// Lückenhaftes Ergebnis (ein Addon fehlt) so lange im Quellen-Cache statt der vollen 10 min.
    public static let partialCacheSeconds: TimeInterval = 60

    /// Gespeicherter Wert → nächstliegende Auswahl (alte oder fremde Werte zeigen sonst keine Auswahl).
    public static func nearestChoice(_ seconds: Double) -> Double {
        timeoutChoices.min { abs($0 - seconds) < abs($1 - seconds) } ?? defaultTimeout
    }

    /// Zeitgrenze aus dem Profil, auf einen sinnvollen Bereich geklemmt.
    public static func clamp(_ seconds: Double) -> Double { min(max(seconds, 3), 120) }

    public enum Outcome: Sendable {
        case streams([StreamItem])
        case failed(String)
        case timedOut
    }

    /// Fehler kurz und ohne Adresse (Links können Schlüssel enthalten).
    public static func describe(_ error: Error) -> String {
        if let e = error as? AddonError {
            switch e {
            case .http(let code): return "HTTP \(code)"
            case .invalidManifestURL: return "Adresse ungültig"
            }
        }
        if error is DecodingError { return "Antwort unlesbar" }
        if error is CancellationError { return "abgebrochen" }
        let ns = error as NSError
        if ns.domain == "NSURLErrorDomain" {
            switch ns.code {
            case -1001: return "Zeitüberschreitung"
            case -1009, -1005, -1020: return "keine Verbindung"
            case -1003, -1004, -1006: return "Server nicht erreichbar"
            case -1206 ... -1200: return "Zertifikat"
            default: return "Netzfehler \(ns.code)"
            }
        }
        return "Fehler"
    }

    /// `op` mit Frist ausführen: nil = Frist abgelaufen (die Arbeit wird abgebrochen).
    public static func withDeadline<T: Sendable>(_ seconds: Double,
                                                 _ op: @escaping @Sendable () async throws -> T) async -> Result<T, Error>? {
        await withTaskGroup(of: Result<T, Error>?.self) { group in
            group.addTask {
                do { return .success(try await op()) } catch { return .failure(error) }
            }
            group.addTask {
                // Abgebrochene Suche (Aufrufer weg) ist keine Zeitüberschreitung.
                do { try await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000)) }
                catch { return .failure(CancellationError()) }
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

extension AddonClient {
    /// Streams aller passenden Addons parallel, jedes mit eigener Zeitgrenze. `onUpdate` meldet nach jedem fertigen
    /// Addon den neuen Stand (Treffer erscheinen sofort). Ergebnis wie `streams(from:type:id:)`: nur Addons mit
    /// Antwort, in Addon-Reihenfolge.
    public func streams(from addons: [InstalledAddon], type: String, id: String, timeout: Double,
                        onUpdate: @escaping @Sendable (AddonSearchProgress) async -> Void) async
        -> [(addon: InstalledAddon, streams: [StreamItem])] {
        let wanted = addons.enumerated().filter { $0.element.manifest.supports("stream", type: type, id: id) }
            .map { (index: $0.offset, addon: $0.element) }
        var progress = AddonSearchProgress(addons: wanted)
        await onUpdate(progress)
        let limit = AddonSearch.clamp(timeout)
        await withTaskGroup(of: (Int, InstalledAddon, AddonSearch.Outcome, Int).self) { group in
            for w in wanted {
                group.addTask {
                    let t0 = Date()
                    let r = await AddonSearch.withDeadline(limit) { try await self.streams(w.addon, type: type, id: id) }
                    let ms = Int(Date().timeIntervalSince(t0) * 1000)
                    switch r {
                    case .some(.success(let s)): return (w.index, w.addon, .streams(s), ms)
                    case .some(.failure(let e)): return (w.index, w.addon, .failed(AddonSearch.describe(e)), ms)
                    case .none: return (w.index, w.addon, .timedOut, ms)
                    }
                }
            }
            for await (i, a, outcome, ms) in group {
                progress.finish(index: i, addon: a, outcome: outcome, milliseconds: ms)
                await onUpdate(progress)
            }
        }
        return progress.results
    }
}
