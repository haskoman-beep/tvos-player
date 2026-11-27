import Foundation

/// Build 7: the studio page. A studio plate of the detail page opens a page with what that company or network made,
/// as the genre page (filter Filme / Serien, endless poster grid by popularity). The page is a synthetic folder
/// (`Route.folder`, ID prefix `studio.`), so it reuses `GenrePageView` and the normal navigation stack.
/// - Production company: films and series (`with_companies`, the same ID on both discover endpoints).
/// - TV network: series only (`with_networks`; TMDB has no network filter for films, the IDs are another space).
public enum StudioPage {
    public static let folderPrefix = "studio."
    public static let sortBy = "popularity.desc"

    /// The page folder of `studio`; nil without a TMDB ID (the plate then stays a plain, non-selectable plate).
    public static func folder(for studio: StudioLogo) -> Folder? {
        guard let id = studio.id, id > 0 else { return nil }
        let base = folderPrefix + "\(studio.kind.rawValue).\(id)"
        var sources: [CatalogSource] = []
        switch studio.kind {
        case .company:
            let f = ["with_companies": String(id), "sort_by": sortBy]
            sources.append(CatalogSource(id: base + ".movies", title: studio.name, kind: .tmdbDiscover(filters: f), mediaType: .movie))
            sources.append(CatalogSource(id: base + ".series", title: studio.name, kind: .tmdbDiscover(filters: f), mediaType: .series))
        case .network:
            let f = ["with_networks": String(id), "sort_by": sortBy]
            sources.append(CatalogSource(id: base + ".series", title: studio.name, kind: .tmdbDiscover(filters: f), mediaType: .series))
        }
        return Folder(id: base, title: studio.name, logo: studio.logo, sources: sources)
    }

    public static func isStudio(_ folder: Folder) -> Bool { folder.id.hasPrefix(folderPrefix) }

    /// Header image of the page: the studio logo (only studio folders; genre folders keep their title header).
    public static func headerLogo(_ folder: Folder) -> String? {
        guard isStudio(folder), let l = folder.logo, !l.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return l
    }

    /// Word in the page's log lines: „Studio: Pixar geöffnet …“ / „Genre: Action geöffnet …“.
    public static func logLabel(_ folder: Folder) -> String { isStudio(folder) ? "Studio" : "Genre" }
}

/// Build 7: logos for studio plates TMDB lists without `logo_path`, from the company / network image list.
public enum StudioLogoFill {
    /// Plates that need a lookup: no logo, but a TMDB ID; each studio once.
    public static func lookups(_ studios: [StudioLogo]) -> [StudioLogo] {
        var seen = Set<String>()
        return studios.filter { s in
            guard s.logo == nil, let k = s.key else { return false }
            return seen.insert(k).inserted
        }
    }

    /// `studios` with the found logos (by `StudioLogo.key`); the rest unchanged.
    public static func apply(_ studios: [StudioLogo], found: [String: String]) -> [StudioLogo] {
        studios.map { s in
            guard s.logo == nil, let k = s.key, let l = found[k] else { return s }
            var c = s; c.logo = l; return c
        }
    }

    /// Best logo of a TMDB `/company|network/{id}/images` answer, as a w300 address: raster files only (an SVG path
    /// does not decode), the best rated first, then the most votes, then the wider one; nil when there is none.
    public static func bestLogo(imagesJSON data: Data) -> String? {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let logos = o["logos"] as? [[String: Any]] else { return nil }
        func num(_ v: Any?) -> Double { (v as? Double) ?? (v as? Int).map(Double.init) ?? 0 }
        let usable = logos.compactMap { l -> (path: String, vote: Double, count: Double, width: Double)? in
            guard let p = (l["file_path"] as? String)?.trimmingCharacters(in: .whitespaces), p.hasPrefix("/"),
                  !p.lowercased().hasSuffix(".svg") else { return nil }
            return (p, num(l["vote_average"]), num(l["vote_count"]), num(l["width"]))
        }
        let best = usable.enumerated().min { a, b in
            if a.element.vote != b.element.vote { return a.element.vote > b.element.vote }
            if a.element.count != b.element.count { return a.element.count > b.element.count }
            if a.element.width != b.element.width { return a.element.width > b.element.width }
            return a.offset < b.offset
        }
        return best.map { TMDBClient.studioLogoBase + $0.element.path }
    }

    /// Log line of the detail row: „Studios 3, mit Logo 2, Text 1“ (Text = plate with the name, no logo found).
    public static func logLine(_ studios: [StudioLogo]) -> String {
        let withLogo = studios.filter { $0.logo != nil }.count
        return "Studios \(studios.count), mit Logo \(withLogo), Text \(studios.count - withLogo)"
    }
}

extension TMDBClient {
    /// Build 7: a logo for a studio TMDB gives without `logo_path` (nil when its image list has none either).
    public func studioLogo(_ studio: StudioLogo) async throws -> String? {
        guard let id = studio.id else { return nil }
        let data = try await http.data(from: url("/\(studio.kind.rawValue)/\(id)/images"))
        return StudioLogoFill.bestLogo(imagesJSON: data)
    }
}
