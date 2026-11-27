import Foundation

/// Welle F-g: Zustand einer Collection-Reihe der Startseite. Kit-Collections kommen erst mit ihrer Kit-Datei;
/// bis dahin Platzhalter, schlug die Datei fehl, eine Statuskachel „Laden fehlgeschlagen“ (statt ewig Platzhalter).
public enum CollectionRowPhase: Equatable, Sendable {
    /// Kit-Datei lädt noch (oder ist noch nicht angefragt): Platzhalter.
    case loading
    /// Kit-Datei der Collection schlug fehl und lädt gerade nicht: Statuskachel mit „erneut versuchen“.
    case failed(sourceKey: String)
    /// Collection da, aber ohne Kacheln, oder eigene Collection nicht mehr vorhanden.
    case empty
    /// Kacheln da.
    case tiles

    /// - Parameters:
    ///   - collectionID: ID aus `HomeRowContent.collection`.
    ///   - folders: Kacheln der Collection, nil = (noch) keine Collection zu dieser ID.
    ///   - kitErrors: Ladefehler je Kit-Quelle (`FusionKitStore.errors`), `kitLoading`: laufende Ladungen.
    public static func of(collectionID: String, folders: [Folder]?,
                          kitErrors: [String: String] = [:], kitLoading: Set<String> = []) -> CollectionRowPhase {
        if let folders { return folders.isEmpty ? .empty : .tiles }
        // Eigene Collection ohne Eintrag (gelöscht): kommt nicht mehr, also kein Platzhalter.
        guard let key = FusionImport.sourceKey(ofID: collectionID) else { return .empty }
        if !kitLoading.contains(key), kitErrors[key] != nil { return .failed(sourceKey: key) }
        return .loading
    }

    /// Text der Statuskachel (nil = Platzhalter bzw. Kacheln).
    public var statusText: String? {
        switch self {
        case .failed: "Laden fehlgeschlagen – erneut versuchen"
        case .empty: "Keine Einträge"
        case .loading, .tiles: nil
        }
    }
}

/// Welle F-g: was eine Collection-Reihe an Bildern hat (Logzeile je Reihe, Diagnose fehlender Bilder).
public struct CollectionArtStats: Equatable, Sendable {
    public var tiles: Int
    /// Kacheln mit Bild im gezeigten Stil (Logos: Logo; sonst Standbild oder Hintergrund).
    public var images: Int
    /// Kacheln mit bewegtem Fokusbild (nur außerhalb des Logo-Stils gezeigt).
    public var gifs: Int

    /// Build 6 (review of 576a588): a still row (`TileMotion.isStillRow`, genre rows) shows no GIF and counts none.
    public init(folders: [Folder], logoStyle: Bool, stillRow: Bool = false) {
        tiles = folders.count
        images = folders.filter { logoStyle ? $0.logo != nil : ($0.coverImage ?? $0.backdrop) != nil }.count
        gifs = logoStyle || stillRow ? 0 : folders.filter { $0.focusGif != nil }.count
    }

    /// „Collection <titel>: <n> Kacheln, Bilder <n>, GIF <n>“.
    public func logLine(title: String) -> String {
        "Collection \(title): \(tiles) Kacheln, Bilder \(images), GIF \(gifs)"
    }
}

/// Welle F-g: welche Einzelbilder eines GIFs dekodiert werden. Lange GIFs werden gleichmäßig ausgedünnt,
/// damit eine Kachel nicht mehr als `maxFrames` Bitmaps hält; die Gesamtdauer bleibt gleich.
public enum GIFFramePlan {
    /// Höchstzahl gehaltener Einzelbilder (bei ~520 px Breite etwa 30 MB für die eine fokussierte Kachel).
    public static let maxFrames = 48
    /// Längste Kante der dekodierten Einzelbilder in Pixeln.
    public static let maxPixels = 520
    /// Browser-Regel: Verzögerungen bis einschließlich 10 ms gelten als 100 ms.
    public static let minDelay = 0.01
    public static let fallbackDelay = 0.1

    /// Indizes der zu dekodierenden Bilder (aufsteigend, das erste immer dabei).
    public static func indices(frameCount: Int, maxFrames: Int = maxFrames) -> [Int] {
        guard frameCount > 0, maxFrames > 0 else { return [] }
        guard frameCount > maxFrames else { return Array(0..<frameCount) }
        return (0..<maxFrames).map { $0 * frameCount / maxFrames }
    }

    /// Dauer eines Einzelbilds aus der GIF-Angabe (nil oder ≤ 10 ms → 0,1 s).
    public static func delay(_ raw: Double?) -> Double {
        guard let raw, raw > minDelay else { return fallbackDelay }
        return raw
    }

    /// Gesamtdauer aller Bilder (für `UIImage.animatedImage`), auch beim Ausdünnen unverändert.
    /// `UIImage.animatedImage` zeigt jedes Einzelbild gleich lang: unterschiedliche Verzögerungen je Bild gehen verloren
    /// (bei gleichmäßigen GIFs ohne sichtbaren Unterschied).
    public static func duration(delays: [Double?]) -> Double {
        delays.reduce(0) { $0 + delay($1) }
    }
}
