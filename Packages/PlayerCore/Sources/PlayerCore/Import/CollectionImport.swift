import Foundation

// Wave F-o round 2: one way in for collection imports (link or pasted code). The format is told from the content:
// a widget export, the flat collection list of the same tool, a preview pack (videos with a sound track, matched to
// tiles by title) or a public collection export (folders with `focusVideoUrl`/`focusGifUrl`). Nothing of it is
// bundled; links are fetched at runtime.

/// Format of an imported JSON text.
public enum CollectionImportFormat: Equatable, Sendable {
    /// `{"exportType":"fusionWidgets","widgets":[…]}` (also kit files).
    case widgets
    /// Flat collection list `[{"name","backgroundImageURL","dataSources"}]` of the widget tool.
    case collectionList
    /// Preview pack `[{"id","title","videoURL","backgroundURL"}]`.
    case previewPack
    /// Public collection export `[{"title","folders":[…]}]`.
    case collections
    /// Recognised but not importable here.
    case backup
    case iconPack
    case invalidJSON
    case unknown

    public static func detect(_ data: Data) -> CollectionImportFormat {
        guard let o = try? JSONSerialization.jsonObject(with: data) else { return .invalidJSON }
        if let d = o as? [String: Any] {
            if d["profiles"] != nil { return .backup }
            if d["exportType"] as? String == "fusionWidgets" || d["widgets"] is [Any] { return .widgets }
            return .unknown
        }
        guard let arr = o as? [Any] else { return .unknown }
        let objects = arr.compactMap { $0 as? [String: Any] }
        guard let first = objects.first else { return .unknown }
        if objects.contains(where: { $0["videoURL"] != nil }) && objects.allSatisfy({ $0["folders"] == nil && $0["dataSources"] == nil }) {
            return .previewPack
        }
        if first["folders"] != nil { return .collections }
        if first["dataSources"] != nil || first["dataSource"] != nil { return .collectionList }
        if first["url"] != nil { return .iconPack }
        return .unknown
    }

    /// German text for a format that cannot be imported, else nil.
    public var problem: String? {
        switch self {
        case .widgets, .collectionList, .previewPack, .collections: nil
        case .backup: "Das ist eine Sicherung – bitte „Sicherung wiederherstellen“ nutzen."
        case .iconPack: "Das ist ein Bewertungs-Icon-Satz – bitte das Feld „Eigener Bewertungs-Icon-Satz“ nutzen."
        case .invalidJSON: "Kein gültiges JSON (abgeschnitten oder kein Text-Export?)."
        case .unknown: "Format nicht erkannt. Möglich: Widget-Export, Preview Pack oder Collection-Export (JSON)."
        }
    }

    /// German name for result lines.
    public var name: String {
        switch self {
        case .widgets: "Widget-Export"
        case .collectionList: "Collection-Liste"
        case .previewPack: "Preview Pack"
        case .collections: "Collection-Export"
        case .backup: "Sicherung"
        case .iconPack: "Icon-Satz"
        case .invalidJSON, .unknown: "unbekannt"
        }
    }
}

/// One video of a preview pack.
public struct PreviewPackEntry: Codable, Equatable, Hashable, Sendable {
    public var title: String
    public var video: String
    public var background: String?

    public init(title: String, video: String, background: String? = nil) {
        self.title = title; self.video = video; self.background = background
    }
}

/// Preview pack: videos (with their sound track) and stills, matched to imported tiles by title.
public enum PreviewPack {
    public static let maxTitleLength = 128
    /// Most entries kept per pack (the pack is stored with the link).
    public static let maxEntries = 1000

    /// Exact key: only case and whitespace folded (" Disney +" → "disney+"). Tried first.
    public static func exactKey(_ title: String) -> String {
        String(title.lowercased().unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.map(Character.init))
    }

    /// Coarse key: compatibility-decomposed, lower case, letters and digits only ("Disney+" → "disney",
    /// " Apple  TV " → "appletv"). Fallback when the exact title has no entry.
    public static func key(_ title: String) -> String {
        let folded = title.decomposedStringWithCompatibilityMapping.lowercased()
        var v = String.UnicodeScalarView()
        v.append(contentsOf: folded.unicodeScalars.filter { $0.isASCII && CharacterSet.alphanumerics.contains($0) })
        return String(v)
    }

    /// Entries of a pack; entries without title or playable video are skipped and counted.
    public static func parse(_ data: Data) throws -> (entries: [PreviewPackEntry], skipped: Int) {
        let raw = try JSONDecoder().decode(LossyList<RawEntry>.self, from: data)
        var out: [PreviewPackEntry] = []
        var skipped = raw.failed
        for r in raw.items {
            guard let t = r.title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, t.count <= maxTitleLength,
                  !key(t).isEmpty, let v = FocusVideoURL.playable(r.videoURL) else { skipped += 1; continue }
            out.append(PreviewPackEntry(title: t, video: v, background: FusionImport.imageURL(r.backgroundURL)))
        }
        if out.count > maxEntries { skipped += out.count - maxEntries; out = Array(out.prefix(maxEntries)) }
        return (out, skipped)
    }

    /// Lookup by title: the exact key first ("Paramount+" and "Paramount" stay apart), then the coarse key. On equal
    /// keys the first entry wins (earlier packs, earlier in a pack), as in the tool that writes the packs.
    public struct Index: Equatable, Sendable {
        public private(set) var byExact: [String: PreviewPackEntry] = [:]
        public private(set) var byKey: [String: PreviewPackEntry] = [:]
        public var isEmpty: Bool { byKey.isEmpty }

        public init(_ entries: [PreviewPackEntry]) {
            for e in entries {
                let x = PreviewPack.exactKey(e.title), k = PreviewPack.key(e.title)
                if byExact[x] == nil { byExact[x] = e }
                if byKey[k] == nil { byKey[k] = e }
            }
        }

        public func entry(forTitle t: String) -> PreviewPackEntry? { byExact[PreviewPack.exactKey(t)] ?? byKey[PreviewPack.key(t)] }
    }

    /// Fills the gaps of matching tiles: focus video where there is none, still where there is none. The tile's own
    /// fields always win.
    public static func apply(_ index: Index, to c: MediaCollection) -> MediaCollection {
        guard !index.isEmpty else { return c }
        var out = c
        for i in out.folders.indices {
            guard let e = index.entry(forTitle: out.folders[i].title) else { continue }
            if (out.folders[i].focusVideo ?? "").isEmpty { out.folders[i].focusVideo = e.video }
            if (out.folders[i].coverImage ?? "").isEmpty, let b = e.background { out.folders[i].coverImage = b }
        }
        return out
    }

    /// Tiles of the collections whose title has an entry in the pack.
    public static func matches(_ index: Index, in collections: [MediaCollection]) -> Int {
        collections.reduce(0) { n, c in n + c.folders.filter { index.entry(forTitle: $0.title) != nil }.count }
    }

    struct RawEntry: Decodable { var title: String?; var videoURL: String?; var backgroundURL: String? }
}

/// Counts for the German result line of an import.
public struct ImportSummary: Equatable, Sendable {
    public var rows: Int
    public var tiles: Int
    public var video: Int
    /// Videos known to have a sound track (nil = not checked yet).
    public var sound: Int?

    public init(rows: Int, tiles: Int, video: Int, sound: Int? = nil) {
        self.rows = rows; self.tiles = tiles; self.video = video; self.sound = sound
    }

    /// Counts of imported collections. `soundVideos`: video addresses with a sound track (nil = not checked).
    public static func of(_ collections: [MediaCollection], soundVideos: Set<String>? = nil) -> ImportSummary {
        let folders = collections.flatMap(\.folders)
        let videos = folders.compactMap { FocusVideoURL.playable($0.focusVideo) }
        return ImportSummary(rows: collections.count, tiles: folders.count, video: videos.count,
                             sound: soundVideos.map { s in videos.filter { s.contains($0) }.count })
    }

    /// Distinct video addresses to check for a sound track.
    public static func videos(_ collections: [MediaCollection]) -> [String] {
        var seen = Set<String>()
        return collections.flatMap(\.folders).compactMap { FocusVideoURL.playable($0.focusVideo) }.filter { seen.insert($0).inserted }
    }

    /// "Import: 3 Reihen, 42 Kacheln, 35 mit Video, 30 mit Ton".
    public var line: String {
        var s = "Import: \(rows) \(rows == 1 ? "Reihe" : "Reihen"), \(tiles) \(tiles == 1 ? "Kachel" : "Kacheln"), \(video) mit Video"
        if let sound { s += ", \(sound) mit Ton" }
        return s
    }

    /// "Preview Pack: 84 Videos, 12 Kacheln zugeordnet, 39 mit Ton".
    public static func packLine(entries: Int, matched: Int, sound: Int?) -> String {
        var s = "Preview Pack: \(entries) \(entries == 1 ? "Video" : "Videos"), \(matched) \(matched == 1 ? "Kachel" : "Kacheln") zugeordnet"
        if let sound { s += ", \(sound) mit Ton" }
        return s
    }
}
