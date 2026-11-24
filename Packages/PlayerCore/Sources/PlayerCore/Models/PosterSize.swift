import Foundation

/// Welle F-f: Form einer Kachel in einer Reihe (Grundmaß bei „Mittel“, der heutigen Größe).
public enum TileKind: String, Sendable, CaseIterable {
    /// Hochformat 240 × 360 (Poster-, Top-10- und „Heute neu“-Reihen).
    case poster
    /// Querformat 440 × 248 (Querformat-Reihen, Collection-Kacheln).
    case landscape
    /// Logo-Kachel 320 × 180 (Collection mit Logos).
    case logo
    /// Großes Titelbild 1600 × 620 (Stil „Hero“); skaliert nicht mit.
    case hero
}

/// Welle F-f: „Postergröße“ Klein / Mittel / Groß (`Appearance.cardSize`, Mittel = bisherige Größe).
/// Reine Rechnung: Kachelmaße je Stil, Abstand und Anzahl der Platzhalter beim Laden einer Reihe.
/// Plaketten und Schrift skalieren nicht mit (bleiben auf 3 m lesbar).
public enum PosterSize {
    /// Grundmaße bei Faktor 1 (Mittel).
    public static func baseSize(_ kind: TileKind) -> CGSize {
        switch kind {
        case .poster: CGSize(width: 240, height: 360)
        case .landscape: CGSize(width: 440, height: 248)
        case .logo: CGSize(width: 320, height: 180)
        case .hero: CGSize(width: 1600, height: 620)
        }
    }

    /// Kachelform eines Reihenstils (Top 10 = Poster mit Rangziffer davor).
    public static func kind(for style: RowStyle) -> TileKind {
        switch style {
        case .poster, .top10: .poster
        case .landscape, .collectionTiles: .landscape
        case .logoTiles: .logo
        case .hero: .hero
        }
    }

    /// Faktor einer Größe; das Seitenverhältnis bleibt.
    public static func scale(_ size: CardSize) -> CGFloat { size.scale }

    /// Maße einer Kachel bei Faktor `scale` (Hero bleibt fest).
    public static func tileSize(_ kind: TileKind, scale: CGFloat) -> CGSize {
        let b = baseSize(kind)
        guard kind != .hero else { return b }
        return CGSize(width: b.width * scale, height: b.height * scale)
    }

    public static func tileSize(for size: CardSize, style: RowStyle) -> CGSize {
        tileSize(kind(for: style), scale: scale(size))
    }

    /// Breite der Kachel eines Stils (ohne Rangziffer bei Top 10).
    public static func tileWidth(for size: CardSize, style: RowStyle) -> CGFloat { tileSize(for: size, style: style).width }

    public static func tileHeight(for size: CardSize, style: RowStyle) -> CGFloat { tileSize(for: size, style: style).height }

    /// Abstand Karte ↔ Karte in einer Reihe (`space.m` = 20, mit skaliert).
    public static func spacing(scale: CGFloat) -> CGFloat { 20 * scale }

    /// Platzhalter beim Laden: so viele, dass die sichtbare Breite (ab dem Rand 80) gefüllt ist, mindestens 1,
    /// höchstens 12. Top 10 hat davor noch die Rangziffer (rund 190 · Faktor breiter).
    public static func placeholderCount(for size: CardSize, style: RowStyle, visibleWidth: CGFloat = 1920 - 80) -> Int {
        let s = scale(size)
        var w = tileWidth(for: size, style: style)
        if style == .top10 { w += 190 * s }
        let step = w + spacing(scale: s)
        guard step > 0 else { return 1 }
        return min(12, max(1, Int((visibleWidth / step).rounded(.up))))
    }
}

/// Welle F-f: was eine Listen-Reihe gerade zeigt. Jede Phase hat mindestens ein fokussierbares Element,
/// damit die Fokus-Engine nie an einer Reihe hängen bleibt (Befund build 39: unter der Merkliste kein Weiterkommen).
public enum HomeRowPhase: Equatable, Sendable {
    /// Lädt noch: Platzhalter-Kacheln in Endgröße.
    case loading
    /// Einträge da.
    case items(Int)
    /// Geladen, aber leer: eine Kachel „Keine Einträge“ (bzw. der Grund).
    case empty
    /// Laden fehlgeschlagen: eine Kachel „Laden fehlgeschlagen – erneut versuchen“.
    case failed

    /// Task 4.1a (F-A-2): a collection row uses the same phases (tiles = items); its placeholder hands over too.
    public init(collection p: CollectionRowPhase, count: Int) {
        switch p {
        case .loading: self = .loading
        case .failed: self = .failed
        case .empty: self = .empty
        case .tiles: self = count > 0 ? .items(count) : .empty
        }
    }

    public init(loaded: Bool, failed: Bool, count: Int) {
        if !loaded { self = .loading }
        else if count > 0 { self = .items(count) }
        else if failed { self = .failed }
        else { self = .empty }
    }

    /// Text der Statuskachel (nil = keine Statuskachel).
    public func statusText(empty: String) -> String? {
        switch self {
        case .loading, .items: nil
        case .empty: empty
        case .failed: "Laden fehlgeschlagen – erneut versuchen"
        }
    }

    /// Wohin der Fokus geht, wenn ein Platzhalter (`index`) fokussiert war und die Reihe fertig ist:
    /// gleiche Stelle (begrenzt) bei Einträgen, sonst die Statuskachel (0).
    public func focusAfterLoad(placeholder index: Int) -> Int {
        if case .items(let n) = self { return min(max(index, 0), n - 1) }
        return 0
    }
}

/// Welle F-f: Reihenfolge des Vorladens der Startseite. Listen in der Reihenfolge der Startseite (sichtbare zuerst),
/// jede Quelle einmal; Weiterschauen ist lokal und braucht kein Laden.
public enum HomeRowPreload {
    public static func sources(_ rows: [HomeRow]) -> [CatalogSource] {
        var seen = Set<String>()
        return rows.compactMap { row in
            guard case .list(let s) = row.content, s.kind != .continueWatching, seen.insert(s.id).inserted else { return nil }
            return s
        }
    }

    /// Gleichzeitige Ladungen beim Vorladen (die gerade sichtbaren Reihen laden zusätzlich sofort selbst).
    public static let limit = 4
}

/// Task 4.1a (F-A-5, A-B-8): row entries are told apart by type and id (TMDB film and series share numbers).
extension MetaPreview {
    /// Identity of a card in a row (`ForEach` id).
    public var rowKey: String { type + "|" + id }
}

public enum RowItems {
    /// One entry per (type, id), the first occurrence wins; order stays.
    public static func deduped(_ items: [MetaPreview]) -> [MetaPreview] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.rowKey).inserted }
    }
}

/// Task 4.1a (A-B-5): local calendar day of "Heute neu" (part of the row's load key).
public enum HomeRowDay {
    public static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Seconds until the next local midnight, plus one second so the new day has begun.
    public static func secondsUntilNextDay(_ date: Date, calendar: Calendar = .current) -> Double {
        let start = calendar.startOfDay(for: date)
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(86_400)
        return max(1, next.timeIntervalSince(date) + 1)
    }
}
