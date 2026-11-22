import Foundation

/// Welle F-b2: Zustand des Verwalters „Reihen & Collections“ (Plan §2.5, Ebene 1) und des Hinzufügen-Browsers
/// (Ebene 2). Alle Änderungen laufen über `HomeEditor`; hier liegt nur, was die Oberfläche testbar entscheiden muss:
/// Verschiebemodus, ausgeblendete Reihen, Fokus nach jeder Aktion (§3.2) und die Log-Texte.
public struct HomeManager: Sendable {
    /// Fokusziel im Verwalter.
    public enum Focus: Hashable, Sendable {
        /// Zeile „Reihe hinzufügen“.
        case add
        case row(UUID)
        /// Eintrag unter „Ausgeblendet“.
        case hidden(UUID)
    }

    /// Was eine Aktion bewirkt hat (für Log und Rückmeldung). Positionen 0-basiert.
    public enum Event: Equatable, Sendable {
        case moved(HomeRow, RowMove)
        case hidden(HomeRow, at: Int)
        case restored(HomeRow, at: Int)
        case added(HomeRow, at: Int)
        /// Im Browser zurückgenommen (in dieser Sitzung hinzugefügt, deshalb ohne Rückfrage und ohne „Ausgeblendet“).
        case removed(HomeRow, at: Int)
        case styled(HomeRow)

        /// Log-Text, Positionen 1-basiert wie in der Liste: „Reihe verschoben 20→1: Genres“.
        public func logText(title: String) -> String {
            switch self {
            case let .moved(_, m): "Reihe verschoben \(m.from + 1)→\(m.to + 1): \(title)"
            case let .hidden(_, at): "Reihe ausgeblendet an \(at + 1): \(title)"
            case let .restored(_, at): "Reihe wieder eingeblendet an \(at + 1): \(title)"
            case let .added(_, at): "Reihe hinzugefügt an \(at + 1): \(title)"
            case let .removed(_, at): "Reihe entfernt an \(at + 1): \(title)"
            case let .styled(row): "Stil \(row.style.displayName): \(title)"
            }
        }

        public var row: HomeRow {
            switch self {
            case let .moved(r, _), let .hidden(r, _), let .restored(r, _), let .added(r, _), let .removed(r, _), let .styled(r): r
            }
        }
    }

    /// Ergebnis einer Aktion: was passiert ist (nil = nichts) und wohin der Fokus geht.
    public struct Outcome: Equatable, Sendable {
        public var event: Event?
        public var focus: Focus
        public init(event: Event?, focus: Focus) { self.event = event; self.focus = focus }
    }

    /// Verschiebemodus: angefasste Reihe und ihre Stelle vor dem Anfassen (Menu stellt sie wieder her, N4).
    public struct Moving: Equatable, Sendable {
        public var id: UUID
        public var from: Int
    }

    /// OK im Browser auf einem Eintrag.
    public enum BrowserToggle: Equatable, Sendable {
        /// Unten angehängt (Nutzerentscheidung 2).
        case added(HomeRow, at: Int)
        /// In dieser Sitzung hinzugefügt und gleich wieder zurückgenommen.
        case removed(HomeRow, at: Int)
        /// Lag schon vorher auf der Startseite: erst nach Rückfrage ausblenden (F-b1-Review M1).
        case confirmHide(HomeRow)
    }

    public private(set) var editor: HomeEditor
    /// `Profile.hiddenRows`, älteste zuerst.
    public private(set) var hidden: [HomeRow]
    public private(set) var moving: Moving?

    public init(layout: HomeLayout, hidden: [HomeRow] = [], added: [UUID] = []) {
        editor = HomeEditor(layout: layout, added: added)
        self.hidden = hidden
    }

    public var layout: HomeLayout { editor.layout }
    public var rows: [HomeRow] { editor.layout.rows }
    public var count: Int { rows.count }
    /// „Ausgeblendet“: nur, was sich wieder einblenden lässt, neueste zuerst.
    public var restorable: [HomeRow] { layout.restorable(hidden) }

    public func isNew(_ id: UUID) -> Bool { editor.isNew(id) }
    /// 1-basierte Stelle (Anzeige „3“ vor der Zeile).
    public func position(of id: UUID) -> Int? { layout.index(of: id).map { $0 + 1 } }
    /// Auswahl für „An Position …“.
    public var positions: [Int] { count > 0 ? Array(1...count) : [] }

    /// Eintritt (§3.2): ohne Kontext „Reihe hinzufügen“, aus dem Kontextmenü einer Reihe diese Reihe.
    public func entryFocus(row: UUID?) -> Focus {
        if let row, layout.index(of: row) != nil { return .row(row) }
        return .add
    }

    /// Rückkehr aus dem Browser (N4): oberste neue Reihe, sonst bleibt der Fokus, wo er war.
    public func focusAfterBrowser(previous: Focus) -> Focus {
        if let top = rows.first(where: { isNew($0.id) }) { return .row(top.id) }
        if case .row(let id) = previous, layout.index(of: id) == nil { return rows.first.map { .row($0.id) } ?? .add }
        return previous
    }

    /// Fremde Änderung übernehmen (Handy-Seite, Kit-Abgleich, anderer Bildschirm). „Neu“-Marken bleiben, soweit die
    /// Reihen noch da sind; ein laufendes Verschieben bricht ab. false = nichts zu tun.
    @discardableResult
    public mutating func adopt(layout new: HomeLayout, hidden newHidden: [HomeRow]) -> Bool {
        guard new != layout || newHidden != hidden else { return false }
        editor = HomeEditor(layout: new, added: editor.added)
        hidden = newHidden
        moving = nil
        return true
    }

    /// Nach einer fremden Einfügung (Kit-Auswahl im Browser legt die Reihe über den Kit-Abgleich an): als „neu“ merken.
    @discardableResult
    public mutating func markAdded(key: String) -> HomeRow? {
        guard let row = layout.row(withKey: key) else { return nil }
        if !isNew(row.id) { editor = HomeEditor(layout: layout, added: editor.added + [row.id]) }
        return row
    }

    // MARK: Aktionsleiste

    public mutating func moveToTop(_ id: UUID) -> Outcome {
        let m = editor.moveToTop(id)
        return outcome(id, m)
    }

    public mutating func moveToBottom(_ id: UUID) -> Outcome {
        let m = editor.moveToBottom(id)
        return outcome(id, m)
    }

    /// „An Position …“, `position` 1-basiert (wird begrenzt).
    public mutating func move(_ id: UUID, toPosition position: Int) -> Outcome {
        let m = editor.move(id, to: position - 1)
        return outcome(id, m)
    }

    private func outcome(_ id: UUID, _ m: RowMove?) -> Outcome {
        guard let m, let at = layout.index(of: id) else { return Outcome(event: nil, focus: entryFocus(row: id)) }
        return Outcome(event: .moved(rows[at], m), focus: .row(id))
    }

    public mutating func cycleStyle(_ id: UUID) -> Outcome {
        guard editor.cycleStyle(id) != nil, let at = layout.index(of: id) else { return Outcome(event: nil, focus: entryFocus(row: id)) }
        return Outcome(event: .styled(rows[at]), focus: .row(id))
    }

    /// Ausblenden (nach Rückfrage in der Oberfläche). Fokus auf die Reihe, die nachrückt, am Ende auf die davor,
    /// ohne Reihen auf „Reihe hinzufügen“.
    public mutating func hide(_ id: UUID) -> Outcome {
        guard let h = editor.hide(id, into: &hidden) else { return Outcome(event: nil, focus: entryFocus(row: nil)) }
        if moving?.id == id { moving = nil }
        return Outcome(event: .hidden(h.row, at: h.at), focus: focusNear(h.at))
    }

    /// „Wieder einblenden“: unten anhängen, Fokus auf die Reihe. Lag der Inhalt schon auf der Startseite,
    /// verschwindet nur der Eintrag (kein Ereignis), Fokus auf die vorhandene Reihe.
    public mutating func restore(_ id: UUID) -> Outcome {
        switch editor.restore(id, from: &hidden) {
        case let .restored(row, at)?: Outcome(event: .restored(row, at: at), focus: .row(row.id))
        case let .alreadyOnHome(row)?: Outcome(event: nil, focus: .row(row.id))
        case nil: Outcome(event: nil, focus: restorable.first.map { .hidden($0.id) } ?? entryFocus(row: nil))
        }
    }

    private func focusNear(_ index: Int) -> Focus {
        guard !rows.isEmpty else { return .add }
        return .row(rows[min(index, rows.count - 1)].id)
    }

    // MARK: Verschiebemodus („Verschieben“: ▲▼ verschiebt, OK legt ab, Menu stellt die alte Stelle wieder her)

    @discardableResult
    public mutating func beginMove(_ id: UUID) -> Bool {
        guard let from = layout.index(of: id) else { return false }
        editor.grab(id)
        moving = Moving(id: id, from: from)
        return true
    }

    /// Ein Schritt nach oben (`up`) bzw. unten. false = am Rand oder kein Verschiebemodus.
    @discardableResult
    public mutating func step(up: Bool) -> Bool {
        guard let m = moving, let before = layout.index(of: m.id) else { return false }
        if up { editor.moveUp() } else { editor.moveDown() }
        return layout.index(of: m.id) != before
    }

    /// OK: ablegen. Ereignis nur, wenn die Reihe wirklich woanders steht.
    public mutating func endMove() -> Outcome {
        guard let m = moving else { return Outcome(event: nil, focus: .add) }
        moving = nil
        editor.grab(nil)
        guard let to = layout.index(of: m.id) else { return Outcome(event: nil, focus: .add) }
        let event: Event? = to == m.from ? nil : .moved(rows[to], RowMove(from: m.from, to: to))
        return Outcome(event: event, focus: .row(m.id))
    }

    /// OK auf einem fremd geänderten Stand (F-b2-Review m3): `current` ist das Profil jetzt (z. B. nach einer Handy-Änderung
    /// während des Verschiebens). Übernommen wird der aktuelle Stand, nur die verschobene Reihe kommt an ihre neue Stelle.
    /// Ist sie dort inzwischen verschwunden, bleibt es beim aktuellen Stand (kein Ereignis).
    public mutating func endMove(onto current: HomeLayout, hidden currentHidden: [HomeRow]) -> Outcome {
        guard let m = moving, let to = layout.index(of: m.id) else { return endMove() }
        moving = nil
        editor = HomeEditor(layout: current, added: editor.added)
        hidden = currentHidden
        guard layout.index(of: m.id) != nil else { return Outcome(event: nil, focus: entryFocus(row: nil)) }
        guard let move = editor.move(m.id, to: to), let at = layout.index(of: m.id) else {
            return Outcome(event: nil, focus: .row(m.id))
        }
        return Outcome(event: .moved(rows[at], move), focus: .row(m.id))
    }

    /// Menu: alte Stelle wiederherstellen.
    public mutating func cancelMove() -> Outcome {
        guard let m = moving else { return Outcome(event: nil, focus: .add) }
        moving = nil
        editor.grab(nil)
        editor.move(m.id, to: m.from)
        return Outcome(event: nil, focus: entryFocus(row: m.id))
    }

    // MARK: Browser

    /// OK auf einem Eintrag mit Inhalt: einmal OK hängt unten an, nochmal OK nimmt die eben hinzugefügte Reihe zurück.
    /// Reihen, die schon vorher auf der Startseite lagen, nimmt ein einzelner OK nicht weg (Rückfrage, dann `hide`).
    /// Liegt der Inhalt unter „Ausgeblendet“, kommt die gemerkte Reihe mit Stil zurück und der Eintrag verschwindet
    /// (wie auf der Handy-Seite, F-b2-Review M6).
    public mutating func toggle(_ content: RowContent, style: RowStyle? = nil) -> BrowserToggle {
        if let existing = layout.row(withKey: content.key), let at = layout.index(of: existing.id) {
            guard isNew(existing.id) else { return .confirmHide(existing) }
            editor.remove(existing.id)
            return .removed(existing, at: at)
        }
        let id = editor.insert(content, style: style, hidden: &hidden)
        let at = layout.index(of: id) ?? (count - 1)
        return .added(rows[at], at: at)
    }
}

/// Welle F-b2: Angaben einer Zeile im Verwalter (`ManagedRowLine`): Art · Stil und Herkunft.
public struct ManagedRowInfo: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case list, collection }

    public var kind: Kind
    public var style: RowStyle
    /// „AIOStreams“, „Fusion-Kit“, „Trakt“, „Sonderliste“ …
    public var origin: String

    /// „Liste · Poster“ bzw. „Collection · Kacheln“.
    public var detail: String {
        DesignText.metaLine([kind == .list ? "Liste" : "Collection", style.displayName])
    }

    /// - Parameter addonName: Name eines installierten Addons zur Addon-ID (nil = nicht mehr installiert).
    public init(row: HomeRow, addonName: (String) -> String? = { _ in nil }) {
        style = row.style
        switch row.content {
        case .list(let s):
            kind = .list
            if FusionImport.isKitID(s.id) {
                origin = RowCatalogGroup.Kind.kit.title
            } else {
                switch s.kind {
                case .addon(let addonId, _, _): origin = addonName(addonId) ?? "Addon"
                case .trakt: origin = RowCatalogGroup.Kind.trakt.title
                case .tmdbDiscover, .tmdbList, .tmdbCompany, .tmdbCollection: origin = "TMDB"
                case .continueWatching, .watchlist, .upcoming: origin = "Sonderliste"
                }
            }
        case .collection(let id):
            kind = .collection
            if FusionImport.isKitID(id) { origin = RowCatalogGroup.Kind.kit.title }
            else if ReadyPackages.all.contains(where: { $0.id == id }) { origin = "Fertiges Paket" }
            else { origin = "Eigene Collection" }
        }
    }
}
