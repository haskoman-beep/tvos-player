import Foundation

// Welle F-l: Standbilder und Fokus-GIFs der fertigen Pakete (Streaming-Dienste, Genres) kommen zur Laufzeit aus
// Nutzer-Importen (Nuvio/Fusion) bzw. aus den Kachel-Dateien des Startseiten-Kits. Im Repo liegt kein Bild.
// Ohne passendes Bild bleibt die eigene Symbol-Kachel (Farbverlauf + SF Symbol + Titel).

/// Eine Bildquelle für Paket-Kacheln: die Kacheln einer importierten Collection oder einer Kit-Reihe.
public struct PackageArtSource: Sendable, Equatable {
    /// Herkunft, zugleich Vorrang (kleiner = zuerst).
    public enum Origin: Int, Sendable, Comparable {
        /// Vom Nutzer importierte Collection (Profil).
        case userImport = 0
        /// Kit-Datei, aus der der Nutzer Reihen gewählt oder die er per Handy eingetragen hat.
        case chosenKit = 1
        /// Übrige Kit-Dateien des Katalogs (nur als Bildquelle geladen).
        case kit = 2
        public static func < (a: Origin, b: Origin) -> Bool { a.rawValue < b.rawValue }
    }

    public var id: String
    public var folders: [Folder]
    public var origin: Origin
    /// Seitenverhältnis der Kachelbilder (`wide`, `poster`, `square`), nil = unbekannt. Die Paket-Kachel ist
    /// breit; Quellen in anderem Format kommen nur zum Zug, wenn keine breite passt.
    public var aspect: String?

    public init(id: String, folders: [Folder], origin: Origin, aspect: String? = nil) {
        self.id = id; self.folders = folders; self.origin = origin; self.aspect = aspect
    }

    /// Breit oder unbekannt: passt zur 16:9-Paket-Kachel.
    var fitsWideTile: Bool { aspect == nil || aspect?.lowercased() == "wide" }

    /// Importierte Collections des Profils (ohne die Pakete selbst).
    public static func userImports(_ collections: [MediaCollection]) -> [PackageArtSource] {
        collections.filter { !$0.id.hasPrefix("pkg.") }.map { PackageArtSource(id: $0.id, folders: $0.folders, origin: .userImport) }
    }

    /// Kachel-Reihen einer Kit-Datei, ungefiltert: auch Kacheln, deren Listen ohne Trakt nicht ladbar sind,
    /// liefern ihr Bild.
    public static func kit(_ content: FusionKitContent, origin: Origin) -> [PackageArtSource] {
        content.rows.compactMap { row in
            guard case .collection(let c) = row.body else { return nil }
            return PackageArtSource(id: row.id, folders: c.folders, origin: origin, aspect: row.imageAspect)
        }
    }

    /// Bildquellen aus geladenen Kit-Dateien (Schlüssel → Inhalt): gewählte Dateien (`chosen`) vor den übrigen,
    /// sonst nach Titel, dann Schlüssel. Ungewählte Dateien nur, wenn sie Paket-Bilddateien sind (`packFiles`,
    /// Breitformat Streaming/Genres) – sonst gewänne nach „Kit neu laden“ in den Einstellungen etwa eine Poster-Datei.
    public static func kitSources(contents: [String: FusionKitContent], titles: [String: String],
                                  chosen: Set<String>, packFiles: Set<String>) -> [PackageArtSource] {
        let keys = contents.keys.filter { chosen.contains($0) || packFiles.contains($0) }.sorted { a, b in
            let ca = chosen.contains(a), cb = chosen.contains(b)
            if ca != cb { return ca }
            let ta = titles[a] ?? a, tb = titles[b] ?? b
            return ta != tb ? ta < tb : a < b
        }
        return keys.flatMap { k in
            contents[k].map { kit($0, origin: chosen.contains(k) ? .chosenKit : .kit) } ?? []
        }
    }
}

extension ReadyPackages {
    /// Vereinheitlichter Name zum Vergleich: klein, ohne Akzente/Umlautpunkte, „+“ → „plus“, „&“ → „and“,
    /// nur Buchstaben und Ziffern („Disney+“ → „disneyplus“, „Komödie“ → „komodie“, „Sci-Fi“ → „scifi“).
    public static func normalizedArtName(_ s: String) -> String {
        var out = ""
        for u in s.decomposedStringWithCanonicalMapping.lowercased().unicodeScalars {
            switch u {
            case "+": out += "plus"
            case "&": out += "and"
            case "a"..."z", "0"..."9": out.unicodeScalars.append(u)
            default: break   // Leer- und Satzzeichen, abgetrennte Akzente
            }
        }
        return out
    }

    /// Weitere Namen je Paket (nach dem eigenen Namen), in Vorzugsreihenfolge: englische Titel der Importe und
    /// Varianten der Kit-Dateien. Schlüssel: Name in `providersDE` bzw. `genres`; Werte schon vereinheitlicht.
    static let artAliases: [String: [String]] = [
        "Netflix": ["netflixred", "netflixdark", "netflixwhite"],
        "Prime Video": ["amazonprimevideo", "amazonprime", "prime", "amazon"],
        "Disney+": ["disney"],
        "Apple TV+": ["appletv"],
        "WOW": ["skywow"],
        "Paramount+": ["paramount"],
        "RTL+": ["rtl"],
        "Komödie": ["comedy", "comedies", "komodien"],
        "Krimi": ["crime", "krimis"],
        "Drama": ["dramas"],
        "Science-Fiction": ["scifi"],
        "Thriller": ["thrillers"],
        "Animation": ["animated", "zeichentrick"],
        "Dokumentation": ["dokumentationen", "doku", "dokus", "documentary", "documentaries"],
        "Familie": ["family", "familymovienight", "kids"],
    ]

    /// Name des Pakets einer Kachel-ID (`pkg.streaming-de.<tmdb>` → „Netflix“, `pkg.genres.<name>` → Name), sonst nil.
    static func packageName(forFolderID id: String) -> String? {
        let streaming = "pkg.streaming-de.", genres = "pkg.genres."
        if id.hasPrefix(streaming), let n = Int(id.dropFirst(streaming.count)) {
            return providersDE.first { $0.tmdbID == n }?.name
        }
        if id.hasPrefix(genres) {
            let name = String(id.dropFirst(genres.count))
            return self.genres.first { $0.name == name }?.name
        }
        return nil
    }

    /// Erkennungsnamen einer Paket-Kachel (vereinheitlicht, eigener Name zuerst), sonst nil.
    public static func artNames(forFolderID id: String) -> [String]? {
        guard let name = packageName(forFolderID: id) else { return nil }
        return [normalizedArtName(name)] + (artAliases[name] ?? [])
    }

    /// TMDB-Schlüssel, an dem eine importierte Kachel als „dieselbe“ erkannt wird: Anbieter-ID bzw. Genre-IDs.
    static func matchKeys(forFolderID id: String) -> (filter: String, values: Set<String>)? {
        let streaming = "pkg.streaming-de.", genres = "pkg.genres."
        if id.hasPrefix(streaming), let n = Int(id.dropFirst(streaming.count)) {
            return ("with_watch_providers", [String(n)])
        }
        if id.hasPrefix(genres), let g = self.genres.first(where: { $0.name == String(id.dropFirst(genres.count)) }) {
            return ("with_genres", Set([g.movie, g.tv].compactMap { $0.map(String.init) }))
        }
        return nil
    }

    /// Rang einer fremden Kachel als Bild für eine Paket-Kachel (kleiner = besser), nil = passt nicht oder hat kein
    /// Standbild. 0: derselbe Anbieter bzw. dasselbe Genre als einziger TMDB-Filterwert oder der eigene Name;
    /// 1…: weitere Namen in Vorzugsreihenfolge.
    static func artRank(title: String, folder f: Folder, names: [String],
                        keys: (filter: String, values: Set<String>)?) -> Int? {
        guard let cover = f.coverImage, !cover.isEmpty else { return nil }
        if let keys, f.sources.contains(where: { s in
            guard case .tmdbDiscover(let filters) = s.kind, let v = filters[keys.filter] else { return false }
            let parts = v.split(whereSeparator: { $0 == "," || $0 == "|" }).map(String.init)
            return parts.count == 1 && keys.values.contains(parts[0])
        }) { return 0 }
        guard !title.isEmpty else { return nil }
        return names.firstIndex(of: title)
    }

    /// Fokus-GIF einer Kachel: eigenes GIF, sonst das Standbild, wenn es selbst ein GIF ist.
    static func gifURL(of f: Folder) -> String? {
        if let g = f.focusGif, !g.isEmpty { return g }
        guard let cover = f.coverImage, let u = URL(string: cover), u.pathExtension.lowercased() == "gif" else { return nil }
        return cover
    }

    /// Paket-Kacheln ohne eigenes Standbild übernehmen Standbild, Logo, Fokus-GIF und Titel-Schalter (`hideTitle`)
    /// einer passenden Kachel aus `sources`. Vorrang der Quellen: Breitformat (oder unbekannt) vor anderem Format –
    /// ein Poster wäre in der 16:9-Kachel beschnitten –, dann Herkunft (Nutzer-Import vor gewähltem Kit vor übrigem
    /// Kit), dann die meisten Treffer in dieser Reihe (eine Reihe sieht einheitlich aus), dann die meisten GIFs, dann
    /// die Reihenfolge in `sources`. Lücken füllt die nächste Quelle.
    /// Wave F-o: focus and hero video come along; among equal hit counts most videos rank before most GIFs.
    /// Ohne Treffer: unverändert (Symbol-Kachel).
    public static func withArt(_ c: MediaCollection, sources: [PackageArtSource]) -> MediaCollection {
        let targets = c.folders.indices.filter { isPackageFolder(c.folders[$0].id) && c.folders[$0].coverImage == nil }
        guard !targets.isEmpty, !sources.isEmpty else { return c }
        let wanted: [(index: Int, names: [String], keys: (filter: String, values: Set<String>)?)] = targets.compactMap { t in
            let id = c.folders[t].id
            guard let names = artNames(forFolderID: id) else { return nil }
            return (t, names, matchKeys(forFolderID: id))
        }

        struct Hits {
            var order: Int; var origin: PackageArtSource.Origin; var wide: Bool
            var videos = 0; var gifs = 0; var byTarget: [Int: (folder: Folder, rank: Int)] = [:]
        }
        var ranked: [Hits] = []
        for (order, s) in sources.enumerated() where !s.id.hasPrefix("pkg.") {
            let titled = s.folders.map { (normalizedArtName($0.title), $0) }
            var h = Hits(order: order, origin: s.origin, wide: s.fitsWideTile)
            for w in wanted {
                var best: (folder: Folder, rank: Int)?
                for (title, f) in titled {
                    guard let r = artRank(title: title, folder: f, names: w.names, keys: w.keys), r < (best?.rank ?? .max) else { continue }
                    best = (f, r)
                }
                if let best {
                    h.byTarget[w.index] = best
                    if gifURL(of: best.folder) != nil { h.gifs += 1 }
                    if best.folder.focusVideo?.isEmpty == false { h.videos += 1 }
                }
            }
            if !h.byTarget.isEmpty { ranked.append(h) }
        }
        guard !ranked.isEmpty else { return c }
        ranked.sort { a, b in
            if a.wide != b.wide { return a.wide }
            if a.origin != b.origin { return a.origin < b.origin }
            if a.byTarget.count != b.byTarget.count { return a.byTarget.count > b.byTarget.count }
            if a.videos != b.videos { return a.videos > b.videos }
            if a.gifs != b.gifs { return a.gifs > b.gifs }
            return a.order < b.order
        }

        var out = c
        for w in wanted {
            guard let src = ranked.lazy.compactMap({ $0.byTarget[w.index]?.folder }).first else { continue }
            out.folders[w.index].coverImage = src.coverImage
            out.folders[w.index].logo = src.logo
            out.folders[w.index].focusGif = gifURL(of: src)
            out.folders[w.index].focusVideo = src.focusVideo.flatMap { $0.isEmpty ? nil : $0 }
            out.folders[w.index].heroVideo = src.heroVideo
            // Steht der Name schon im Bild (Kit: `hideTitle`), zeigt die Kachel keinen zweiten Titel darüber.
            out.folders[w.index].hideTitle = src.hideTitle
        }
        return out
    }
}

/// Welle F-l / F-o: Logzeile je Paket-Reihe („Paket-Bilder: <reihe> n/m mit Bild, k mit GIF, v mit Video“).
public struct PackageArtStats: Equatable, Sendable {
    public var tiles: Int
    public var images: Int
    public var gifs: Int
    public var videos: Int

    /// nil, wenn die Reihe keine Paket-Kachel hat.
    public init?(folders: [Folder]) {
        let p = folders.filter { ReadyPackages.isPackageFolder($0.id) }
        guard !p.isEmpty else { return nil }
        tiles = p.count
        images = p.filter { !($0.coverImage ?? "").isEmpty }.count
        gifs = p.filter { !($0.focusGif ?? "").isEmpty }.count
        videos = p.filter { !($0.focusVideo ?? "").isEmpty }.count
    }

    public func logLine(row: String) -> String {
        "Paket-Bilder: \(row) \(images)/\(tiles) mit Bild, \(gifs) mit GIF, \(videos) mit Video"
    }
}

extension FusionKitCatalog {
    /// Dateinamen-Anfänge der Kit-Dateien, deren Kacheln Bilder für die Pakete liefern (Breitformat wie unsere Kachel).
    static let packageArtPrefixes = ["widgets-sourced-streaming-wide-", "widgets-sourced-genres-wide-"]

    /// Bekannte Dateien, solange keine Dateiliste vorliegt (erster Start ohne Netz zur GitHub-API, Abrufgrenze).
    static let packageArtFallback = [
        "widgets/widgets-sourced-genres-wide-dannyrutledge.json",
        "widgets/widgets-sourced-genres-wide-mousa.a.json",
        "widgets/widgets-sourced-streaming-wide-rdnoni-color.json",
    ]

    /// Kit-Dateien, die als Bildquelle der Pakete geladen werden (auch bei ausgeschaltetem Kit), nach Titel sortiert.
    public static func packageArtSources(_ listing: [FusionKitSource]) -> [FusionKitSource] {
        let hits = listing.filter { s in
            guard !s.custom, let name = URL(string: s.url)?.lastPathComponent else { return false }
            return packageArtPrefixes.contains { name.hasPrefix($0) }
        }
        return (hits.isEmpty ? packageArtFallback.map { kitSource(path: $0) } : hits).sorted { $0.title < $1.title }
    }
}

/// Welle F-g Runde 2 / F-l: Ergebnis von `ReadyPackages.withArt` je Collection merken, bis sich Profil oder
/// Kit-Stand ändern (`Stamp`). Die Suche über alle Bildquellen läuft so nur nach einer Änderung,
/// nicht bei jedem Lesen der Startseite.
public struct PackageArtMemo {
    public struct Stamp: Equatable, Sendable {
        public var profile: Int
        public var kit: Int
        public init(profile: Int, kit: Int) { self.profile = profile; self.kit = kit }
    }

    private var stamp: Stamp?
    private var cache: [String: MediaCollection] = [:]

    public init() {}

    /// `sources` wird nur bei einem Fehlgriff ausgewertet.
    public mutating func collection(_ c: MediaCollection, stamp: Stamp, sources: () -> [PackageArtSource]) -> MediaCollection {
        if stamp != self.stamp { cache.removeAll(); self.stamp = stamp }
        if let hit = cache[c.id] { return hit }
        let out = ReadyPackages.withArt(c, sources: sources())
        cache[c.id] = out
        return out
    }
}
