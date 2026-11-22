import Foundation

/// Tabs der Hauptnavigation (Plan §3.3). Liegt in PlayerCore, damit die Menu-Kette testbar ist.
public enum AppTab: String, CaseIterable, Hashable, Sendable {
    case home, search, library, calendar, settings

    /// Kurzname fürs Log.
    public var logName: String {
        switch self {
        case .home: "Start"
        case .search: "Suche"
        case .library: "Bibliothek"
        case .calendar: "Kalender"
        case .settings: "Einstellungen"
        }
    }
}

/// Menu/Zurück-Kette (Plan §3.1, N1/N2): jede Ebene geht genau eine Stufe zurück.
public enum MenuChain {
    /// Wo der Fokus beim Menu-Druck liegt.
    public enum Level: Hashable, Sendable {
        /// Offenes Blatt, Dialog oder Vollbild-Überlagerung: schließt sich selbst.
        case sheet
        /// Gepushte Seite im Stack eines Tabs.
        case pushedPage
        /// Rechte Spalte einer zweispaltigen Seite (Einstellungen, Reihen-Browser).
        case rightColumn
        /// Linke Spalte (Kategorie bzw. Quelle).
        case leftColumn
        /// Wurzelseite eines Tabs (Inhalt, nichts gepusht).
        case tabRoot
        /// Tab- bzw. Seitenleiste selbst.
        case tabBar
    }

    public enum Target: Hashable, Sendable {
        /// Das System bzw. die Seite selbst geht zurück (Blatt schließen, Stack poppen, in die Leiste).
        case system
        /// Fokus auf den aktiven Eintrag der linken Spalte.
        case activeCategory
        /// Zum Start-Tab wechseln (N2).
        case startTab
        /// App verlassen (nur auf der Ebene des Start-Tabs).
        case leaveApp
    }

    public static func target(_ level: Level, tab: AppTab) -> Target {
        switch level {
        case .sheet, .pushedPage: return .system
        case .rightColumn: return .activeCategory
        case .leftColumn, .tabRoot:
            // Start: Inhalt → Leiste (System); alle anderen Tabs: erst zum Start-Tab.
            return tab == .home ? .system : .startTab
        case .tabBar:
            return tab == .home ? .leaveApp : .startTab
        }
    }

    /// Menu auf der Tab-Ebene (Wurzel oder Leiste) eines Tabs mit `depth` gepushten Seiten:
    /// true = die App übernimmt (Wechsel zum Start-Tab), false = System-Verhalten (poppen bzw. App verlassen).
    public static func handlesAtTabLevel(tab: AppTab, depth: Int) -> Bool {
        guard depth == 0 else { return false }
        return target(.tabRoot, tab: tab) == .startTab
    }
}

/// Fokus-Rückkehr auf der Detailseite einer Serie (Plan §3.2): „nächste ungesehene Folge“, auch über die
/// Staffelgrenze.
public enum EpisodeFocus {
    /// Ziel-Folge nach dem Player bzw. beim Eintritt.
    /// - `anchor`: zuletzt gespielte Folge (Fortschritt), sonst die gestartete; nil = noch nichts gespielt.
    /// - Ist der Anker noch nicht gesehen (abgebrochen, halb gesehen), bleibt der Fokus dort.
    /// - Sonst die erste ungesehene Folge danach (Staffelgrenze egal), sonst die erste ungesehene davor,
    ///   sonst der Anker selbst bzw. die letzte Folge (alles gesehen).
    /// `episodes` muss sortiert sein (wie `EpisodeRef.list`).
    public static func target(episodes: [EpisodeRef], anchor: EpisodeRef?,
                              isWatched: (EpisodeRef) -> Bool) -> EpisodeRef? {
        guard !episodes.isEmpty else { return nil }
        guard let anchor else { return episodes.first { !isWatched($0) } ?? episodes.first }
        let key = (anchor.season, anchor.episode)
        if let same = episodes.first(where: { ($0.season, $0.episode) == key }), !isWatched(same) { return same }
        if let after = episodes.first(where: { ($0.season, $0.episode) > key && !isWatched($0) }) { return after }
        if let before = episodes.first(where: { ($0.season, $0.episode) < key && !isWatched($0) }) { return before }
        return episodes.first { ($0.season, $0.episode) == key } ?? episodes.last
    }
}

/// Fokus in der Quellenliste (Plan §3.2). IDs in Anzeige-Reihenfolge.
public enum SourceFocus {
    /// Eintritt: zuletzt gespielte Quelle, sonst die erste spielbare, sonst die erste Zeile.
    public static func entry(ids: [String], lastPlayed: String?, isPlayable: (String) -> Bool) -> String? {
        if let lastPlayed, ids.contains(lastPlayed) { return lastPlayed }
        return ids.first(where: isPlayable) ?? ids.first
    }

    /// Nach dem Player: normal beendet → die gespielte Quelle; nach einem Fehler → die nächste spielbare Quelle
    /// unter der gescheiterten (ohne Umlauf), gibt es keine, die erste spielbare darüber, sonst die gescheiterte.
    /// `isPlayable` schließt die in dieser Liste schon gescheiterten Quellen aus.
    public static func afterPlayer(ids: [String], played: String, failed: Bool,
                                   isPlayable: (String) -> Bool) -> String? {
        guard let i = ids.firstIndex(of: played) else { return entry(ids: ids, lastPlayed: nil, isPlayable: isPlayable) }
        guard failed else { return played }
        if let below = ids[(i + 1)...].first(where: { $0 != played && isPlayable($0) }) { return below }
        if let above = ids[..<i].first(where: isPlayable) { return above }
        return played
    }
}

/// Menu im Player (Plan §3.1, N5): offene Überlagerung schließt nur sich selbst, erst bei freiem Bild verlässt
/// Menu den Player. Spulen und Überspringen-Knopf prüft der Player vorher selbst (unverändert).
public enum PlayerMenuStep: Hashable, Sendable {
    case cancelUpNext
    case hideControls
    case leave

    /// - `upNext`: Karte „Nächste Folge in …“ steht.
    /// - `controlsVisible`: Steuerleiste sichtbar; zählt erst, wenn ein Bild da ist (beim Laden verlässt Menu sofort).
    /// - `failed`: Fehler steht auf dem Bildschirm → verlassen, nichts zu schließen.
    public static func decide(upNext: Bool, controlsVisible: Bool, hasPicture: Bool, failed: Bool) -> PlayerMenuStep {
        if failed { return .leave }
        if upNext { return .cancelUpNext }
        if controlsVisible && hasPicture { return .hideControls }
        return .leave
    }
}
