import Foundation

/// Welle D-b (M1): laufende Abfragen je Schlüssel, zusammengelegt (ein zweiter Aufruf wartet auf dieselbe Aufgabe).
/// - `reset()` (Profilwechsel) vergisst alle laufenden Abfragen: ein neuer Aufruf startet dann eine eigene und
///   übernimmt nie das Ergebnis einer alten.
/// - `finish` räumt nur den eigenen Eintrag weg: endet eine alte Abfrage nach dem Wechsel, bleibt eine neuere
///   unter demselben Schlüssel stehen.
/// - `isCurrent`: die Abfrage wurde seit ihrem Start nicht durch `reset()` vergessen (darf ihr Ergebnis ablegen).
public struct TaskSlots<Value: Sendable> {
    public struct Ticket: Equatable, Sendable {
        let serial: Int
        let epoch: Int
    }

    private var slots: [String: (ticket: Ticket, task: Task<Value, Never>)] = [:]
    private var serial = 0
    private var epoch = 0

    public init() {}

    /// Laufende Abfrage zu `key` (nil = keine).
    public subscript(key: String) -> Task<Value, Never>? { slots[key]?.task }

    public var count: Int { slots.count }

    /// Abfrage zu `key` eintragen; der Beleg gehört zu genau diesem Eintrag.
    public mutating func begin(_ key: String, _ task: Task<Value, Never>) -> Ticket {
        serial += 1
        let t = Ticket(serial: serial, epoch: epoch)
        slots[key] = (t, task)
        return t
    }

    /// Eintrag entfernen, aber nur, wenn er noch der zu `ticket` ist.
    public mutating func finish(_ key: String, _ ticket: Ticket) {
        if slots[key]?.ticket == ticket { slots[key] = nil }
    }

    /// Alle laufenden Abfragen vergessen (sie laufen aus, ohne dass jemand neu auf sie wartet).
    public mutating func reset() {
        slots.removeAll()
        epoch += 1
    }

    /// Seit dem Start der Abfrage kein `reset()`.
    public func isCurrent(_ ticket: Ticket) -> Bool { ticket.epoch == epoch }

    /// Beleg für eine Abfrage, die noch nicht eingetragen ist (Prüfung `isCurrent` vor `begin`).
    public var currentEpoch: Int { epoch }
    public func isCurrent(epoch e: Int) -> Bool { e == epoch }
}
