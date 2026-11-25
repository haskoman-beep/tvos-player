import Foundation

/// Welle F-h3: wie Ton & Untertitel im Player öffnen (Einstellung je Profil, `PlayerComfortSettings.trackPanelStyle`).
/// Task 5.4: the three styles are the three looks of `player.trackPanel` (`look`, same table as `LookMigration`);
/// the gestures stay those of build 198 (topBar: ▼ / swipe down, bottomBar and menu: ▲ / swipe up).
public enum TrackPanelStyle: String, Codable, Sendable, CaseIterable {
    /// „Seite“: panel from the right, full height, Ton over Untertitel over Versatz (Wisch nach unten / ▼), Standard.
    case topBar
    /// „Unten“: card over the lower edge, columns side by side (Wisch nach oben / ▲).
    case bottomBar
    /// „Mitte“: dimmed picture, card in the middle, columns side by side (Wisch nach oben / ▲).
    case menu

    /// The look value of this style.
    public var look: LookTrackPanel {
        switch self {
        case .topBar: .seite
        case .bottomBar: .unten
        case .menu: .mitte
        }
    }

    /// The style of a look value.
    public init(_ look: LookTrackPanel) {
        self = switch look {
        case .seite: .topBar
        case .unten: .bottomBar
        case .mitte: .menu
        }
    }

    public var title: String {
        switch self {
        case .topBar: "Seite"
        case .bottomBar: "Unten"
        case .menu: "Mitte"
        }
    }

    /// Erklärung in den Einstellungen.
    public var detail: String {
        switch self {
        case .topBar: "Wisch nach unten öffnet ein Panel von rechts: Ton, darunter Untertitel und Versatz."
        case .bottomBar: "Wisch nach oben öffnet eine Karte am unteren Rand mit den Spalten Ton, Untertitel und Versatz."
        case .menu: "Wisch nach oben öffnet eine Karte in der Mitte mit den Spalten Ton, Untertitel und Versatz; das Bild wird abgedunkelt."
        }
    }

    /// Bedeckt den unteren Bildrand bzw. das Bild (dann Steuerleiste ausblenden, Untertitel ggf. anheben).
    public var coversBottom: Bool { self != .topBar }

    /// Task 5.4: the side panel stacks its columns (one list from top to bottom), the others put them side by side.
    public var isStacked: Bool { self == .topBar }
}

/// Senkrechte Eingabe auf der Fernbedienung: Wisch (Touchfläche) oder Klick auf den Rand bzw. Steuerkreuz.
public enum TrackPanelGesture: Equatable, Sendable {
    case swipeDown, swipeUp, clickDown, clickUp

    public var isSwipe: Bool { self == .swipeDown || self == .swipeUp }

    public var logText: String {
        switch self {
        case .swipeDown: "Wisch nach unten"
        case .swipeUp: "Wisch nach oben"
        case .clickDown: "▼ Klick"
        case .clickUp: "▲ Klick"
        }
    }
}

extension TrackPanelEntry {
    /// Öffnet diese Geste in diesem Stil das Panel bzw. Menü? Die jeweils andere Richtung tut nichts (wie bisher
    /// Wisch nach oben bei „Leiste oben“). F-h3 R1 M1: ▲ öffnet das Menü auch bei sichtbarer Steuerleiste – sie hat
    /// keine fokussierbaren Elemente, und G-a hält nur ◀/▶; so verhält sich ▲ wie bei „Leiste unten“.
    public static func opens(style: TrackPanelStyle, gesture: TrackPanelGesture) -> Bool {
        switch (style, gesture) {
        case (.topBar, .swipeDown), (.topBar, .clickDown): true
        case (.bottomBar, .swipeUp), (.bottomBar, .clickUp): true
        case (.menu, .swipeUp), (.menu, .clickUp): true
        default: false
        }
    }

    /// Welle F-h3: Geste → Schritt je Stil. Gehört die Geste nicht zum Stil, `.ignore(.otherGesture)` vor allem
    /// anderen (bricht auch kein Up-next ab); sonst wie `decide(leaving:…)`.
    public static func decide(style: TrackPanelStyle, gesture: TrackPanelGesture,
                              leaving: Bool, scrubbing: Bool, upNextShowing: Bool, failureShowing: Bool,
                              alreadyOpen: Bool, skipPromptShowing: Bool, lock: TrackLock?) -> Step {
        guard opens(style: style, gesture: gesture) else { return .ignore(.otherGesture) }
        return decide(leaving: leaving, scrubbing: scrubbing, upNextShowing: upNextShowing, failureShowing: failureShowing,
                      alreadyOpen: alreadyOpen, skipPromptShowing: skipPromptShowing, lock: lock)
    }
}

extension TrackPanelLayout {
    /// Welle F-h3: schließt ein Wisch im offenen Panel? Seite: Wisch nach oben aus der obersten Zeile des Panels.
    /// Leiste unten: Wisch nach unten aus der untersten Zeile. Sonst ist es ein Listenschritt. Menü: nie (Menü-Taste).
    /// Ohne Fokus oder in einer leeren Spalte schließt der passende Wisch immer.
    /// Task 5.4: the side panel („Seite“) stacks the columns, so only the first row of the first column with rows is
    /// the top edge; a swipe up from the top row of Untertitel is a step up into Ton.
    public static func closesOnSwipe(_ gesture: TrackPanelGesture, style: TrackPanelStyle, startSpot: TrackPanelSpot?,
                                     columns: [TrackPanelColumnModel]) -> Bool {
        switch (style, gesture) {
        case (.topBar, .swipeUp):
            guard let s = startSpot, let c = columns.first(where: { $0.column == s.column }), !c.rows.isEmpty else { return true }
            guard let top = columns.first(where: { !$0.rows.isEmpty }) else { return true }
            return top.column == s.column && top.rows.first?.id == s.row
        case (.bottomBar, .swipeDown):
            guard let s = startSpot, let c = columns.first(where: { $0.column == s.column }), let last = c.rows.last else { return true }
            return last.id == s.row
        default: return false
        }
    }
}

/// Welle F-h3: Eintrag der ersten Menü-Ebene („Ton ›“ mit der laufenden Spur als zweite Zeile).
public struct TrackMenuEntry: Equatable, Sendable, Identifiable {
    public var column: TrackPanelColumn
    public var title: String
    /// Laufende Wahl („Englisch · Dolby Atmos 5.1“, „Aus“, „+0,3 s“).
    public var detail: String
    /// „lädt…“, „gesperrt“, „bis Play gesperrt“, „wirkt hier nicht“.
    public var note: String?
    public var isLocked: Bool
    /// Keine Zeilen (z. B. keine Tonspuren): nicht wählbar.
    public var isEmpty: Bool
    public var id: TrackPanelColumn { column }
}

/// Welle F-h3: Navigation im kleinen Menü. Ebene 1: Ton / Untertitel / Versatz; Ebene 2: Liste der Spalte.
/// Menü-Taste: eine Ebene zurück, auf Ebene 1 schließen.
public struct TrackMenuNav: Equatable, Sendable {
    public enum Level: Equatable, Sendable {
        case root
        case list(TrackPanelColumn)
    }

    public enum Back: Equatable, Sendable { case toRoot, close }

    public private(set) var level: Level = .root
    /// Eintrag der ersten Ebene, der den Fokus bekommt (nach Zurück der zuletzt geöffnete).
    public private(set) var rootFocus: TrackPanelColumn

    public init(rootFocus: TrackPanelColumn = .audio) { self.rootFocus = rootFocus }

    /// Startzustand: Ebene 1, Fokus auf dem ersten wählbaren Eintrag (Ton, ohne Tonspuren Untertitel).
    public init(entries: [TrackMenuEntry]) {
        rootFocus = entries.first(where: { !$0.isLocked && !$0.isEmpty })?.column ?? .audio
    }

    /// Eintrag öffnen; gesperrt oder leer bleibt es auf Ebene 1. Rückgabe: geöffnet.
    @discardableResult
    public mutating func open(_ entry: TrackMenuEntry) -> Bool {
        guard level == .root, !entry.isLocked, !entry.isEmpty else { return false }
        rootFocus = entry.column
        level = .list(entry.column)
        return true
    }

    /// Menü-Taste.
    public mutating func back() -> Back {
        guard case .list(let c) = level else { return .close }
        rootFocus = c
        level = .root
        return .toRoot
    }

    /// Nach einer Wahl: Ton und Untertitel zurück auf Ebene 1 (die neue Spur steht dort als zweite Zeile),
    /// Versatz bleibt in der Liste (mehrere Schritte nacheinander).
    public mutating func picked(_ column: TrackPanelColumn) {
        guard level == .list(column), column != .offset else { return }
        rootFocus = column
        level = .root
    }

    /// Einträge der ersten Ebene aus den Spalten (nach `TrackPanelLayout.applying`).
    public static func entries(_ columns: [TrackPanelColumnModel], offset: Double) -> [TrackMenuEntry] {
        columns.map { c in
            let detail: String
            switch c.column {
            case .audio: detail = c.rows.first(where: \.isActive)?.line ?? (c.rows.isEmpty ? "Keine Tonspuren" : "–")
            case .subtitles: detail = c.rows.first(where: \.isActive)?.line ?? "Aus"
            case .offset: detail = SubtitleOffset.label(offset)
            }
            return TrackMenuEntry(column: c.column, title: c.column.title, detail: detail, note: c.note,
                                  isLocked: c.isLocked, isEmpty: c.rows.isEmpty)
        }
    }
}

/// Welle F-h3: Breite des kleinen Menüs (Ebene 2 nimmt dasselbe Zeichenbudget wie eine Spalte dieser Breite).
public enum TrackMenuMetrics {
    public static let width: Double = 720
    /// Höchstens so viele Zeilen sichtbar, der Rest scrollt.
    public static let maxVisibleRows = 6
    /// Höhe einer einzeiligen Zeile (31 pt `.callout`, Innenrand 2 × `Space.xs`, Abstand 2) für die Listenhöhe.
    public static let rowHeight: Double = 55
}
