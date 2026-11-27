import Foundation

/// Welle E-a Nacharbeit 1: höchstens `limit` gleichzeitige Arbeiten (z. B. Addon-Abfragen sichtbarer Kacheln).
/// Wer wartet und abgebrochen wird, verlässt die Warteschlange, ohne einen Platz zu belegen.
/// Build 8 (poster): waiters carry a ticket and an urgency. Urgent ones (visible tiles) are served before the others
/// (block warm-up); `promote` moves a waiting ticket forward when a visible tile joins it.
public actor AsyncLimiter {
    public let limit: Int
    private var running = 0
    private var urgent: [(id: UUID, c: CheckedContinuation<Bool, Never>)] = []
    private var normal: [(id: UUID, c: CheckedContinuation<Bool, Never>)] = []
    /// Promotions that arrived before their ticket queued (kept small).
    private var early: Set<UUID> = []

    public init(limit: Int) { self.limit = max(1, limit) }

    /// Belegte Plätze und Wartende (für Tests und Protokoll).
    public var active: Int { running }
    public var queued: Int { urgent.count + normal.count }

    /// true: Platz belegt (danach `release()`), false: vorher abgebrochen.
    public func acquire() async -> Bool { await acquire(ticket: UUID(), urgent: true) }

    /// Build 8: `urgent` waiters go first; a ticket promoted before it got here counts as urgent.
    public func acquire(ticket: UUID, urgent isUrgent: Bool) async -> Bool {
        let wasPromoted = early.remove(ticket) != nil
        if Task.isCancelled { return false }
        if running < limit { running += 1; return true }
        let first = isUrgent || wasPromoted
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                if first { urgent.append((ticket, c)) } else { normal.append((ticket, c)) }
            }
        } onCancel: {
            Task { await self.dropWaiter(ticket) }
        }
    }

    /// Build 8: a waiting ticket moves to the urgent queue (end of it); unknown tickets are remembered briefly.
    public func promote(_ ticket: UUID) {
        if let i = normal.firstIndex(where: { $0.id == ticket }) {
            urgent.append(normal.remove(at: i))
            return
        }
        guard !urgent.contains(where: { $0.id == ticket }) else { return }
        if early.count >= 256 { early.removeAll() }
        early.insert(ticket)
    }

    /// Platz freigeben; der nächste Wartende (dringende zuerst) übernimmt ihn direkt.
    public func release() {
        if !urgent.isEmpty { urgent.removeFirst().c.resume(returning: true); return }
        if !normal.isEmpty { normal.removeFirst().c.resume(returning: true); return }
        running = max(0, running - 1)
    }

    /// `op` mit belegtem Platz; nil, wenn schon beim Warten abgebrochen.
    public nonisolated func run<T: Sendable>(_ op: @Sendable () async -> T) async -> T? {
        guard await acquire() else { return nil }
        let r = await op()
        await release()
        return r
    }

    private func dropWaiter(_ id: UUID) {
        if let i = urgent.firstIndex(where: { $0.id == id }) { urgent.remove(at: i).c.resume(returning: false); return }
        if let i = normal.firstIndex(where: { $0.id == id }) { normal.remove(at: i).c.resume(returning: false) }
    }
}

/// Welle E-a Runde 2: Wartende einer geteilten Abfrage. Kacheln zählen einzeln; Detailseite, Hero und Folgenliste
/// halten die Abfrage bis zum Ende fest (`pinned`), damit sie den Cache füllt.
/// Build 8 (poster): a block warm-up (`warm`) holds it too, at low urgency; once the request is sent (`started`) it is
/// never cancelled because tiles scrolled away: its answer fills the cache. Only a not yet started request whose last
/// tile left (and no warm-up or pin) is dropped.
public struct FlightWaiters: Sendable, Equatable {
    public private(set) var tiles = 0
    public private(set) var pinned = false
    public private(set) var warm = false
    public private(set) var started = false

    public init(tile: Bool) { join(tile: tile) }

    /// Build 8: a warm-up starts the flight.
    public init(warm: Bool) { if warm { self.warm = true } else { pinned = true } }

    public mutating func join(tile: Bool) {
        if tile { tiles += 1 } else { pinned = true }
    }

    public mutating func joinWarm() { warm = true }

    public mutating func markStarted() { started = true }

    /// Build 8: waits ahead of warm-ups (a visible tile, the detail page …).
    public var urgent: Bool { tiles > 0 || pinned }

    /// Eine Kachel wartet nicht mehr; true = niemand mehr da und noch nicht gesendet, Abfrage abbrechen.
    public mutating func leaveTile() -> Bool {
        tiles = max(0, tiles - 1)
        return tiles == 0 && !pinned && !warm && !started
    }
}
