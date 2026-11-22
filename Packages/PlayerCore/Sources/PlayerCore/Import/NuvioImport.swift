import Foundation

public struct NuvioImportResult: Sendable {
    public var collections: [MediaCollection]
    public var skippedSources: Int
    /// Addon-Kataloge ohne bekannte Manifest-URL; werden aktiv, sobald das Addon installiert ist.
    public var pendingAddonSources: [CatalogSource]
    /// Hinweise mit Anzahl, z. B. `tmdb PERSON übersprungen` oder `Addon-Genre ignoriert`.
    public var warnings: [String: Int] = [:]
}

/// Liest den Collections-Export von Nuvio (`nuvio-collections-*.json`).
public enum NuvioImport {
    public static func parse(_ data: Data) throws -> NuvioImportResult {
        let raw = try JSONDecoder().decode([RawCollection].self, from: data)
        var skipped = 0
        var warnings: [String: Int] = [:]
        var pending: [CatalogSource] = []
        var order: [String] = []
        var byTitle: [String: MediaCollection] = [:]

        for rc in raw {
            var folders: [Folder] = []
            let ctitle = rc.title ?? "?"
            for rf in rc.folders ?? [] {
                var sources: [CatalogSource] = []
                // `catalogSources` = altes Feld für Addon-Kataloge (ohne `provider`).
                for rs in (rf.sources ?? []) + (rf.catalogSources ?? []) {
                    guard let s = map(rs, warn: { warnings[$0, default: 0] += 1 }) else { skipped += 1; continue }
                    if case .addon = s.kind { pending.append(s) }
                    sources.append(s)
                }
                let ftitle = rf.title ?? "?"
                // Wave F-o: `focusGifEnabled == false` also switches the focus video off (exports set both together).
                // The WebM variant is never taken (tvOS cannot play it); unplayable addresses fall back to the GIF.
                let motionOn = rf.focusGifEnabled != false
                folders.append(Folder(id: rf.id ?? "nuvio.folder." + stableHash(ctitle + "|" + ftitle), title: ftitle,
                                      coverImage: rf.coverImageUrl, logo: rf.titleLogoUrl, backdrop: rf.heroBackdropUrl,
                                      sources: sources, focusGif: motionOn ? rf.focusGifUrl : nil,
                                      focusVideo: motionOn ? FocusVideoURL.playable(rf.focusVideoUrl) : nil,
                                      heroVideo: FocusVideoURL.playable(rf.heroVideoUrl)))
            }
            let title = ctitle
            if var existing = byTitle[title] {
                existing.folders = mergeFolders(existing.folders, folders)
                byTitle[title] = existing
            } else {
                order.append(title)
                byTitle[title] = MediaCollection(id: rc.id ?? "nuvio.collection." + stableHash(title), title: title,
                                            folders: mergeFolders([], folders))
            }
        }
        var seen = Set<String>()
        pending = pending.filter { seen.insert($0.id).inserted }
        return NuvioImportResult(collections: order.compactMap { byTitle[$0] }, skippedSources: skipped, pendingAddonSources: pending,
                                 warnings: warnings)
    }

    public static func mergeFolders(_ a: [Folder], _ b: [Folder]) -> [Folder] {
        var out = a
        for f in b {
            if let i = out.firstIndex(where: { $0.title == f.title }) {
                var ids = Set(out[i].sources.map(\.id))
                out[i].sources += f.sources.filter { ids.insert($0.id).inserted }
                out[i].coverImage = out[i].coverImage ?? f.coverImage
                out[i].logo = out[i].logo ?? f.logo
                out[i].backdrop = out[i].backdrop ?? f.backdrop
                out[i].focusGif = out[i].focusGif ?? f.focusGif
                out[i].focusVideo = out[i].focusVideo ?? f.focusVideo
                out[i].heroVideo = out[i].heroVideo ?? f.heroVideo
            } else {
                var f = f
                var seen = Set<String>()
                f.sources = f.sources.filter { seen.insert($0.id).inserted }
                out.append(f)
            }
        }
        return out
    }

    static func mediaType(_ s: String?) -> MediaType {
        switch s?.lowercased() {
        case "movie": .movie
        case "tv", "series", "show": .series
        default: .both
        }
    }

    /// `releaseDateGte` → `primary_release_date.gte` (Film) / `first_air_date.gte` (Serie), `voteCountGte` → `vote_count.gte`,
    /// sonst camelCase → snake_case. `sortBy` wird separat behandelt.
    static func tmdbKey(camel k: String, mediaType: MediaType) -> String? {
        if k == "sortBy" { return nil }
        if k == "year" { return mediaType == .series ? "first_air_date_year" : "primary_release_year" }
        var base = k, suffix = ""
        for s in ["Gte", "Lte"] where k.hasSuffix(s) { base = String(k.dropLast(3)); suffix = "." + s.lowercased() }
        if base == "releaseDate" { return (mediaType == .series ? "first_air_date" : "primary_release_date") + suffix }
        var out = ""
        for ch in base { if ch.isUppercase { out += "_" + ch.lowercased() } else { out.append(ch) } }
        return out + suffix
    }

    /// Datums-Filter und -Sortierung auf den Medientyp umschreiben (`/discover/tv` kennt nur `first_air_date…`).
    static func normalizeDateKey(_ k: String, mediaType: MediaType) -> String {
        switch mediaType {
        case .series:
            if k == "year" || k == "primary_release_year" { return "first_air_date_year" }
            for p in ["primary_release_date", "release_date"] where k.hasPrefix(p) { return "first_air_date" + k.dropFirst(p.count) }
        case .movie:
            if k == "year" || k == "first_air_date_year" { return "primary_release_year" }
            if k.hasPrefix("first_air_date") { return "primary_release_date" + k.dropFirst("first_air_date".count) }
        case .both: break
        }
        return k
    }

    /// Sortierung je Medientyp (`primary_release_date.desc` ↔ `first_air_date.desc`); leer/`original` = Reihenfolge der Quelle.
    static func convertSort(_ s: String?, mediaType: MediaType) -> String? {
        guard let s, !s.isEmpty, s != "original" else { return nil }
        return normalizeDateKey(s, mediaType: mediaType)
    }

    /// Reproduzierbarer Kurzschlüssel (FNV-1a 64), damit ein zweiter Import keine Dubletten erzeugt.
    static func stableHash(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    /// Quellen-Schlüssel aus dem Inhalt, wenn der Export keine `id` mitbringt.
    static func sourceKey(_ parts: [String?]) -> String {
        parts.map { $0 ?? "" }.joined(separator: "|")
    }

    static func map(_ r: RawSource, warn: (String) -> Void = { _ in }) -> CatalogSource? {
        let title = r.title ?? r.name ?? "?"
        let provider = r.provider ?? "addon"   // ältere Exporte ohne `provider` sind Addon-Kataloge
        switch provider {
        case "tmdb":
            let mt = mediaType(r.mediaType)
            let sort = convertSort(r.sortBy, mediaType: mt)
            let type = r.tmdbSourceType ?? ""
            switch type {
            case "DISCOVER":
                // Nuvio speichert jeden Filter doppelt (camelCase + snake_case); TMDB braucht snake_case.
                // Manche Filter gibt es nur in camelCase → selbst übersetzen; snake_case gewinnt.
                var f: [String: String] = [:]
                for (k, v) in r.filters ?? [:] where !(k.contains("_") || k.contains(".")) {
                    if let key = tmdbKey(camel: k, mediaType: mt) { f[normalizeDateKey(key, mediaType: mt)] = v.string }
                }
                for (k, v) in r.filters ?? [:] where k.contains("_") || k.contains(".") { f[normalizeDateKey(k, mediaType: mt)] = v.string }
                if let sort { f["sort_by"] = sort }
                let id = r.id ?? "nuvio.tmdb." + stableHash(sourceKey(["DISCOVER", mt.rawValue,
                                                                        f.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")]))
                return CatalogSource(id: id, title: title, kind: .tmdbDiscover(filters: f), mediaType: mt, sortBy: sort)
            case "LIST", "COMPANY", "COLLECTION", "NETWORK":
                guard let t = r.tmdbId?.string, !t.isEmpty else { return nil }
                let id = r.id ?? "nuvio.tmdb." + stableHash(sourceKey([type, t, mt.rawValue, sort]))
                switch type {
                case "LIST": return CatalogSource(id: id, title: title, kind: .tmdbList(id: t), mediaType: mt, sortBy: sort)
                case "COMPANY": return CatalogSource(id: id, title: title, kind: .tmdbCompany(id: t), mediaType: mt, sortBy: sort)
                case "COLLECTION": return CatalogSource(id: id, title: title, kind: .tmdbCollection(id: t), mediaType: mt, sortBy: sort)
                default:
                    // Sender = Serien-Discover mit `with_networks`.
                    let tvSort = convertSort(r.sortBy, mediaType: .series)
                    var f = ["with_networks": t]
                    if let tvSort { f["sort_by"] = tvSort }
                    return CatalogSource(id: id, title: title, kind: .tmdbDiscover(filters: f), mediaType: .series, sortBy: tvSort)
                }
            default:
                // PERSON/DIRECTOR (Filmografie) kann unser Modell nicht abbilden.
                warn("tmdb \(type.isEmpty ? "?" : type) übersprungen")
                return nil
            }
        case "trakt":
            guard let l = r.traktListId else { return nil }
            let mt = mediaType(r.mediaType)
            return CatalogSource(id: r.id ?? "trakt-\(l.string)", title: title, kind: .trakt(user: nil, list: l.string),
                                 mediaType: mt, sortBy: r.sortBy)
        case "addon":
            guard let a = r.addonId, let c = r.catalogId else { return nil }
            let type = r.type ?? "movie"
            // Genre-Extra kann `SourceKind.addon` (noch) nicht tragen; Quelle bleibt, Genre wird gezählt.
            let genre = r.genre.flatMap { $0.isEmpty || $0 == "None" ? nil : $0 }
            if genre != nil { warn("Addon-Genre ignoriert") }
            let id = r.id ?? "addon:\(a):\(type):\(c)" + (genre.map { ":genre=\($0)" } ?? "")
            return CatalogSource(id: id, title: r.title ?? (genre.map { "\(c) · \($0)" } ?? c),
                                 kind: .addon(addonId: a, catalogId: c, type: type), mediaType: mediaType(type))
        default:
            return nil
        }
    }

    // MARK: Roh-Format (nur die Felder, die wir brauchen; Rest wird ignoriert)

    struct RawCollection: Decodable { var id: String?; var title: String?; var folders: [RawFolder]? }
    struct RawFolder: Decodable {
        var id: String?; var title: String?; var coverImageUrl: String?; var titleLogoUrl: String?
        var heroBackdropUrl: String?; var sources: [RawSource]?; var catalogSources: [RawSource]?
        /// Bewegtes Fokusbild (Welle F-g); `focusGifEnabled == false` schaltet es ab.
        var focusGifUrl: String?; var focusGifEnabled: Bool?
        /// Wave F-o: focus video (mp4) and hero video; `focusVideoWebmUrl` is read but never used (no WebM on tvOS).
        var focusVideoUrl: String?; var focusVideoWebmUrl: String?; var heroVideoUrl: String?
    }
    struct RawSource: Decodable {
        var id: String?; var name: String?; var title: String?; var provider: String?
        var tmdbSourceType: String?; var mediaType: String?; var sortBy: String?
        var tmdbId: Scalar?; var traktListId: Scalar?; var addonId: String?; var catalogId: String?; var type: String?; var genre: String?
        var filters: [String: Scalar]?
    }

    /// Zahl, String oder Bool aus JSON als String.
    struct Scalar: Decodable {
        var string: String
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let i = try? c.decode(Int.self) { string = String(i) }
            else if let d = try? c.decode(Double.self) { string = String(d) }
            else if let b = try? c.decode(Bool.self) { string = String(b) }
            else if let s = try? c.decode(String.self) { string = s }
            else { string = "" }
        }
    }
}
