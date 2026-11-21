import Foundation

/// Bearbeiten-Modus der Startseite (Spec §2): eine Reihe ist "angefasst",
/// ▲▼ verschiebt, ◀▶ wechselt den Stil, Play/Pause nimmt sie weg, OK = commit, Zurück = cancel.
/// Dazu die Aktionen des Verwalters „Reihen & Collections“: ganz oben/unten, an Position, Einfügen, Umschalten.
public struct HomeEditor: Sendable {
    public private(set) var layout: HomeLayout
    public private(set) var grabbed: UUID?
    private let original: HomeLayout

    public init(layout: HomeLayout, grabbing: UUID? = nil) {
        self.layout = layout; self.original = layout
        self.grabbed = grabbing.flatMap { id in layout.rows.contains { $0.id == id } ? id : nil }
    }

    private var index: Int? { grabbed.flatMap { id in layout.rows.firstIndex { $0.id == id } } }

    public mutating func grab(_ id: UUID?) {
        grabbed = id.flatMap { id in layout.rows.contains { $0.id == id } ? id : nil }
    }

    public mutating func moveUp() {
        guard let i = index, i > 0 else { return }
        layout.rows.swapAt(i, i - 1)
    }

    public mutating func moveDown() {
        guard let i = index, i < layout.rows.count - 1 else { return }
        layout.rows.swapAt(i, i + 1)
    }

    public mutating func nextStyle() { shiftStyle(+1) }
    public mutating func previousStyle() { shiftStyle(-1) }

    private mutating func shiftStyle(_ d: Int) {
        guard let i = index else { return }
        let styles = layout.rows[i].content.allowedStyles
        let cur = styles.firstIndex(of: layout.rows[i].style) ?? 0
        layout.rows[i].style = styles[(cur + d + styles.count) % styles.count]
    }

    public mutating func removeGrabbed() {
        guard let g = grabbed, let i = index else { return }
        layout.rows.remove(at: i)
        added.removeAll { $0 == g }
        grabbed = nil
    }

    /// Neue Reihe am Ende (über der Plus-Kachel), sofort angefasst.
    @discardableResult
    public mutating func add(_ content: RowContent) -> UUID {
        let row = HomeRow(content: content)
        layout.rows.append(row)
        added.append(row.id)
        grabbed = row.id
        return row.id
    }

    // MARK: Verwalter (Plan §2.5): Sprungaktionen, Einfügen, Umschalten

    /// In dieser Sitzung hinzugefügte Reihen, in Reihenfolge des Hinzufügens (Markierung „neu“ im Verwalter).
    public private(set) var added: [UUID] = []

    public func isNew(_ id: UUID) -> Bool { added.contains(id) }

    @discardableResult
    public mutating func moveToTop(_ id: UUID) -> RowMove? { layout.moveToTop(id) }

    @discardableResult
    public mutating func moveToBottom(_ id: UUID) -> RowMove? { layout.moveToBottom(id) }

    /// `index` 0-basiert, wird in die gültigen Grenzen gezogen.
    @discardableResult
    public mutating func move(_ id: UUID, to index: Int) -> RowMove? { layout.move(id, to: index) }

    /// Fügt ein (Standard: **am Ende**, Nutzerentscheidung 21.11.). Liegt der Inhalt schon auf der Startseite,
    /// bleibt alles, wie es ist, und die vorhandene Reihe wird zurückgegeben. Fasst nichts an.
    @discardableResult
    public mutating func insert(_ content: RowContent, at index: Int? = nil, style: RowStyle? = nil) -> UUID {
        if let existing = layout.row(withKey: content.key) { return existing.id }
        let id = layout.insert(content, at: index, style: style)
        added.append(id)
        return id
    }

    /// Hinzufügen-Browser: einmal OK fügt hinzu (am Ende), nochmal OK nimmt die Reihe wieder weg.
    @discardableResult
    public mutating func toggle(_ content: RowContent, style: RowStyle? = nil) -> RowToggle {
        if let existing = layout.row(withKey: content.key) {
            remove(existing.id)
            return .removed(existing.id)
        }
        return .added(insert(content, style: style))
    }

    /// Reihe entfernen (Aktionsleiste „Entfernen …“, nach Rückfrage in der UI).
    @discardableResult
    public mutating func remove(_ id: UUID) -> Bool {
        guard layout.remove(id) else { return false }
        added.removeAll { $0 == id }
        if grabbed == id { grabbed = nil }
        return true
    }

    public func commit() -> HomeLayout { layout }
    public func cancel() -> HomeLayout { original }

    /// Alles, was nicht auf der Startseite liegt: Collections zuerst, dann Listen.
    public func availableToAdd(collections: [MediaCollection], extraLists: [CatalogSource]) -> [RowContent] {
        let used = Set(layout.rows.map(\.content.key))
        let all = collections.map { RowContent.collection(id: $0.id) } + extraLists.map { RowContent.list($0) }
        return all.filter { !used.contains($0.key) }
    }
}

/// Verschiebung einer Reihe, 0-basiert (für das Log „verschoben von→nach“).
public struct RowMove: Equatable, Sendable {
    public var from: Int
    public var to: Int
    public init(from: Int, to: Int) { self.from = from; self.to = to }
}

public enum RowToggle: Equatable, Sendable {
    case added(UUID)
    case removed(UUID)
}

/// Bearbeitung ohne Editor-Sitzung (z. B. Handy-Seite „Startseite ordnen“).
extension HomeLayout {
    public func index(of id: UUID) -> Int? { rows.firstIndex { $0.id == id } }

    public func row(withKey key: String) -> HomeRow? { rows.first { $0.content.key == key } }

    public func contains(_ content: RowContent) -> Bool { row(withKey: content.key) != nil }

    /// nil = Reihe unbekannt oder schon an der Stelle.
    @discardableResult
    public mutating func move(_ id: UUID, to index: Int) -> RowMove? {
        guard let from = self.index(of: id) else { return nil }
        let to = min(max(index, 0), rows.count - 1)
        guard to != from else { return nil }
        let row = rows.remove(at: from)
        rows.insert(row, at: to)
        return RowMove(from: from, to: to)
    }

    @discardableResult
    public mutating func moveToTop(_ id: UUID) -> RowMove? { move(id, to: 0) }

    @discardableResult
    public mutating func moveToBottom(_ id: UUID) -> RowMove? { move(id, to: rows.count - 1) }

    /// Neue Reihe; `index` nil = am Ende, sonst in die Grenzen gezogen. Prüft keine Doppelten.
    @discardableResult
    public mutating func insert(_ content: RowContent, at index: Int? = nil, style: RowStyle? = nil) -> UUID {
        let row = HomeRow(content: content, style: style)
        rows.insert(row, at: min(max(index ?? rows.count, 0), rows.count))
        return row.id
    }

    @discardableResult
    public mutating func remove(_ id: UUID) -> Bool {
        guard let i = index(of: id) else { return false }
        rows.remove(at: i)
        return true
    }
}
