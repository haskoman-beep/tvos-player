import Foundation

public struct NuvioImportResult: Sendable {
    public var collections: [Collection]
    public var skippedSources: Int
    /// Addon-Kataloge ohne bekannte Manifest-URL; werden aktiv, sobald das Addon installiert ist.
    public var pendingAddonSources: [CatalogSource]
}

/// Liest den Collections-Export von Nuvio (`nuvio-collections-*.json`).
public enum NuvioImport {
    public static func parse(_ data: Data) throws -> NuvioImportResult {
        let raw = try JSONDecoder().decode([RawCollection].self, from: data)
        var skipped = 0
        var pending: [CatalogSource] = []
        var order: [String] = []
        var byTitle: [String: Collection] = [:]

        for rc in raw {
            var folders: [Folder] = []
            for rf in rc.folders ?? [] {
                var sources: [CatalogSource] = []
                for rs in rf.sources ?? [] {
                    guard let s = map(rs) else { skipped += 1; continue }
                    if case .addon = s.kind { pending.append(s) }
                    sources.append(s)
                }
                folders.append(Folder(id: rf.id ?? UUID().uuidString, title: rf.title ?? "?",
                                      coverImage: rf.coverImageUrl, logo: rf.titleLogoUrl, backdrop: rf.heroBackdropUrl,
                                      sources: sources))
            }
            let title = rc.title ?? "?"
            if var existing = byTitle[title] {
                existing.folders = mergeFolders(existing.folders, folders)
                byTitle[title] = existing
            } else {
                order.append(title)
                byTitle[title] = Collection(id: rc.id ?? UUID().uuidString, title: title,
                                            folders: mergeFolders([], folders))
            }
        }
        var seen = Set<String>()
        pending = pending.filter { seen.insert($0.id).inserted }
        return NuvioImportResult(collections: order.compactMap { byTitle[$0] }, skippedSources: skipped, pendingAddonSources: pending)
    }

    static func mergeFolders(_ a: [Folder], _ b: [Folder]) -> [Folder] {
        var out = a
        for f in b {
            if let i = out.firstIndex(where: { $0.title == f.title }) {
                let ids = Set(out[i].sources.map(\.id))
                out[i].sources += f.sources.filter { !ids.contains($0.id) }
                out[i].coverImage = out[i].coverImage ?? f.coverImage
                out[i].logo = out[i].logo ?? f.logo
                out[i].backdrop = out[i].backdrop ?? f.backdrop
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
        var base = k, suffix = ""
        for s in ["Gte", "Lte"] where k.hasSuffix(s) { base = String(k.dropLast(3)); suffix = "." + s.lowercased() }
        if base == "releaseDate" { return (mediaType == .series ? "first_air_date" : "primary_release_date") + suffix }
        var out = ""
        for ch in base { if ch.isUppercase { out += "_" + ch.lowercased() } else { out.append(ch) } }
        return out + suffix
    }

    static func map(_ r: RawSource) -> CatalogSource? {
        let title = r.title ?? r.name ?? "?"
        let sort = r.sortBy == "original" ? nil : r.sortBy
        switch r.provider {
        case "tmdb":
            let id = r.id ?? UUID().uuidString
            let mt = mediaType(r.mediaType)
            switch r.tmdbSourceType {
            case "DISCOVER":
                // Nuvio speichert jeden Filter doppelt (camelCase + snake_case); TMDB braucht snake_case.
                // Manche Filter gibt es nur in camelCase → selbst übersetzen; snake_case gewinnt.
                var f: [String: String] = [:]
                for (k, v) in r.filters ?? [:] where !(k.contains("_") || k.contains(".")) {
                    if let key = tmdbKey(camel: k, mediaType: mt) { f[key] = v.string }
                }
                for (k, v) in r.filters ?? [:] where k.contains("_") || k.contains(".") { f[k] = v.string }
                if let sort { f["sort_by"] = sort }
                return CatalogSource(id: id, title: title, kind: .tmdbDiscover(filters: f), mediaType: mt, sortBy: sort)
            case "LIST":
                guard let t = r.tmdbId else { return nil }
                return CatalogSource(id: id, title: title, kind: .tmdbList(id: t.string), mediaType: mt, sortBy: sort)
            case "COMPANY":
                guard let t = r.tmdbId else { return nil }
                return CatalogSource(id: id, title: title, kind: .tmdbCompany(id: t.string), mediaType: mt, sortBy: sort)
            case "COLLECTION":
                guard let t = r.tmdbId else { return nil }
                return CatalogSource(id: id, title: title, kind: .tmdbCollection(id: t.string), mediaType: mt, sortBy: sort)
            default:
                return nil
            }
        case "trakt":
            guard let l = r.traktListId else { return nil }
            return CatalogSource(id: r.id ?? "trakt-\(l.string)", title: title, kind: .trakt(user: nil, list: l.string),
                                 mediaType: mediaType(r.mediaType), sortBy: r.sortBy)
        case "addon":
            guard let a = r.addonId, let c = r.catalogId else { return nil }
            let type = r.type ?? "movie"
            return CatalogSource(id: r.id ?? "addon:\(a):\(type):\(c)", title: r.title ?? c, kind: .addon(addonId: a, catalogId: c, type: type),
                                 mediaType: mediaType(type))
        default:
            return nil
        }
    }

    // MARK: Roh-Format (nur die Felder, die wir brauchen; Rest wird ignoriert)

    struct RawCollection: Decodable { var id: String?; var title: String?; var folders: [RawFolder]? }
    struct RawFolder: Decodable {
        var id: String?; var title: String?; var coverImageUrl: String?; var titleLogoUrl: String?
        var heroBackdropUrl: String?; var sources: [RawSource]?
    }
    struct RawSource: Decodable {
        var id: String?; var name: String?; var title: String?; var provider: String?
        var tmdbSourceType: String?; var mediaType: String?; var sortBy: String?
        var tmdbId: Scalar?; var traktListId: Scalar?; var addonId: String?; var catalogId: String?; var type: String?
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
