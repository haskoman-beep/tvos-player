import Foundation

// Fusion-Startseiten-Kit (kit.betterer.cc, Format `fusionWidgets` v1) → unsere Reihen.
// Kit-Dateien haben keine Lizenz: sie werden nur zur Laufzeit per URL geladen, nichts davon liegt im Repo.

/// Was eine Quelle zum Laden braucht.
public struct FusionNeeds: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    /// Öffentliche Trakt-Liste: die Trakt Client ID reicht.
    public static let traktID = FusionNeeds(rawValue: 1)
    /// Eigene Trakt-Merkliste: zusätzlich Anmeldung.
    public static let traktLogin = FusionNeeds(rawValue: 2)
    public static let tmdb = FusionNeeds(rawValue: 4)

    public static func of(_ s: CatalogSource) -> FusionNeeds {
        switch s.kind {
        case .trakt(let user, let list):
            return user == nil && (FusionImport.isWatchlistSlug(list) || TraktClient.isRecommendations(list)) ? [.traktID, .traktLogin] : .traktID
        case .watchlist: return []
        case .tmdbDiscover, .tmdbList, .tmdbCompany, .tmdbCollection: return .tmdb
        default: return []
        }
    }
}

/// Eine Reihe aus dem Kit: Titelliste (`row.classic`) oder Kachel-Reihe (`collection.row`).
public struct FusionKitRow: Sendable, Hashable, Identifiable {
    public enum Body: Sendable, Hashable {
        case list(CatalogSource)
        case collection(MediaCollection)
    }

    /// `fusion.<quelle>.<widget-id>`; zugleich ID der Quelle bzw. der Collection.
    public var id: String
    public var title: String
    public var style: RowStyle
    public var body: Body
    /// Seitenverhältnis der Kachelbilder laut Kit (`wide`, `poster`, `square`); nil bei Titellisten.
    public var imageAspect: String?

    public init(id: String, title: String, style: RowStyle, body: Body, imageAspect: String? = nil) {
        self.id = id; self.title = title; self.style = style; self.body = body; self.imageAspect = imageAspect
    }

    public var content: RowContent {
        switch body {
        case .list(let s): .list(s)
        case .collection(let c): .collection(id: c.id)
        }
    }

    public var needs: FusionNeeds {
        switch body {
        case .list(let s): FusionNeeds.of(s)
        case .collection(let c): c.folders.flatMap(\.sources).reduce(into: FusionNeeds()) { $0.formUnion(.of($1)) }
        }
    }

    /// Nur Quellen, die mit den vorhandenen Diensten laden (Trakt ohne Client ID bzw. ohne Anmeldung fällt weg);
    /// Kacheln ohne Quelle entfallen. nil = nichts bleibt übrig, Reihe ausblenden.
    public func available(traktID: Bool, traktLogin: Bool) -> FusionKitRow? {
        func ok(_ s: CatalogSource) -> Bool {
            let n = FusionNeeds.of(s)
            if n.contains(.traktID) && !traktID { return false }
            if n.contains(.traktLogin) && !traktLogin { return false }
            return true
        }
        switch body {
        case .list(let s):
            return ok(s) ? self : nil
        case .collection(var c):
            c.folders = c.folders.compactMap { f in
                var f = f
                f.sources = f.sources.filter(ok)
                return f.sources.isEmpty ? nil : f
            }
            guard !c.folders.isEmpty else { return nil }
            var r = self
            r.body = .collection(c)
            return r
        }
    }
}

/// Gelesene Kit-Datei.
public struct FusionKitContent: Sendable, Hashable {
    public var rows: [FusionKitRow]
    /// Hinweise mit Anzahl, z. B. `traktRecommendations übersprungen` oder `Kachel ohne Quellen`.
    public var warnings: [String: Int]

    public init(rows: [FusionKitRow], warnings: [String: Int] = [:]) { self.rows = rows; self.warnings = warnings }

    public func row(_ id: String) -> FusionKitRow? { rows.first { $0.id == id } }
}

public enum FusionImportError: Error, Equatable, CustomStringConvertible {
    case unknownFormat
    case iconPack

    public var description: String {
        switch self {
        case .unknownFormat: "kein Fusion-Kit-Format (fusionWidgets oder Collection-Liste erwartet)"
        case .iconPack: "Bewertungs-Icon-Satz – wird (noch) nicht unterstützt"
        }
    }
}

/// Liest Kit-Dateien: `{"exportType":"fusionWidgets","widgets":[…]}` (Setups und Kachel-Reihen) oder die
/// flache Collection-Liste `[{"name","backgroundImageURL","dataSources"}]`. Unbekanntes wird gezählt, nie abgebrochen.
public enum FusionImport {
    public static let idPrefix = "fusion."

    public static func isKitID(_ id: String) -> Bool { id.hasPrefix(idPrefix) }

    /// Quellen-Schlüssel aus einer ID `fusion.<quelle>.<…>`.
    public static func sourceKey(ofID id: String) -> String? {
        guard isKitID(id) else { return nil }
        let rest = id.dropFirst(idPrefix.count)
        guard let dot = rest.firstIndex(of: "."), dot > rest.startIndex else { return nil }
        return String(rest[..<dot])
    }

    /// Kit-ID einer Startseiten-Reihe (nil = eigene Reihe des Nutzers).
    public static func kitID(of row: HomeRow) -> String? {
        switch row.content {
        case .list(let s): isKitID(s.id) ? s.id : nil
        case .collection(let id): isKitID(id) ? id : nil
        }
    }

    /// Eigene Trakt-Merkliste (`watchlist`, `watchlist/movies`, `watchlist/shows`).
    static func isWatchlistSlug(_ s: String) -> Bool { s == "watchlist" || s.hasPrefix("watchlist/") }

    /// - Parameters:
    ///   - sourceKey: Schlüssel der Kit-Datei (Teil aller IDs, damit zwei Dateien sich nicht in die Quere kommen).
    ///   - title: Reihentitel für die flache Collection-Liste (die hat keinen eigenen).
    ///   - now: day for "released" (TMDB date filter), stored at parse. A-B-10: `requestFilters` replaces it with
    ///     the current day at request time; the stored value stays for older builds.
    public static func parse(_ data: Data, sourceKey: String, title: String = "Kit", now: Date = Date()) throws -> FusionKitContent {
        let any = try JSONSerialization.jsonObject(with: data)
        var warnings: [String: Int] = [:]
        let warn: (String) -> Void = { warnings[$0, default: 0] += 1 }
        let ctx = Context(sourceKey: sourceKey, today: day(now), warn: warn)
        var rows: [FusionKitRow] = []

        if let obj = any as? [String: Any] {
            guard obj["exportType"] as? String == "fusionWidgets" || obj["widgets"] != nil else { throw FusionImportError.unknownFormat }
            if let v = obj["exportVersion"] as? Int, v != 1 { warn("exportVersion \(v) unbekannt") }
            // Reihe für Reihe: eine kaputte Reihe kostet nur sich selbst, nie die ganze Datei.
            let export = try JSONDecoder().decode(RawExport.self, from: data)
            if export.widgetsUnreadable { warn("widgets unlesbar") }
            for _ in 0..<(export.widgets?.failed ?? 0) { warn("Reihe unlesbar") }
            var seen = Set<String>()
            for (i, w) in (export.widgets?.items ?? []).enumerated() {
                let rowID = idPrefix + sourceKey + "." + (w.id ?? "w\(i)")
                guard seen.insert(rowID).inserted else { warn("doppelte Reihe"); continue }
                if let r = row(w, id: rowID, ctx: ctx) { rows.append(r) }
            }
        } else if let arr = any as? [[String: Any]] {
            if let first = arr.first, first["url"] != nil, first["dataSources"] == nil, first["dataSource"] == nil {
                throw FusionImportError.iconPack
            }
            let list = try JSONDecoder().decode(LossyList<RawItem>.self, from: data)
            for _ in 0..<list.failed { warn("Kachel unlesbar") }
            let items = list.items
            let rowID = idPrefix + sourceKey + ".collection"
            let folders = folders(items, rowID: rowID, ctx: ctx)
            if folders.isEmpty { warn("Collection ohne Kacheln mit Quellen") } else {
                rows.append(FusionKitRow(id: rowID, title: germanTitle(title), style: .collectionTiles,
                                         body: .collection(MediaCollection(id: rowID, title: germanTitle(title), folders: folders)),
                                         imageAspect: aspect(items)))
            }
        } else {
            throw FusionImportError.unknownFormat
        }
        return FusionKitContent(rows: rows, warnings: warnings)
    }

    struct Context {
        let sourceKey: String
        let today: String
        let warn: (String) -> Void
    }

    static func row(_ w: RawWidget, id: String, ctx: Context) -> FusionKitRow? {
        let title = germanTitle(w.title ?? "?")
        guard let ds = w.dataSource else { ctx.warn("Reihe ohne Quelle"); return nil }
        if ds.kind == "collection" {
            for _ in 0..<(ds.payload?.items?.failed ?? 0) { ctx.warn("Kachel unlesbar") }
            let items = ds.payload?.items?.items ?? []
            let folders = folders(items, rowID: id, ctx: ctx)
            guard !folders.isEmpty else { ctx.warn("Collection ohne Kacheln mit Quellen"); return nil }
            return FusionKitRow(id: id, title: title, style: .collectionTiles,
                                body: .collection(MediaCollection(id: id, title: title, folders: folders)), imageAspect: aspect(items))
        }
        let style: RowStyle
        switch w.type {
        case "row.classic.numbered": style = .top10
        case "row.classic", nil: style = .poster
        case let t?: ctx.warn("Reihentyp \(t) als Poster-Reihe"); style = .poster
        }
        guard var s = source(ds, id: id, title: title, ctx: ctx) else { return nil }
        if let n = w.limit, n > 0 { s.limit = n }
        return FusionKitRow(id: id, title: title, style: style, body: .list(s))
    }

    static func folders(_ items: [RawItem], rowID: String, ctx: Context) -> [Folder] {
        var out: [Folder] = []
        var seen = Set<String>()
        for (j, it) in items.enumerated() {
            let fid = rowID + "." + (it.id ?? "i\(j)")
            guard seen.insert(fid).inserted else { ctx.warn("doppelte Kachel"); continue }
            let ftitle = it.title ?? it.name ?? "?"
            for _ in 0..<(it.dataSources?.failed ?? 0) { ctx.warn("Quelle unlesbar") }
            let raw = it.dataSources?.items ?? it.dataSource.map { [$0] } ?? []
            var sources: [CatalogSource] = []
            for (k, s) in raw.enumerated() {
                if let c = source(s, id: "\(fid).\(k)", title: s.payload?.listName ?? ftitle, ctx: ctx) { sources.append(c) }
            }
            guard !sources.isEmpty else { ctx.warn("Kachel ohne Quellen"); continue }
            // Wave F-o round 2: animated tiles of a widget export (video before GIF, see TileMotion).
            let gif = imageURL(it.focusGifURL ?? it.focusGifUrl ?? it.gifURL)
            let video = [it.focusVideoURL, it.focusVideoUrl, it.videoURL].lazy.compactMap { FocusVideoURL.playable($0) }.first
            out.append(Folder(id: fid, title: ftitle, coverImage: imageURL(it.imageURL ?? it.backgroundImageURL), sources: sources,
                              hideTitle: it.hideTitle, focusGif: gif, focusVideo: video))
        }
        return out
    }

    /// Bild-URL wie geliefert; nur wenn sie so nicht gültig ist (Leerzeichen, Umlaute), prozent-kodiert.
    static func imageURL(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        // Vorhandene `%xx` bleiben, nur unzulässige Zeichen werden kodiert (kein doppeltes Kodieren).
        let allowed = CharacterSet.urlFragmentAllowed.union(CharacterSet(charactersIn: "%#"))
        if s.unicodeScalars.allSatisfy(allowed.contains) { return s }
        return s.addingPercentEncoding(withAllowedCharacters: allowed)
    }

    /// Häufigstes Seitenverhältnis der Kacheln (`imageAspect` bzw. `layout` der Collection-Liste).
    static func aspect(_ items: [RawItem]) -> String? {
        var n: [String: Int] = [:]
        for it in items { if let a = (it.imageAspect ?? it.layout)?.lowercased() { n[a, default: 0] += 1 } }
        return n.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key
    }

    static func source(_ r: RawSource, id: String, title: String, ctx: Context) -> CatalogSource? {
        let p = r.payload
        switch r.kind {
        case "traktList":
            guard let user = p?.username, !user.isEmpty, let slug = p?.listSlug, !slug.isEmpty else {
                ctx.warn("Trakt-Liste ohne Nutzer/Slug"); return nil
            }
            guard user == "__me__" else {
                guard TraktClient.isSafeName(user), TraktClient.isSafeName(slug) else { ctx.warn("Trakt-Liste mit ungültigem Namen"); return nil }
                return CatalogSource(id: id, title: title, kind: .trakt(user: user, list: slug), mediaType: .both)
            }
            // Eigene Merkliste des angemeldeten Nutzers (Fusion: `__me__` + `__watchlist_*__`).
            switch slug {
            case "__watchlist_all__": return CatalogSource(id: id, title: title, kind: .trakt(user: nil, list: "watchlist"), mediaType: .both)
            case "__watchlist_movies__": return CatalogSource(id: id, title: title, kind: .trakt(user: nil, list: "watchlist/movies"), mediaType: .movie)
            case "__watchlist_shows__": return CatalogSource(id: id, title: title, kind: .trakt(user: nil, list: "watchlist/shows"), mediaType: .series)
            default: ctx.warn("eigene Trakt-Liste \(slug) übersprungen"); return nil
            }
        case "tmdbDiscover":
            guard let p else { ctx.warn("TMDB-Discover ohne Angaben"); return nil }
            let mt: MediaType = ["tv", "show", "shows", "series"].contains(p.type?.lowercased() ?? "") ? .series : .movie
            var f: [String: String] = [:]
            if let g = p.includeGenres, !g.isEmpty { f["with_genres"] = g.map { String($0) }.joined(separator: ",") }
            if let g = p.excludeGenres, !g.isEmpty { f["without_genres"] = g.map { String($0) }.joined(separator: ",") }
            if let s = NuvioImport.convertSort(p.sortBy, mediaType: mt) { f["sort_by"] = s }
            if mt == .movie, let rc = p.releaseChannel {
                switch rc {
                case "theatrical": f["with_release_type"] = "2|3"
                case "digital": f["with_release_type"] = "4"
                case "physical": f["with_release_type"] = "5"
                default: ctx.warn("releaseChannel \(rc) ignoriert")
                }
            }
            if let rs = p.releaseStatus {
                if rs == "released" {
                    // Mit Veröffentlichungsart gilt `release_date` (Datum dieser Art), sonst das Erstdatum.
                    let key = mt == .series ? "first_air_date.lte" : (f["with_release_type"] != nil ? "release_date.lte" : "primary_release_date.lte")
                    f[key] = ctx.today
                } else { ctx.warn("releaseStatus \(rs) ignoriert") }
            }
            let suffix = mt == .series ? "Serien" : "Filme"
            return CatalogSource(id: id, title: "\(title) · \(suffix)", kind: .tmdbDiscover(filters: f), mediaType: mt, sortBy: f["sort_by"])
        case "traktRecommendations":
            // Braucht Trakt-Anmeldung (FusionNeeds); `type` movies/shows, sonst Filme.
            let series = ["shows", "show", "tv", "series"].contains(p?.type?.lowercased() ?? "")
            return CatalogSource(id: id, title: title, kind: .trakt(user: nil, list: series ? "recommendations/shows" : "recommendations/movies"),
                                 mediaType: series ? .series : .movie, limit: p?.limit)
        case let k?:
            ctx.warn("Quelle \(k) übersprungen"); return nil
        case nil:
            ctx.warn("Quelle ohne Art"); return nil
        }
    }

    /// Kit-Titel der Kachel-Reihen auf Deutsch; Variantenzusatz wie „(Color)“ entfällt. Unbekanntes bleibt.
    static func germanTitle(_ t: String) -> String {
        var base = t.trimmingCharacters(in: .whitespaces)
        if base.hasSuffix(")"), let open = base.lastIndex(of: "("), open > base.startIndex {
            base = String(base[..<open]).trimmingCharacters(in: .whitespaces)
        }
        let map = ["Decades": "Jahrzehnte", "Directors": "Regie", "Awards": "Preise", "Genres": "Genres", "Streaming": "Streaming",
                   "Streaming Services": "Streaming-Dienste", "Movie Genres": "Film-Genres", "Movie Collections": "Filmreihen",
                   "Popular Genres": "Beliebte Genres", "Popular Decades": "Beliebte Jahrzehnte", "Discover": "Entdecken"]
        return map[base] ?? t
    }

    /// A-B-10: date keys that `releaseStatus: "released"` sets (the only way a kit discover filter gets them).
    static let releasedDateKeys = ["primary_release_date.lte", "release_date.lte", "first_air_date.lte"]

    /// A-B-10: filters as sent to TMDB. For a kit source (`fusion.` ID) the "released" cut-off is the current
    /// local day at request time, not the day of the last parse. The stored filter keeps its literal date, so the
    /// layout format is unchanged and older builds still send a valid (if stale) date; own rows stay untouched.
    public static func requestFilters(_ filters: [String: String], sourceID: String, now: Date,
                                      calendar: Calendar = Upcoming.localCalendar) -> [String: String] {
        guard isKitID(sourceID) else { return filters }
        var f = filters
        let today = Upcoming.dayKey(now, calendar: calendar)
        for k in releasedDateKeys where f[k] != nil { f[k] = today }
        return f
    }

    /// `yyyy-MM-dd` (UTC) für TMDB-Datumsfilter.
    static func day(_ d: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: d)
        func pad(_ n: Int?, _ w: Int) -> String { let s = String(n ?? 1); return String(repeating: "0", count: max(0, w - s.count)) + s }
        return "\(pad(c.year, 4))-\(pad(c.month, 2))-\(pad(c.day, 2))"
    }

    // MARK: Roh-Format (nur die Felder, die wir brauchen; Rest wird ignoriert)

    struct RawExport: Decodable {
        var widgets: LossyList<RawWidget>?
        /// `widgets` da, aber keine Liste.
        var widgetsUnreadable = false
        enum CodingKeys: String, CodingKey { case widgets }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            do { widgets = try c.decodeIfPresent(LossyList<RawWidget>.self, forKey: .widgets) } catch { widgetsUnreadable = true }
        }
    }
    struct RawWidget: Decodable { var id: String?; var title: String?; var type: String?; var limit: Int?; var dataSource: RawSource? }
    struct RawSource: Decodable { var kind: String?; var payload: RawPayload? }
    struct RawPayload: Decodable {
        var username: String?; var listSlug: String?; var listName: String?
        var type: String?; var includeGenres: [Int]?; var excludeGenres: [Int]?; var sortBy: String?
        var releaseChannel: String?; var releaseStatus: String?; var limit: Int?
        var items: LossyList<RawItem>?
    }
    struct RawItem: Decodable {
        var id: String?; var title: String?; var name: String?
        var imageURL: String?; var backgroundImageURL: String?; var imageAspect: String?; var layout: String?
        var hideTitle: Bool?
        var dataSources: LossyList<RawSource>?; var dataSource: RawSource?
        // Wave F-o round 2: optional motion fields (spellings seen in widget and collection exports).
        var focusVideoURL: String?; var focusVideoUrl: String?; var videoURL: String?
        var focusGifURL: String?; var focusGifUrl: String?; var gifURL: String?
    }
}

/// Liste, die unlesbare Einträge überspringt und zählt (statt die ganze Datei abzulehnen).
struct LossyList<T: Decodable>: Decodable {
    var items: [T] = []
    var failed = 0

    private struct Skip: Decodable { init(from decoder: Decoder) throws {} }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        while !c.isAtEnd {
            if let v = try? c.decode(T.self) { items.append(v); continue }
            failed += 1
            // Ein fehlgeschlagenes decode rückt nicht weiter; Skip verbraucht den Eintrag.
            guard (try? c.decode(Skip.self)) != nil else { break }
        }
    }
}
