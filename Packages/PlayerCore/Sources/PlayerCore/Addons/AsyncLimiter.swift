import Foundation

/// Welle E-a Nacharbeit 1: höchstens `limit` gleichzeitige Arbeiten (z. B. Addon-Abfragen sichtbarer Kacheln).
/// Wer wartet und abgebrochen wird, verlässt die Warteschlange, ohne einen Platz zu belegen.
public actor AsyncLimiter {
    public let limit: Int
    private var running = 0
    private var waiters: [(id: UUID, c: CheckedContinuation<Bool, Never>)] = []

    public init(limit: Int) { self.limit = max(1, limit) }

    /// Belegte Plätze und Wartende (für Tests und Protokoll).
    public var active: Int { running }
    public var queued: Int { waiters.count }

    /// true: Platz belegt (danach `release()`), false: vorher abgebrochen.
    public func acquire() async -> Bool {
        if Task.isCancelled { return false }
        if running < limit { running += 1; return true }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in waiters.append((id, c)) }
        } onCancel: {
            Task { await self.dropWaiter(id) }
        }
    }

    /// Platz freigeben; der nächste Wartende übernimmt ihn direkt.
    public func release() {
        if waiters.isEmpty { running = max(0, running - 1); return }
        waiters.removeFirst().c.resume(returning: true)
    }

    /// `op` mit belegtem Platz; nil, wenn schon beim Warten abgebrochen.
    public nonisolated func run<T: Sendable>(_ op: @Sendable () async -> T) async -> T? {
        guard await acquire() else { return nil }
        let r = await op()
        await release()
        return r
    }

    private func dropWaiter(_ id: UUID) {
        guard let i = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: i).c.resume(returning: false)
    }
}

/// Welle E-a Runde 2: Wartende einer geteilten Abfrage. Kacheln zählen einzeln; Detailseite, Hero und Folgenliste
/// halten die Abfrage bis zum Ende fest (`pinned`), damit sie den Cache füllt.
public struct FlightWaiters: Sendable, Equatable {
    public private(set) var tiles = 0
    public private(set) var pinned = false

    public init(tile: Bool) { join(tile: tile) }

    public mutating func join(tile: Bool) {
        if tile { tiles += 1 } else { pinned = true }
    }

    /// Eine Kachel wartet nicht mehr; true = niemand mehr da, Abfrage abbrechen.
    public mutating func leaveTile() -> Bool {
        tiles = max(0, tiles - 1)
        return tiles == 0 && !pinned
    }
}
