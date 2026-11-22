import Foundation

/// Bearbeitung der Startseite für den Verwalter „Reihen & Collections“ (Plan §2.5) und die Handy-Seite:
/// Sprungaktionen, an Position, Verschiebemodus (`grab` + ▲▼), Stil, Einfügen am Ende, Ausblenden und Wiedereinblenden.
/// Merkt sich, welche Reihen in dieser Sitzung hinzugekommen sind („neu“).
public struct HomeEditor: Sendable {
    public private(set) var layout: HomeLayout
    public private(set) var grabbed: UUID?

    /// `added`: Reihen, die schon als „neu“ gelten (Verwalter übernimmt eine fremde Änderung, ohne die Marken zu verlieren).
    public init(layout: HomeLayout, grabbing: UUID? = nil, added: [UUID] = []) {
        self.layout = layout
        self.grabbed = grabbing.flatMap { id in layout.rows.contains { $0.id == id } ? id : nil }
        self.added = added.filter { id in layout.rows.contains { $0.id == id } }
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

    // MARK: Verwalter (Plan §2.5): Sprungaktionen, Einfügen

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

    /// Einfügen am Ende, mit Blick auf „Ausgeblendet“ (Fernseher und Handy gleich, F-b2-Review M6): liegt der Inhalt
    /// dort, kommt die gemerkte Reihe mit ID und Stil zurück und der Eintrag verschwindet. Liegt der Inhalt schon auf
    /// der Startseite, bleibt sie unverändert (nur „Ausgeblendet“ wird aufgeräumt) und die vorhandene Reihe kommt zurück.
    @discardableResult
    public mutating func insert(_ content: RowContent, style: RowStyle? = nil, hidden: inout [HomeRow]) -> UUID {
        let key = content.key
        let remembered = hidden.last { $0.content.key == key }
        hidden.removeAll { $0.content.key == key }
        if let existing = layout.row(withKey: key) { return existing.id }
        if let row = remembered, layout.index(of: row.id) == nil {
            layout.rows.append(row)
            added.append(row.id)
            return row.id
        }
        return insert(content, style: style)
    }

    /// Reihe entfernen (Browser nimmt eine eben hinzugefügte zurück); Ausblenden läuft über `hide`.
    @discardableResult
    public mutating func remove(_ id: UUID) -> Bool {
        guard layout.remove(id) else { return false }
        added.removeAll { $0 == id }
        if grabbed == id { grabbed = nil }
        return true
    }

    /// Welle F-b2: Reihe ausblenden. Sie verschwindet von der Startseite und wird vollständig (ID, Stil) in `hidden`
    /// (`Profile.hiddenRows`) gemerkt, gleiche Regel wie auf der Handy-Seite. nil = Reihe unbekannt.
    @discardableResult
    public mutating func hide(_ id: UUID, into hidden: inout [HomeRow]) -> (row: HomeRow, at: Int)? {
        guard let at = layout.index(of: id) else { return nil }
        let row = layout.rows[at]
        remove(id)
        HomeLayout.rememberHidden(row, in: &hidden)
        return (row, at)
    }

    /// Welle F-b2: ausgeblendete Reihe unverändert unten wieder anhängen (Nutzerentscheidung 2).
    /// Liegt ihr Inhalt inzwischen schon auf der Startseite, wird sie nur aus `hidden` genommen.
    @discardableResult
    public mutating func restore(_ id: UUID, from hidden: inout [HomeRow]) -> HomeRestore? {
        guard let j = hidden.firstIndex(where: { $0.id == id }) else { return nil }
        let row = hidden.remove(at: j)
        if let existing = layout.rows.first(where: { $0.id == row.id || $0.content.key == row.content.key }) {
            return .alreadyOnHome(existing)
        }
        layout.rows.append(row)
        return .restored(row, at: layout.rows.count - 1)
    }

    /// Welle F-b2: nächster erlaubter Stil einer Reihe (Aktionsleiste „Stil“), ohne sie anzufassen.
    @discardableResult
    public mutating func cycleStyle(_ id: UUID) -> RowStyle? {
        guard let i = layout.index(of: id) else { return nil }
        let styles = layout.rows[i].content.allowedStyles
        let cur = styles.firstIndex(of: layout.rows[i].style) ?? 0
        layout.rows[i].style = styles[(cur + 1) % styles.count]
        return layout.rows[i].style
    }
}

/// Verschiebung einer Reihe, 0-basiert (für das Log „verschoben von→nach“).
public struct RowMove: Equatable, Sendable {
    public var from: Int
    public var to: Int
    public init(from: Int, to: Int) { self.from = from; self.to = to }
}

/// Ergebnis von `HomeEditor.restore`.
public enum HomeRestore: Equatable, Sendable {
    /// Unten wieder angehängt (0-basierte Stelle).
    case restored(HomeRow, at: Int)
    /// Inhalt lag schon auf der Startseite (diese Reihe); nur aus „Ausgeblendet“ genommen, Startseite unverändert.
    case alreadyOnHome(HomeRow)
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

    /// Neue Reihe; `index` nil = am Ende, sonst in die Grenzen gezogen. Liegt der Inhalt schon auf der Startseite,
    /// bleibt alles, wie es ist, und die vorhandene Reihe wird zurückgegeben.
    @discardableResult
    public mutating func insert(_ content: RowContent, at index: Int? = nil, style: RowStyle? = nil) -> UUID {
        if let existing = row(withKey: content.key) { return existing.id }
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

    /// Merkt eine ausgeblendete Reihe (`Profile.hiddenRows`): gleicher Inhalt nur einmal, höchstens `hiddenLimit`,
    /// die älteste fällt zuerst heraus. Gilt für Fernseher und Handy.
    public static func rememberHidden(_ row: HomeRow, in hidden: inout [HomeRow]) {
        hidden.removeAll { $0.id == row.id || $0.content.key == row.content.key }
        hidden.append(row)
        if hidden.count > hiddenLimit { hidden.removeFirst(hidden.count - hiddenLimit) }
    }

    /// Ausgeblendete Reihen, die sich wieder einblenden lassen (Inhalt nicht auf der Startseite), neueste zuerst.
    /// Gemerkte Reihen, deren Inhalt inzwischen wieder da ist, zeigen weder Fernseher noch Handy an.
    public func restorable(_ hidden: [HomeRow]) -> [HomeRow] {
        let shown = Set(rows.map(\.content.key))
        return hidden.reversed().filter { !shown.contains($0.content.key) }
    }
}
