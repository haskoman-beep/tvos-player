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
        case .addon: "Addons & Quellen"
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

    /// Gezeigt = Reihen der Startseite; ausgeblendet = gemerkte Reihen (neueste zuerst);
    /// weitere = Angebote (`options`), die weder gezeigt noch ausgeblendet sind.
    public static func make(layout: HomeLayout, hiddenRows: [HomeRow] = [], options: [RowContent],
                            title: (RowContent) -> String, detail: (RowContent) -> String = { _ in "" }) -> PhoneHomeState {
        var seen = Set(layout.rows.map(\.content.key)).union(hiddenRows.map(\.content.key))
        let more = options.filter { seen.insert($0.key).inserted }
        func line(_ r: HomeRow) -> PhoneHomeRow { PhoneHomeRow(id: r.id.uuidString, title: title(r.content), detail: detail(r.content)) }
        return PhoneHomeState(shown: layout.rows.map(line), hidden: hiddenRows.reversed().map(line),
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
        case .moveRow, .removeRow, .restoreRow, .addRow: true
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
        case restored(HomeRow, at: Int)
        case added(HomeRow, at: Int)
    }

    /// Wendet einen Befehl aus „Startseite ordnen“ an. `hidden` sind die gemerkten ausgeblendeten Reihen
    /// (`Profile.hiddenRows`), `options` löst den Schlüssel von `addRow` auf. Eingeblendetes kommt ans Ende
    /// (Nutzerentscheidung 21.11.). nil = nichts geändert.
    // wird nach F-b1-Merge auf HomeEditor umgestellt
    @discardableResult
    public mutating func applyPhone(_ command: PhoneCommand, hidden: inout [HomeRow], options: [RowContent]) -> PhoneEdit? {
        switch command {
        case .moveRow(let id, let to):
            guard let i = rows.firstIndex(where: { $0.id == id }) else { return nil }
            let target = min(max(to, 0), rows.count - 1)
            guard target != i else { return nil }
            let row = rows.remove(at: i)
            rows.insert(row, at: target)
            return .moved(row, from: i, to: target)
        case .removeRow(let id):
            guard let i = rows.firstIndex(where: { $0.id == id }) else { return nil }
            let row = rows.remove(at: i)
            hidden.removeAll { $0.id == row.id || $0.content.key == row.content.key }
            hidden.append(row)
            if hidden.count > Self.hiddenLimit { hidden.removeFirst(hidden.count - Self.hiddenLimit) }
            return .removed(row, at: i)
        case .restoreRow(let id):
            guard let j = hidden.firstIndex(where: { $0.id == id }) else { return nil }
            let row = hidden.remove(at: j)
            // Liegt der Inhalt inzwischen schon auf der Startseite, nur aus „Ausgeblendet“ nehmen.
            guard !rows.contains(where: { $0.id == row.id || $0.content.key == row.content.key }) else { return nil }
            rows.append(row)
            return .restored(row, at: rows.count - 1)
        case .addRow(let key):
            guard !rows.contains(where: { $0.content.key == key }),
                  let content = options.first(where: { $0.key == key }) else { return nil }
            let row = HomeRow(content: content)
            rows.append(row)
            hidden.removeAll { $0.content.key == key }
            return .added(row, at: rows.count - 1)
        default:
            return nil
        }
    }
}
