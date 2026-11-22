import Foundation

/// Welle F-e: Abschnitte der Handy-Seite, gleiche Reihenfolge und Namen wie im Zielbaum (UX-Plan §2.3).
/// `rawValue` ist der Anker in der URL (`…/?t=…#home`); der Fernseher öffnet die QR-Seite damit.
public enum PhoneSection: String, CaseIterable, Sendable {
    case quickImport = "import"
    case addon
    case keys
    case home
    case system

    public var title: String {
        switch self {
        case .quickImport: "Schnell-Import"
        case .addon: "Addons"
        case .keys: "Konten & Schlüssel"
        case .home: "Startseite"
        case .system: "System"
        }
    }

    /// Adresse der Handy-Seite mit Anker (nil = ohne Anker).
    public static func url(_ base: String, section: PhoneSection?) -> String {
        guard let section else { return base }
        return base + "#" + section.rawValue
    }
}

/// Eine Zeile im Abschnitt „Startseite ordnen“. `id` ist bei gezeigten und ausgeblendeten Reihen die Reihen-UUID,
/// bei weiteren Angeboten der `RowContent.key` (Reihe gibt es noch nicht).
public struct PhoneHomeRow: Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public init(id: String, title: String, detail: String = "") { self.id = id; self.title = title; self.detail = detail }
}

/// Was die Handy-Seite von der Startseite zeigt: Reihen in Reihenfolge, ausgeblendete Reihen und weitere Angebote.
public struct PhoneHomeState: Equatable, Sendable {
    public var shown: [PhoneHomeRow]
    public var hidden: [PhoneHomeRow]
    public var more: [PhoneHomeRow]
    public init(shown: [PhoneHomeRow] = [], hidden: [PhoneHomeRow] = [], more: [PhoneHomeRow] = []) {
        self.shown = shown; self.hidden = hidden; self.more = more
    }
    public static let empty = PhoneHomeState()

    /// Gezeigt = Reihen der Startseite; ausgeblendet = gemerkte Reihen (neueste zuerst), ohne die, deren Inhalt
    /// inzwischen wieder auf der Startseite liegt (F-e N1: kein „Wieder einblenden“, das nichts ändert);
    /// weitere = Angebote (`options`), die weder gezeigt noch ausgeblendet sind.
    public static func make(layout: HomeLayout, hiddenRows: [HomeRow] = [], options: [RowContent],
                            title: (RowContent) -> String, detail: (RowContent) -> String = { _ in "" }) -> PhoneHomeState {
        var seen = Set(layout.rows.map(\.content.key)).union(hiddenRows.map(\.content.key))
        let more = options.filter { seen.insert($0.key).inserted }
        func line(_ r: HomeRow) -> PhoneHomeRow { PhoneHomeRow(id: r.id.uuidString, title: title(r.content), detail: detail(r.content)) }
        return PhoneHomeState(shown: layout.rows.map(line), hidden: layout.restorable(hiddenRows).map(line),
                              more: more.map { PhoneHomeRow(id: $0.key, title: title($0), detail: detail($0)) })
    }

    /// Formularwert `op` → Befehl. Formen: `to:` + UUID + `:` + Ziel (absolut, wiederholbar ohne Doppelwirkung),
    /// `hide:` / `restore:` + UUID, `show:` + Inhaltsschlüssel. Unbekanntes und Leerlauf-Züge ergeben nil.
    public func command(op raw: String) -> PhoneCommand? {
        guard let c = raw.firstIndex(of: ":") else { return nil }
        let verb = String(raw[..<c]), rest = String(raw[raw.index(after: c)...])
        switch verb {
        case "show":
            return more.contains { $0.id == rest } ? .addRow(key: rest) : nil
        case "restore":
            guard let id = UUID(uuidString: rest), hidden.contains(where: { $0.id == id.uuidString }) else { return nil }
            return .restoreRow(id)
        case "hide":
            guard let id = UUID(uuidString: rest), shown.contains(where: { $0.id == id.uuidString }) else { return nil }
            return .removeRow(id)
        case "delete":
            guard let id = UUID(uuidString: rest), shown.contains(where: { $0.id == id.uuidString }) else { return nil }
            return .deleteRow(id)
        case "to":
            guard let c2 = rest.lastIndex(of: ":"), let n = Int(rest[rest.index(after: c2)...]),
                  let id = UUID(uuidString: String(rest[..<c2])),
                  let i = shown.firstIndex(where: { $0.id == id.uuidString }) else { return nil }
            let to = min(max(n, 0), shown.count - 1)
            return to == i ? nil : .moveRow(id: id, to: to)
        default:
            return nil
        }
    }
}

extension PhoneCommand {
    /// Befehle aus „Startseite ordnen“: werden sofort (synchron) übernommen, damit die Antwortseite den neuen Stand zeigt.
    public var isHomeEdit: Bool {
        switch self {
        case .moveRow, .removeRow, .deleteRow, .restoreRow, .addRow: true
        default: false
        }
    }
}

extension HomeLayout {
    /// Höchstzahl gemerkter ausgeblendeter Reihen; die älteste fällt zuerst heraus.
    public static let hiddenLimit = 50

    /// Ergebnis eines Handy-Befehls für Log und Rückmeldung (mit der betroffenen Reihe).
    public enum PhoneEdit: Equatable, Sendable {
        case moved(HomeRow, from: Int, to: Int)
        case removed(HomeRow, at: Int)
        /// Welle F-f: gelöscht (nicht unter „Ausgeblendet“).
        case deleted(HomeRow, at: Int)
        case restored(HomeRow, at: Int)
        case added(HomeRow, at: Int)
    }

    /// Wendet einen Befehl aus „Startseite ordnen“ an, über `HomeEditor` (dieselben Regeln wie der Verwalter am
    /// Fernseher). `hidden` sind die gemerkten ausgeblendeten Reihen (`Profile.hiddenRows`), `options` löst den
    /// Schlüssel von `addRow` auf. Eingeblendetes kommt ans Ende (Nutzerentscheidung 21.11.). nil = Startseite
    /// unverändert (beim Wiedereinblenden eines schon gezeigten Inhalts wird nur `hidden` aufgeräumt).
    @discardableResult
    public mutating func applyPhone(_ command: PhoneCommand, hidden: inout [HomeRow], options: [RowContent]) -> PhoneEdit? {
        var editor = HomeEditor(layout: self)
        defer { self = editor.layout }
        switch command {
        case .moveRow(let id, let to):
            guard let m = editor.move(id, to: to) else { return nil }
            return .moved(editor.layout.rows[m.to], from: m.from, to: m.to)
        case .removeRow(let id):
            guard let h = editor.hide(id, into: &hidden) else { return nil }
            return .removed(h.row, at: h.at)
        case .deleteRow(let id):
            guard let d = editor.delete(id) else { return nil }
            return .deleted(d.row, at: d.at)
        case .restoreRow(let id):
            guard case .restored(let row, let at)? = editor.restore(id, from: &hidden) else { return nil }
            return .restored(row, at: at)
        case .addRow(let key):
            guard editor.layout.row(withKey: key) == nil, let content = options.first(where: { $0.key == key }) else { return nil }
            let id = editor.insert(content, hidden: &hidden)
            guard let at = editor.layout.index(of: id) else { return nil }
            return .added(editor.layout.rows[at], at: at)
        default:
            return nil
        }
    }
}
