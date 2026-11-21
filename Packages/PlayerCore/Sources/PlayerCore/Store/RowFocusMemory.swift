import Foundation

/// Fokus-Gedächtnis der Startseite: je Reihe die zuletzt fokussierte Kachel.
/// Meldungen, während eine andere Seite über der Startseite liegt (`covered`), zählen nicht:
/// sonst merkt sich eine Reihe den Nachbarn, auf den das System den Fokus beim Zurückkehren legt.
public struct RowFocusMemory: Sendable, Equatable {
    public static let maxRows = 64

    public var covered = false
    private var items: [String: String] = [:]
    private var order: [String] = []

    public init() {}

    /// Merkt `item` für `row`. Gibt zurück, ob gemerkt wurde.
    @discardableResult
    public mutating func record(row: String, item: String) -> Bool {
        guard !covered else { return false }
        items[row] = item
        order.removeAll { $0 == row }
        order.append(row)
        if order.count > Self.maxRows { items[order.removeFirst()] = nil }
        return true
    }

    public func remembered(row: String) -> String? { items[row] }

    /// Gemerkte Kachel, sofern sie unter den aktuellen IDs der Reihe noch vorkommt.
    public func remembered(row: String, among ids: [String]) -> String? {
        guard let i = items[row], ids.contains(i) else { return nil }
        return i
    }

    public mutating func forget(row: String) {
        items[row] = nil
        order.removeAll { $0 == row }
    }
}
