import Foundation

/// Bearbeiten-Modus der Startseite (Spec §2): eine Reihe ist "angefasst",
/// ▲▼ verschiebt, ◀▶ wechselt den Stil, Play/Pause nimmt sie weg, OK = commit, Zurück = cancel.
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
        guard let i = index else { return }
        layout.rows.remove(at: i)
        grabbed = nil
    }

    /// Neue Reihe am Ende (über der Plus-Kachel), sofort angefasst.
    @discardableResult
    public mutating func add(_ content: RowContent) -> UUID {
        let row = HomeRow(content: content)
        layout.rows.append(row)
        grabbed = row.id
        return row.id
    }

    public func commit() -> HomeLayout { layout }
    public func cancel() -> HomeLayout { original }

    /// Alles, was nicht auf der Startseite liegt: Collections zuerst, dann Listen.
    public func availableToAdd(collections: [Collection], extraLists: [CatalogSource]) -> [RowContent] {
        let used = Set(layout.rows.map(\.content.key))
        let all = collections.map { RowContent.collection(id: $0.id) } + extraLists.map { RowContent.list($0) }
        return all.filter { !used.contains($0.key) }
    }
}
