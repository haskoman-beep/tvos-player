import Foundation

/// Welle E-a Nacharbeit 1: Abfrage beim Metadaten-Addon mit Zeitgrenzen.
/// - `run`: eine Abfrage mit harter Grenze; Abbruch zählt nicht als Fehler (wird nicht gecacht).
/// - `wait`: Aufrufer warten höchstens kurz auf eine (geteilte) laufende Abfrage, die danach weiterläuft.
public enum AddonMetaFetch {
    public enum Outcome: Sendable, Equatable {
        case meta(MetaDetail)
        /// Fehler oder Zeitüberschreitung: kurz als „keine Antwort“ merken.
        case failed
        /// Abgebrochen: nichts merken.
        case cancelled
    }

    /// Wie lange Detailseite, Hero und Folgenliste höchstens auf das Addon warten.
    public static let callerWaitSeconds: Double = 3
    /// Harte Grenze der geteilten Abfrage selbst (statt 60 s Standard von URLSession).
    public static let requestLimitSeconds: Double = 10

    /// Abbruch (Task oder URLSession) statt echtem Fehler.
    public static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let u = error as? URLError, u.code == .cancelled { return true }
        return false
    }

    public static func run(limit seconds: Double = requestLimitSeconds,
                           _ op: @escaping @Sendable () async throws -> MetaDetail) async -> Outcome {
        do {
            let m = try await limited(seconds, op)
            return .meta(m)
        } catch {
            if isCancellation(error) || Task.isCancelled { return .cancelled }
            return .failed
        }
    }

    /// Ergebnis von `task`, aber höchstens `seconds` warten (dann nil; `task` läuft weiter und füllt den Cache).
    public static func wait<T: Sendable>(for task: Task<T?, Never>, atMost seconds: Double) async -> T? {
        let once = ResumeOnce<T>()
        return await withCheckedContinuation { (c: CheckedContinuation<T?, Never>) in
            once.attach(c)
            Task { once.resume(await task.value) }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                once.resume(nil)
            }
        }
    }

    /// Ergebnis von `task`; wird der Aufrufer abgebrochen, sofort nil und `onCancel` (z. B. Abfrage abmelden).
    public static func value<T: Sendable>(of task: Task<T?, Never>, onCancel: @escaping @Sendable () -> Void) async -> T? {
        let once = ResumeOnce<T>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<T?, Never>) in
                once.attach(c)
                Task { once.resume(await task.value) }
            }
        } onCancel: {
            once.resume(nil)
            onCancel()
        }
    }

    /// Ergebnis von `op` oder `URLError(.timedOut)` nach `seconds` (die Arbeit wird dann abgebrochen).
    static func limited<T: Sendable>(_ seconds: Double, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw URLError(.timedOut) }
            return first
        }
    }
}

/// Setzt eine Fortsetzung genau einmal fort (wer zuerst kommt); ein Ergebnis vor `attach` wird nachgereicht.
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?
    private var result: T??
    private var done = false

    func attach(_ c: CheckedContinuation<T?, Never>) {
        lock.lock()
        if let r = result { result = nil; lock.unlock(); c.resume(returning: r); return }
        continuation = c
        lock.unlock()
    }

    func resume(_ v: T?) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true
        if let c = continuation { continuation = nil; lock.unlock(); c.resume(returning: v); return }
        result = .some(v)
        lock.unlock()
    }
}
