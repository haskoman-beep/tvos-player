import Foundation

/// Eine Kit-Datei (Kachel-Reihe oder komplette Startseite), nur als Verweis – der Inhalt kommt zur Laufzeit.
public struct FusionKitSource: Codable, Sendable, Hashable, Identifiable {
    /// Stabiler Schlüssel (Kit-Dateien: aus dem Pfad, sonst aus der URL); Teil aller Reihen-IDs.
    public var id: String
    public var title: String
    public var url: String
    /// Per Handy eingetragene URL außerhalb des Kit-Katalogs (kann wieder entfernt werden).
    public var custom: Bool

    public init(id: String, title: String, url: String, custom: Bool) {
        self.id = id; self.title = title; self.url = url; self.custom = custom
    }
}

/// Kit-Katalog: welche Dateien es gibt, kommt zur Laufzeit aus der GitHub-Dateiliste (das Kit hat keinen Index).
public enum FusionKitCatalog {
    public static let siteURL = "https://kit.betterer.cc"
    static let repo = "itsrenoria/fusion-starter-kit"
    static let rawBase = "https://raw.githubusercontent.com/itsrenoria/fusion-starter-kit/refs/heads/main/json/"
    /// Ordner, deren Dateiliste geholt wird.
    public static let folders = ["widgets", "setup"]

    public static func listingURL(_ folder: String) -> URL? {
        URL(string: "https://api.github.com/repos/\(repo)/contents/json/\(folder)")
    }

    /// GitHub-Dateiliste (`GET /repos/…/contents/json/<ordner>`) → angebotene Kit-Dateien.
    /// Kachel-Reihen nur „mit Quellen“ (ohne Quellen wären die Kacheln leer) und im Breitformat
    /// (unsere Collection-Kachel ist 16:9); komplette Startseiten alle. Kachel-Reihen nach Titel, Startseiten zuletzt.
    public static func parseListing(_ data: Data) -> [FusionKitSource] {
        struct Entry: Decodable { var name: String?; var path: String?; var type: String?; var download_url: String? }
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        var widgets: [FusionKitSource] = [], setups: [FusionKitSource] = []
        for e in entries {
            guard e.type == nil || e.type == "file", let name = e.name, name.hasSuffix(".json"), let path = e.path,
                  let r = path.range(of: "json/") else { continue }
            let rel = String(path[r.upperBound...])
            if rel.hasPrefix("widgets/") {
                guard name.hasPrefix("widgets-sourced-"), parts(name).aspect == "wide" else { continue }
                widgets.append(kitSource(path: rel, url: e.download_url))
            } else if rel.hasPrefix("setup/") {
                guard name.hasPrefix("setup-") else { continue }
                setups.append(kitSource(path: rel, url: e.download_url))
            }
        }
        return widgets.sorted { $0.title < $1.title } + setups.sorted { $0.title < $1.title }
    }

    /// Quelle zu einer Kit-Datei (`widgets/…json`, `setup/…json`); die ID hängt nur am Pfad.
    public static func kitSource(path: String, url: String? = nil) -> FusionKitSource {
        let u = url ?? (rawBase + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path))
        return FusionKitSource(id: NuvioImport.stableHash("kit:" + path), title: title(forPath: path), url: u, custom: false)
    }

    /// Per Handy eingefügte URL („Copy JSON URL“ im Kit): Kit-Datei → dieselbe Quelle wie im Katalog, sonst eigene Quelle.
    public static func source(forURL url: String) -> FusionKitSource {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = u.range(of: "/fusion-starter-kit/"), let j = u.range(of: "/json/", range: r.upperBound..<u.endIndex) {
            let rel = String(u[j.upperBound...])
            let path = rel.removingPercentEncoding ?? rel
            if path.hasPrefix("widgets/") || path.hasPrefix("setup/") || path.hasPrefix("collections/") {
                return kitSource(path: path, url: u)
            }
        }
        let host = URL(string: u)?.host ?? "?"
        return FusionKitSource(id: NuvioImport.stableHash("url:" + u), title: "Eigenes Kit · \(host)", url: u, custom: true)
    }

    /// `widgets-sourced-genres-wide-name.x` → (genres, wide, name.x).
    static func parts(_ fileName: String) -> (category: String, aspect: String, variant: String) {
        var n = fileName
        if n.hasSuffix(".json") { n = String(n.dropLast(5)) }
        for p in ["widgets-", "collections-", "sourced-"] where n.hasPrefix(p) { n = String(n.dropFirst(p.count)) }
        let s = n.split(separator: "-", maxSplits: 2).map(String.init)
        return (s.first ?? n, s.count > 1 ? s[1] : "", s.count > 2 ? s[2] : "")
    }

    static func title(forPath path: String) -> String {
        let name = String(path.split(separator: "/").last ?? Substring(path))
        if name.hasPrefix("setup-") {
            return "Komplette Startseite · " + name.dropFirst("setup-".count).replacingOccurrences(of: ".json", with: "")
        }
        let p = parts(name)
        let cat = ["genres": "Genres", "decades": "Jahrzehnte", "directors": "Regie", "streaming": "Streaming",
                   "awards": "Preise"][p.category] ?? p.category.capitalized
        let aspect = ["wide": "", "poster": " (Poster)", "square": " (Quadrat)"][p.aspect] ?? (p.aspect.isEmpty ? "" : " (\(p.aspect))")
        return cat + aspect + (p.variant.isEmpty ? "" : " · " + p.variant)
    }
}

/// Build 6 (L3): a placed kit row that waits for an addon or a Trakt login. It leaves the start page (no empty rows),
/// but keeps its row (id, style) and where it stood, so it comes back at the same place with the same style.
public struct FusionKitParkedRow: Codable, Sendable, Hashable {
    /// The row as it stood on the start page (id, content, style).
    public var row: HomeRow
    /// Content keys of the rows above it when it left, nearest first (at most `FusionKitSync.anchorLimit`).
    public var above: [String]
    /// Its index when it left (used only when none of `above` is on the start page any more).
    public var index: Int

    public init(row: HomeRow, above: [String], index: Int) { self.row = row; self.above = above; self.index = index }

    public var kitID: String? { FusionImport.kitID(of: row) }
}

/// Kit-Einstellungen eines Profils.
public struct FusionKitSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    /// Gewählte Kit-Reihen (IDs `fusion.<quelle>.<widget>`), in Wahl-Reihenfolge.
    public var selected: [String]
    /// Von uns auf die Startseite gesetzte Reihen. Fehlt eine davon im Layout, hat der Nutzer sie im Editor entfernt.
    public var placed: [String]
    /// Quellen der gewählten Reihen und per Handy eingetragene Kit-URLs (zum Laden ohne Katalog).
    public var sources: [FusionKitSource]
    /// Build 6 (L3): placed rows that wait for an addon or a Trakt login (off the start page, place and style kept).
    public var parked: [FusionKitParkedRow]

    public init(enabled: Bool = false, selected: [String] = [], placed: [String] = [], sources: [FusionKitSource] = [],
                parked: [FusionKitParkedRow] = []) {
        self.enabled = enabled; self.selected = selected; self.placed = placed; self.sources = sources; self.parked = parked
    }

    enum CodingKeys: String, CodingKey { case enabled, selected, placed, sources, parked }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        selected = try c.decodeIfPresent([String].self, forKey: .selected) ?? []
        placed = try c.decodeIfPresent([String].self, forKey: .placed) ?? []
        sources = try c.decodeIfPresent([FusionKitSource].self, forKey: .sources) ?? []
        parked = (try? c.decodeIfPresent([FusionKitParkedRow].self, forKey: .parked)) ?? []
    }

    public func isSelected(_ rowID: String) -> Bool { selected.contains(rowID) }

    /// Reihe an-/abwählen; die Quelle wird gemerkt, damit sie auch ohne Katalog (offline, API-Limit) lädt.
    public mutating func setSelected(_ rowID: String, _ on: Bool, source: FusionKitSource) {
        if on {
            if !selected.contains(rowID) { selected.append(rowID) }
            if !sources.contains(where: { $0.id == source.id }) { sources.append(source) }
        } else {
            selected.removeAll { $0 == rowID }
        }
    }

    /// Eine Kit-Reihe hinzufügen bzw. wieder einblenden (Browser, Verwalter, Handy). Ist das Kit aus, wird die alte
    /// Auswahl verworfen: nur diese Reihe kommt zurück, nicht alle früher gewählten (F-b2-Review I1).
    /// Rückgabe: verworfene Reihen-IDs (leer, wenn das Kit schon an war).
    @discardableResult
    public mutating func choose(_ rowID: String, source: FusionKitSource) -> [String] {
        var dropped: [String] = []
        if !enabled {
            dropped = selected.filter { $0 != rowID }
            selected = []
            enabled = true
        }
        setSelected(rowID, true, source: source)
        return dropped
    }

    /// Ganze Kit-Datei übernehmen (Handy-Import): Kit an, alle Reihen gewählt.
    public mutating func addAll(_ content: FusionKitContent, source: FusionKitSource) {
        enabled = true
        for r in content.rows { setSelected(r.id, true, source: source) }
        if content.rows.isEmpty, !sources.contains(where: { $0.id == source.id }) { sources.append(source) }
    }

    /// Eigene Quelle samt ihrer Reihen vergessen.
    public mutating func removeSource(_ id: String) {
        sources.removeAll { $0.id == id }
        selected.removeAll { FusionImport.sourceKey(ofID: $0) == id }
        parked.removeAll { $0.kitID.flatMap(FusionImport.sourceKey(ofID:)) == id }
    }
}

public struct FusionKitSyncResult: Equatable, Sendable {
    public var added: [String] = []
    public var removed: [String] = []
    /// Vom Nutzer im Startseiten-Editor entfernt → abgewählt.
    public var deselected: [String] = []
    /// Gewählt, aber ohne Trakt Client ID bzw. Anmeldung (oder ohne Addon) nicht ladbar → ausgeblendet.
    public var hidden: [String] = []
    /// Build 6 (L3): left the start page in this sync, but wait with place and style (`FusionKitSettings.parked`).
    public var parked: [String] = []
    /// Build 6 (L3): came back from `parked` at their old place (also listed in `added`).
    public var restored: [String] = []
    public var layoutChanged = false
    public init() {}
}

/// Gleicht die Kit-Reihen der Startseite mit den Einstellungen ab. Eigene Reihen des Nutzers bleiben unberührt,
/// vorhandene Kit-Reihen behalten Platz und Stil; neue kommen ans Ende. Build 6 (L3): a placed row that waits for an
/// addon or a Trakt login leaves the start page but is parked with place and style, and comes back there.
public enum FusionKitSync {
    /// Rows above a parked row that are remembered as its anchor.
    public static let anchorLimit = 8

    /// Task 2.4 (S-12): rule for kit rows when the settings may be missing (e.g. right after restoring a backup
    /// without kit settings). `nil` = no settings stored for the profile → the layout stays as it is. Kit rows are
    /// removed only when settings were loaded and the selection is explicitly empty (kit off or nothing chosen).
    /// The app calls it only for the `nil` case (FusionKitStore without stored settings); for loaded settings the full
    /// `apply(layout:settings:contents:…)` below behaves the same way (kit off or empty selection → no kit rows), and
    /// this function is its specification in the tests.
    public static func apply(settings: FusionKitSettings?, layout: HomeLayout) -> HomeLayout {
        guard let settings, !settings.enabled || settings.selected.isEmpty else { return layout }
        var l = layout
        l.rows.removeAll { FusionImport.kitID(of: $0) != nil }
        return l
    }

    /// - Parameter contents: geladene Kit-Dateien je Quellen-Schlüssel. Ist eine Quelle (noch) nicht geladen,
    ///   bleiben ihre Reihen, wie sie sind – sonst gingen Platz und Stil bei jedem Start ohne Netz verloren.
    public static func apply(layout: inout HomeLayout, settings: inout FusionKitSettings,
                             contents: [String: FusionKitContent], traktID: Bool, traktLogin: Bool,
                             addons: [InstalledAddon]? = nil) -> FusionKitSyncResult {
        var res = FusionKitSyncResult()
        let index = addons.map(AddonCatalogIndex.init)
        let present = Set(layout.rows.compactMap { FusionImport.kitID(of: $0) })

        // 1. Von uns gesetzt, aber nicht mehr da: im Editor entfernt → abwählen.
        for id in settings.placed where !present.contains(id) && settings.selected.contains(id) {
            settings.selected.removeAll { $0 == id }
            res.deselected.append(id)
        }

        // 2. Was angezeigt werden soll; `unknown` = gewählt, aber Quelle nicht geladen.
        var want: [String: FusionKitRow] = [:]
        var order: [String] = []
        var unknown = Set<String>()
        if settings.enabled {
            for id in settings.selected {
                guard let key = FusionImport.sourceKey(ofID: id) else { continue }
                guard let content = contents[key] else { unknown.insert(id); continue }
                guard let row = content.row(id) else { continue }   // nicht mehr im Kit
                if let r = row.available(traktID: traktID, traktLogin: traktLogin, catalogs: index) { want[id] = r; order.append(id) }
                else { res.hidden.append(id) }
            }
        }

        // 3. Überzählige Kit-Reihen entfernen, vorhandene Listen aktualisieren, wartende parken, fehlende einsetzen.
        let waiting = Set(res.hidden)
        var parked: [String: FusionKitParkedRow] = [:]
        for p in settings.parked { if let id = p.kitID { parked[id] = p } }
        var rows: [HomeRow] = []
        for (i, row) in layout.rows.enumerated() {
            guard let id = FusionImport.kitID(of: row) else { rows.append(row); continue }
            if let r = want[id] {
                var row = row
                if case .list = r.body, row.content != r.content { row.content = r.content; res.layoutChanged = true }
                rows.append(row)
            } else if unknown.contains(id) {
                rows.append(row)
            } else if waiting.contains(id) {
                // Anchors from the whole old layout (neighbours that wait too count), so adjacent rows keep their order.
                let above = layout.rows[..<i].reversed().prefix(anchorLimit).map(\.content.key)
                parked[id] = FusionKitParkedRow(row: row, above: Array(above), index: i)
                res.parked.append(id)
            } else {
                res.removed.append(id)
            }
        }
        let kept = Set(rows.compactMap { FusionImport.kitID(of: $0) })
        for id in order where !kept.contains(id) {
            guard let r = want[id] else { continue }
            if let p = parked.removeValue(forKey: id) {
                rows.insert(restoredRow(p, as: r), at: restoreIndex(p, in: rows))
                res.restored.append(id)
            } else {
                rows.append(HomeRow(content: r.content, style: r.style))
            }
            res.added.append(id)
        }
        if !res.added.isEmpty || !res.removed.isEmpty || !res.parked.isEmpty { res.layoutChanged = true }
        layout.rows = rows
        settings.placed = rows.compactMap { FusionImport.kitID(of: $0) }
        // Keep only rows that still wait (or whose file is not loaded yet); kit off, deselected or gone → forgotten.
        let keep = waiting.union(unknown)
        var still: [FusionKitParkedRow] = []
        for id in settings.parked.compactMap(\.kitID) + res.parked where keep.contains(id) {
            if let p = parked.removeValue(forKey: id) { still.append(p) }
        }
        settings.parked = still
        return res
    }

    /// A parked row as it comes back: its id and style; a list takes the current source of the kit file.
    static func restoredRow(_ p: FusionKitParkedRow, as r: FusionKitRow) -> HomeRow {
        var row = p.row
        if case .list = r.body { row.content = r.content }
        if !row.content.allowedStyles.contains(row.style) { row.style = r.style }
        return row
    }

    /// Below the nearest remembered row above it that is still on the start page; at the top if it was the first row;
    /// otherwise at its old index (clamped).
    static func restoreIndex(_ p: FusionKitParkedRow, in rows: [HomeRow]) -> Int {
        for key in p.above {
            if let j = rows.firstIndex(where: { $0.content.key == key }) { return j + 1 }
        }
        return p.above.isEmpty ? 0 : min(p.index, rows.count)
    }
}
