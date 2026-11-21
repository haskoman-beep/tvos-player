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

/// Eine Zeile im Abschnitt „Startseite ordnen“. `id` ist bei gezeigten Reihen die Reihen-UUID,
/// bei ausgeblendeten der `RowContent.key` (Reihe gibt es noch nicht auf der Startseite).
public struct PhoneHomeRow: Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public init(id: String, title: String, detail: String = "") { self.id = id; self.title = title; self.detail = detail }
}

/// Was die Handy-Seite von der Startseite zeigt: Reihen in Reihenfolge und was sich einblenden lässt.
public struct PhoneHomeState: Equatable, Sendable {
    public var shown: [PhoneHomeRow]
    public var hidden: [PhoneHomeRow]
    public init(shown: [PhoneHomeRow] = [], hidden: [PhoneHomeRow] = []) { self.shown = shown; self.hidden = hidden }
    public static let empty = PhoneHomeState()

    /// Gezeigt = Reihen der Startseite; ausgeblendet = Angebote (`options`), die dort noch nicht liegen.
    public static func make(layout: HomeLayout, options: [RowContent],
                            title: (RowContent) -> String, detail: (RowContent) -> String = { _ in "" }) -> PhoneHomeState {
        let used = Set(layout.rows.map(\.content.key))
        var seen: Set<String> = []
        let hidden = options.filter { !used.contains($0.key) && seen.insert($0.key).inserted }
        return PhoneHomeState(shown: layout.rows.map { PhoneHomeRow(id: $0.id.uuidString, title: title($0.content), detail: detail($0.content)) },
                              hidden: hidden.map { PhoneHomeRow(id: $0.key, title: title($0), detail: detail($0)) })
    }

    /// Formularwert `op` → Befehl. Formen: `up:`, `down:`, `top:`, `bottom:`, `hide:` + UUID, `to:` + UUID + `:` + Ziel,
    /// `show:` + Inhaltsschlüssel. Unbekannte Reihen, unbekannte Schlüssel und Leerlauf-Züge ergeben nil.
    public func command(op raw: String) -> PhoneCommand? {
        guard let c = raw.firstIndex(of: ":") else { return nil }
        let verb = String(raw[..<c]), rest = String(raw[raw.index(after: c)...])
        if verb == "show" {
            return hidden.contains { $0.id == rest } ? .addRow(key: rest) : nil
        }
        var idPart = rest, target: Int?
        if verb == "to" {
            guard let c2 = rest.lastIndex(of: ":"), let n = Int(rest[rest.index(after: c2)...]) else { return nil }
            idPart = String(rest[..<c2]); target = n
        }
        guard let id = UUID(uuidString: idPart), let i = shown.firstIndex(where: { $0.id == id.uuidString }) else { return nil }
        let last = shown.count - 1
        let to: Int
        switch verb {
        case "up": to = i - 1
        case "down": to = i + 1
        case "top": to = 0
        case "bottom": to = last
        case "to": to = target ?? i
        case "hide": return .removeRow(id)
        default: return nil
        }
        let clamped = min(max(to, 0), last)
        return clamped == i ? nil : .moveRow(id: id, to: clamped)
    }
}

extension PhoneCommand {
    /// Befehle aus „Startseite ordnen“: werden sofort (synchron) übernommen, damit die Antwortseite den neuen Stand zeigt.
    public var isHomeEdit: Bool {
        switch self {
        case .moveRow, .removeRow, .addRow: true
        default: false
        }
    }
}

extension HomeLayout {
    /// Ergebnis eines Handy-Befehls für Log und Rückmeldung.
    public enum PhoneEdit: Equatable, Sendable {
        case moved(from: Int, to: Int)
        case removed(at: Int)
        case added(at: Int)
    }

    /// Wendet einen Befehl aus „Startseite ordnen“ an. `options` löst den Schlüssel von `addRow` auf.
    /// Neue Reihen kommen ans Ende (Nutzerentscheidung 21.11.). nil = nichts geändert.
    // wird nach F-b1-Merge auf HomeEditor umgestellt
    @discardableResult
    public mutating func applyPhone(_ command: PhoneCommand, options: [RowContent]) -> PhoneEdit? {
        switch command {
        case .moveRow(let id, let to):
            guard let i = rows.firstIndex(where: { $0.id == id }) else { return nil }
            let target = min(max(to, 0), rows.count - 1)
            guard target != i else { return nil }
            let row = rows.remove(at: i)
            rows.insert(row, at: target)
            return .moved(from: i, to: target)
        case .removeRow(let id):
            guard let i = rows.firstIndex(where: { $0.id == id }) else { return nil }
            rows.remove(at: i)
            return .removed(at: i)
        case .addRow(let key):
            guard !rows.contains(where: { $0.content.key == key }),
                  let content = options.first(where: { $0.key == key }) else { return nil }
            rows.append(HomeRow(content: content))
            return .added(at: rows.count - 1)
        default:
            return nil
        }
    }
}
