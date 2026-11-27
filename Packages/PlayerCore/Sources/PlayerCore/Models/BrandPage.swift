import Foundation

/// Build 8: studio and streaming tiles of the home screen (rows „Studios“, „Streaming“, „Dienste“ … and the package
/// `pkg.streaming-de.*`) open the studio page of build 7 (`GenrePageView`: filter Filme / Serien, endless poster grid)
/// instead of the row page. The user's tiles are mostly Fusion imports with addon catalogs whose IDs carry no TMDB
/// ID, so the mapping goes by the folder title, in this order:
/// 1. `pkg.streaming-de.<provider>`: its own popular film / series lists (already TMDB, region DE).
/// 2. Normalised title against the tables below: streaming service (TMDB watch provider, region DE, US when DE has
///    nothing), production company (`with_companies`) or TV network (`with_networks`, series only). A streaming row
///    looks up services first, a studio row companies first („Disney“ is Disney+ there and Walt Disney Pictures here).
/// 3. The folder's own TMDB lists, when they already make a film / series pair.
/// 4. A cached TMDB `/search/company` by the title (exact folded name only, `CompanySearchCache`).
/// 5. The folder's own addon catalogs (one film and one series catalog), paged by `skip`.
/// Everything else (Trakt lists, mixed lists, more lists) keeps the row page.
public enum BrandPage {
    public enum Kind: String, Sendable, Equatable { case provider, company, network }

    /// Where the titles come from; the word in the log line „Quelle …“.
    public enum Origin: String, Sendable, Equatable {
        case tmdbProvider = "tmdb-provider"
        case tmdbCompany = "tmdb-company"
        case tmdbNetwork = "tmdb-network"
        case search = "suche"
        case folder = "ordner"
        case addon = "addon"
    }

    /// The kind of row a tile sits in.
    public enum RowKind: Sendable, Equatable { case streaming, studios }

    /// One known service, company or network. `ids`: TMDB ID(s), `|` = any of them.
    public struct Entry: Sendable, Equatable {
        public let name: String
        public let kind: Kind
        public let ids: String
        /// Normalised names (`ReadyPackages.normalizedArtName`), the own name first.
        public let names: [String]
        /// The page opens on Serien (services that are mostly series).
        public let seriesFirst: Bool

        init(_ name: String, _ kind: Kind, _ ids: String, _ aliases: [String] = [], seriesFirst: Bool = false) {
            self.name = name; self.kind = kind; self.ids = ids; self.seriesFirst = seriesFirst
            var n = [ReadyPackages.normalizedArtName(name)]
            for a in aliases.map(ReadyPackages.normalizedArtName) where !n.contains(a) { n.append(a) }
            names = n
        }

        /// First ID (logo lookup).
        public var firstID: Int? { ids.split(separator: "|").first.flatMap { Int($0) } }
    }

    /// Header of the page: the logo as a white shape (folder logo, TMDB logo), else the tile picture with the name,
    /// else the name. `tmdbLogo`: a company / network whose TMDB logo the app looks up when `logo` is nil.
    public struct Header: Sendable, Equatable {
        public var logo: String?
        public var tmdbLogo: StudioLogo?
        public var tile: String?
    }

    /// A resolved page.
    public struct Grid: Sendable, Equatable {
        /// „Dienst“ or „Studio“ (log lines).
        public let label: String
        public let origin: Origin
        public let sources: GenrePageSources
        public let initial: GenreFilter
        /// Region DE source ID → the same list for region US (a watch provider with nothing in DE).
        public let regionFallback: [String: CatalogSource]
        public let header: Header
    }

    public enum Resolution: Sendable, Equatable {
        case grid(Grid)
        /// Not in the tables: the app searches TMDB for the company (`CompanySearchCache`), then resolves again.
        case search(query: String, key: String)
        /// Not a studio / streaming tile, or nothing pageable: the row page (or the genre rule) decides.
        case rowPage
    }

    public static let streamingPackagePrefix = "pkg.streaming-de."
    public static let sortBy = "popularity.desc"
    public static let region = "DE"
    public static let fallbackRegion = "US"
    /// Free and ad-supported services (Joyn) count as well as subscriptions.
    public static let monetization = "flatrate|free|ads"

    // MARK: Tables

    /// TMDB watch provider IDs. Marked „unsure“: from memory of the TMDB provider list, not checked against the API
    /// here; a wrong ID shows another service or (DE and US empty) „Keine Titel gefunden.“.
    public static let providers: [Entry] = [
        Entry("Netflix", .provider, "8", ["netflixred", "netflixdark", "netflixwhite"]),
        Entry("Prime Video", .provider, "9|119", ["amazonprimevideo", "amazonprime", "prime", "amazon", "amazonvideo"]),
        Entry("Disney+", .provider, "337", ["disney"]),
        Entry("Apple TV+", .provider, "350", ["appletv", "apple"]),
        Entry("Paramount+", .provider, "531", ["paramount"]),
        Entry("WOW", .provider, "30|29", ["skywow", "wowtv", "sky", "skygo"]),           // unsure: 29 = Sky Go
        Entry("MagentaTV", .provider, "178", ["magenta", "telekom"]),                     // unsure
        Entry("RTL+", .provider, "298", ["rtl", "tvnow"]),
        Entry("Joyn", .provider, "304|421", ["joynplus"]),                                // unsure: 421 = Joyn PLUS+
        Entry("Crunchyroll", .provider, "283", seriesFirst: true),
        Entry("MUBI", .provider, "11"),
        Entry("Shudder", .provider, "99"),
        Entry("AMC+", .provider, "526", ["amcplus"]),                                     // unsure
        Entry("BritBox", .provider, "151"),                                               // unsure
        Entry("STARZ", .provider, "43|194", ["starzplay", "lionsgateplus"]),              // unsure: 194 = STARZPLAY
        Entry("Hulu", .provider, "15"),
        Entry("Max", .provider, "1899|384", ["hbomax"]),
        Entry("Peacock", .provider, "386|387", ["peacocktv", "peacockpremium"]),
        Entry("discovery+", .provider, "510", ["discovery"]),                             // unsure: 510 or 520
    ]

    /// TMDB company IDs (`with_companies`, films and series).
    public static let companies: [Entry] = [
        Entry("Pixar", .company, "3", ["pixaranimationstudios", "disneypixar"]),
        Entry("Walt Disney Pictures", .company, "2", ["disney", "waltdisney", "disneypictures"]),
        Entry("Walt Disney Animation Studios", .company, "6125", ["disneyanimation"]),      // unsure
        Entry("Marvel Studios", .company, "420", ["marvel"]),
        Entry("Lucasfilm", .company, "1", ["lucasfilmltd"]),
        Entry("Warner Bros. Pictures", .company, "174", ["warnerbros", "warner", "warnerbrothers", "wb"]),
        Entry("Universal Pictures", .company, "33", ["universal", "universalstudios"]),
        Entry("Paramount Pictures", .company, "4", ["paramount"]),
        Entry("Columbia Pictures", .company, "5", ["columbia"]),
        Entry("20th Century Studios", .company, "25|127928", ["20thcenturyfox", "20thcentury", "twentiethcenturyfox", "fox"]),
        Entry("A24", .company, "41077"),
        Entry("DreamWorks Animation", .company, "521", ["dreamworks"]),
        Entry("Illumination", .company, "6704", ["illuminationentertainment"]),
        Entry("Studio Ghibli", .company, "10342", ["ghibli"]),
        Entry("Blumhouse", .company, "3172", ["blumhouseproductions"]),
        Entry("Legendary", .company, "923", ["legendarypictures", "legendaryentertainment"]),
        Entry("Lionsgate", .company, "1632", ["lionsgatefilms", "lionsgate films"]),          // unsure (35 = Lions Gate Films)
        Entry("MGM", .company, "21|8411", ["metrogoldwynmayer"]),
        Entry("Miramax", .company, "14"),
        Entry("Touchstone Pictures", .company, "9195", ["touchstone"]),
        Entry("New Line Cinema", .company, "12", ["newline"]),
        Entry("Focus Features", .company, "10146", ["focus"]),
        Entry("Searchlight Pictures", .company, "43|127929", ["searchlight", "foxsearchlight", "foxsearchlightpictures"]),
        Entry("Neon", .company, "90733"),
        Entry("Amblin Entertainment", .company, "56", ["amblin"]),                         // unsure
        Entry("Constantin Film", .company, "47", ["constantin"]),                          // unsure
    ]

    /// TMDB network IDs (`with_networks`, series only; another ID space than companies).
    public static let networks: [Entry] = [
        Entry("HBO", .network, "49"),
        Entry("Showtime", .network, "67"),
        Entry("FX", .network, "88", ["fxnetworks"]),
        Entry("AMC", .network, "174"),
        Entry("Adult Swim", .network, "80"),
        Entry("Cartoon Network", .network, "56"),
        Entry("Nickelodeon", .network, "13", ["nick"]),
        Entry("Comedy Central", .network, "47"),
        Entry("Syfy", .network, "77"),
        Entry("BBC One", .network, "4", ["bbc"]),                                          // unsure
    ]

    /// Entry for a normalised title; the row kind sets which table is asked first.
    public static func entry(normalizedName n: String, row: RowKind) -> Entry? {
        guard !n.isEmpty else { return nil }
        let order: [[Entry]] = row == .streaming ? [providers, networks, companies] : [companies, networks, providers]
        // The own name of any table beats an alias („Paramount+“ in a studio row stays the service).
        for t in order { if let e = t.first(where: { $0.names.first == n }) { return e } }
        for t in order { if let e = t.first(where: { $0.names.contains(n) }) { return e } }
        return nil
    }

    // MARK: Rule

    /// Row kind of a collection by its title (German and English), nil for every other row. Genre rows never count.
    public static func rowKind(collectionID id: String, title: String) -> RowKind? {
        if id == "pkg.streaming-de" { return .streaming }
        if GenrePageRule.isGenreCollection(id: id, title: title) || id.hasPrefix("pkg.") { return nil }
        let words = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
        // Build 8 review: service / provider / studio wording only. „Streaming“ as a word part is not enough („Neu im
        // Streaming“, „Streaming-Charts“ are title lists); a row titled only „Streaming“ still counts.
        if words == ["streaming"] { return .streaming }
        let streaming: Set = ["dienste", "anbieter", "provider", "providers", "service", "services", "plattformen", "mediatheken"]
        if words.contains(where: { streaming.contains($0) || $0.hasSuffix("dienste") || $0.hasSuffix("anbieter") }) {
            return .streaming
        }
        let studios: Set = ["studios", "networks", "sender", "companies", "produktionsfirmen"]
        if words.contains(where: { studios.contains($0) || $0.hasSuffix("studios") }) { return .studios }
        return nil
    }

    /// Page of `folder`. `collection` looks up a collection by ID (as `GenrePageRule`); `searched` answers a cached
    /// company search by key (nil = not searched yet). Build 8 review: `tmdb` false (no TMDB key): only the addon
    /// grid or the row page (a TMDB grid would only say „TMDB-Key fehlt“); the package keeps its grid.
    public static func resolve(_ folder: Folder, collection: (String) -> MediaCollection?,
                               searched: (String) -> CompanySearchCache.Lookup?, tmdb: Bool = true) -> Resolution {
        if folder.id.hasPrefix(streamingPackagePrefix) { return packageGrid(folder) }
        guard let row = rowKind(of: folder, collection: collection) else { return .rowPage }
        let label = row == .streaming ? "Dienst" : "Studio"
        guard tmdb else { return addonGrid(folder, label: label, addonOnly: true) }
        let name = ReadyPackages.normalizedArtName(folder.title)
        if let e = entry(normalizedName: name, row: row) { return .grid(grid(e, folder: folder)) }
        // The folder's own TMDB lists already name the service or studio.
        if let own = GenrePageSources.of(folder), !own.hasAddon {
            return .grid(Grid(label: label, origin: .folder, sources: own, initial: GenreFilter.initial(available: own.available),
                              regionFallback: [:], header: plainHeader(folder)))
        }
        // Build 8 review: the company search only for studio rows (a service is no production company).
        let key = CompanySearchCache.searchKey(folder.title)
        if row == .studios, !name.isEmpty {
            switch searched(key) {
            case nil: return .search(query: folder.title.trimmingCharacters(in: .whitespacesAndNewlines), key: key)
            case .found(let studio)?:
                var header = plainHeader(folder)
                if header.logo == nil { header.logo = studio.logo }
                if header.logo == nil { header.tmdbLogo = studio }
                let ids = studio.id.map(String.init) ?? ""
                if !ids.isEmpty {
                    return .grid(Grid(label: label, origin: .search, sources: companySources(ids, title: folder.title),
                                      initial: .movies, regionFallback: [:], header: header))
                }
            case .miss?: break
            }
        }
        return addonGrid(folder, label: label)
    }

    /// After a search (hit, miss or failure): the same as `resolve` with that answer; a failed search counts as miss.
    public static func afterSearch(_ folder: Folder, collection: (String) -> MediaCollection?,
                                   answer: CompanySearchCache.Lookup) -> Resolution {
        let r = resolve(folder, collection: collection, searched: { _ in answer })
        if case .search = r { return .rowPage }
        return r
    }

    /// The fallback when a search could not run: the addon grid, else the row page.
    public static func withoutSearch(_ folder: Folder, collection: (String) -> MediaCollection?) -> Resolution {
        afterSearch(folder, collection: collection, answer: .miss)
    }

    static func rowKind(of folder: Folder, collection: (String) -> MediaCollection?) -> RowKind? {
        for c in GenrePageRule.parentCandidates(ofFolderID: folder.id) {
            guard let parent = collection(c), parent.folders.contains(where: { $0.id == folder.id }) else { continue }
            return rowKind(collectionID: parent.id, title: parent.title)
        }
        return nil
    }

    static func plainHeader(_ folder: Folder) -> Header {
        Header(logo: nonEmpty(folder.logo), tmdbLogo: nil, tile: nonEmpty(folder.coverImage))
    }

    static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }

    static func packageGrid(_ folder: Folder) -> Resolution {
        let m = folder.sources.first { $0.id.hasSuffix(".popular-movies") }
        let s = folder.sources.first { $0.id.hasSuffix(".popular-series") }
        guard m != nil || s != nil else { return .rowPage }
        let src = GenrePageSources(movies: m, series: s)
        return .grid(Grid(label: "Dienst", origin: .tmdbProvider, sources: src, initial: GenreFilter.initial(available: src.available),
                          regionFallback: [:], header: plainHeader(folder)))
    }

    static func addonGrid(_ folder: Folder, label: String, addonOnly: Bool = false) -> Resolution {
        guard let own = GenrePageSources.of(folder), !addonOnly || own.hasAddon else { return .rowPage }
        return .grid(Grid(label: label, origin: own.hasAddon ? .addon : .folder, sources: own,
                          initial: GenreFilter.initial(available: own.available), regionFallback: [:], header: plainHeader(folder)))
    }

    static func grid(_ e: Entry, folder: Folder) -> Grid {
        let label = e.kind == .provider ? "Dienst" : "Studio"
        var header = plainHeader(folder)
        switch e.kind {
        case .provider:
            let de = providerSources(e.ids, title: folder.title, region: region)
            let us = providerSources(e.ids, title: folder.title, region: fallbackRegion)
            var fb: [String: CatalogSource] = [:]
            if let a = de.movies, let b = us.movies { fb[a.id] = b }
            if let a = de.series, let b = us.series { fb[a.id] = b }
            return Grid(label: label, origin: .tmdbProvider, sources: de, initial: e.seriesFirst ? .series : .movies,
                        regionFallback: fb, header: header)
        case .company:
            if header.logo == nil { header.tmdbLogo = e.firstID.map { StudioLogo(name: e.name, logo: nil, id: $0, kind: .company) } }
            return Grid(label: label, origin: .tmdbCompany, sources: companySources(e.ids, title: folder.title),
                        initial: e.seriesFirst ? .series : .movies, regionFallback: [:], header: header)
        case .network:
            if header.logo == nil { header.tmdbLogo = e.firstID.map { StudioLogo(name: e.name, logo: nil, id: $0, kind: .network) } }
            let f = ["with_networks": e.ids, "sort_by": sortBy]
            let series = CatalogSource(id: "brand.network.\(idPart(e.ids)).series", title: folder.title,
                                       kind: .tmdbDiscover(filters: f), mediaType: .series)
            return Grid(label: label, origin: .tmdbNetwork, sources: GenrePageSources(movies: nil, series: series),
                        initial: .series, regionFallback: [:], header: header)
        }
    }

    /// Film and series list of a watch provider in `region` (popularity, subscription / free).
    public static func providerSources(_ ids: String, title: String, region r: String) -> GenrePageSources {
        let f = ["with_watch_providers": ids, "watch_region": r, "with_watch_monetization_types": monetization, "sort_by": sortBy]
        let base = "brand.provider.\(idPart(ids))" + (r == region ? "" : ".\(r.lowercased())")
        return GenrePageSources(
            movies: CatalogSource(id: base + ".movies", title: title, kind: .tmdbDiscover(filters: f), mediaType: .movie),
            series: CatalogSource(id: base + ".series", title: title, kind: .tmdbDiscover(filters: f), mediaType: .series))
    }

    /// Film and series list of a company (the same ID on both discover endpoints).
    public static func companySources(_ ids: String, title: String) -> GenrePageSources {
        let f = ["with_companies": ids, "sort_by": sortBy]
        let base = "brand.company.\(idPart(ids))"
        return GenrePageSources(
            movies: CatalogSource(id: base + ".movies", title: title, kind: .tmdbDiscover(filters: f), mediaType: .movie),
            series: CatalogSource(id: base + ".series", title: title, kind: .tmdbDiscover(filters: f), mediaType: .series))
    }

    /// `9|119` → `9-119` (source IDs and cache keys keep no `|`).
    static func idPart(_ ids: String) -> String { ids.replacingOccurrences(of: "|", with: "-") }

    // MARK: Paging and log

    /// Build 8: rows before the end at which the brand and genre grid asks for the next block. A TMDB page is about
    /// three grid rows, so the next page is requested while more than a page is still below the focus: holding the
    /// remote down never reaches the end before it is there.
    public static let prefetchRows = 4

    /// Sources to warm when the tile rests in focus: the start filter first.
    public static func warmSources(_ g: Grid) -> [CatalogSource] {
        let first = g.sources.source(for: g.initial)
        let other = g.sources.source(for: g.initial == .movies ? .series : .movies)
        return [first, other].compactMap { $0 }
    }

    /// „Dienst: Netflix geöffnet, Quelle tmdb-provider, Filter Filme (Filme/Serien)“.
    public static func openLine(_ g: Grid, title: String, filter: GenreFilter) -> String {
        "\(g.label): \(title) geöffnet, Quelle \(g.origin.rawValue), Filter \(filter.title) (\(g.sources.available.map(\.title).joined(separator: "/")))"
    }

    /// „Dienst: Netflix erste Seite Filme: 20 Titel in 312 ms (seit Öffnen 340 ms)“.
    public static func firstPageLine(label: String, title: String, filter: GenreFilter, count: Int,
                                     fetchMs: Int, sinceOpenMs: Int?) -> String {
        var s = "\(label): \(title) erste Seite \(filter.title): \(count) Titel in \(fetchMs) ms"
        if let sinceOpenMs { s += " (seit Öffnen \(sinceOpenMs) ms)" }
        return s
    }

    /// „Dienst: Hulu Filme: in DE nichts, Region US“.
    public static func regionLine(label: String, title: String, filter: GenreFilter) -> String {
        "\(label): \(title) \(filter.title): in \(region) nichts, Region \(fallbackRegion)"
    }
}

extension GenrePageSources {
    var hasAddon: Bool {
        [movies, series].contains { s in
            if case .addon? = s?.kind { return true }
            return false
        }
    }

    /// Filter of a source of this pair (nil when it is neither).
    public func filter(ofSourceID id: String) -> GenreFilter? {
        if movies?.id == id { return .movies }
        if series?.id == id { return .series }
        return nil
    }
}

// MARK: Company search

/// Build 8: answers of TMDB `/search/company` by title, kept on disk (a found company 90 days, „nothing“ 3 days),
/// and the TMDB logos of table companies / networks (same entries, key `logo:<kind>:<id>`).
public struct CompanySearchCache: Codable, Sendable, Equatable {
    public enum Lookup: Sendable, Equatable {
        case found(StudioLogo)
        case miss
    }

    public struct Entry: Codable, Sendable, Equatable {
        public var id: Int?
        public var name: String?
        public var logo: String?
        public var at: Date
    }

    public static let fileName = "studio-suche.json"
    public static let hitDays: TimeInterval = 90
    public static let missDays: TimeInterval = 3
    public static let maxEntries = 400

    public private(set) var entries: [String: Entry] = [:]

    public init() {}

    public static func searchKey(_ title: String) -> String { "suche:" + ReadyPackages.normalizedArtName(title) }
    public static func logoKey(_ s: StudioLogo) -> String? { s.id.map { "logo:\(s.kind.rawValue):\($0)" } }

    public func lookup(_ key: String, now: Date = Date()) -> Lookup? {
        guard let e = entries[key] else { return nil }
        let days = (e.id == nil && e.logo == nil) ? Self.missDays : Self.hitDays
        guard now.timeIntervalSince(e.at) < days * 86400 else { return nil }
        guard e.id != nil || e.logo != nil else { return .miss }
        return .found(StudioLogo(name: e.name ?? "", logo: e.logo, id: e.id, kind: .company))
    }

    public mutating func store(_ key: String, _ found: StudioLogo?, now: Date = Date()) {
        entries[key] = Entry(id: found?.id, name: found?.name, logo: found?.logo, at: now)
        if entries.count > Self.maxEntries {
            let drop = entries.sorted { $0.value.at < $1.value.at }.prefix(entries.count - Self.maxEntries).map(\.key)
            for k in drop { entries[k] = nil }
        }
    }

    public static func decode(_ data: Data?) -> CompanySearchCache {
        guard let data, let c = try? JSONDecoder().decode(CompanySearchCache.self, from: data) else { return CompanySearchCache() }
        return c
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    /// One company of a `/search/company` answer with its `origin_country` (nil when missing or empty).
    public struct Result: Sendable, Equatable {
        public let studio: StudioLogo
        public let country: String?
    }

    /// Countries whose companies most titles of the app's catalogs come from (tie break of equal names).
    public static let preferredCountries: Set<String> = ["US", "GB", "DE"]

    /// The company of a search answer whose folded name equals the title; nil when no name matches exactly.
    /// Build 8 review: several companies often share a name (small namesakes in other countries). Of those, the one
    /// with a logo wins (TMDB curates logos for the known ones), then one from the US, GB or DE, then TMDB's order
    /// (its search ranks by popularity). The title count per company would need one request each, so it is not used.
    public static func exactMatch(_ results: [Result], title: String) -> StudioLogo? {
        let n = ReadyPackages.normalizedArtName(title)
        guard !n.isEmpty else { return nil }
        let same = results.enumerated().filter { $0.element.studio.id != nil && ReadyPackages.normalizedArtName($0.element.studio.name) == n }
        func score(_ r: Result) -> Int {
            (r.studio.logo != nil ? 2 : 0) + (r.country.map { preferredCountries.contains($0) } == true ? 1 : 0)
        }
        let best = same.min { a, b in
            let sa = score(a.element), sb = score(b.element)
            return sa != sb ? sa > sb : a.offset < b.offset
        }
        return best?.element.studio
    }

    /// Companies of a `/search/company` answer.
    public static func parse(_ data: Data) -> [Result] {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let arr = o["results"] as? [[String: Any]] else { return [] }
        return arr.compactMap { r in
            guard let id = r["id"] as? Int, let name = r["name"] as? String else { return nil }
            let path = (r["logo_path"] as? String).flatMap { $0.hasPrefix("/") && !$0.lowercased().hasSuffix(".svg") ? $0 : nil }
            let country = (r["origin_country"] as? String).flatMap { $0.isEmpty ? nil : $0.uppercased() }
            return Result(studio: StudioLogo(name: name, logo: path.map { TMDBClient.studioLogoBase + $0 }, id: id, kind: .company),
                          country: country)
        }
    }
}

extension TMDBClient {
    /// Build 8: TMDB `/search/company` (first page).
    public func searchCompany(_ query: String) async throws -> [CompanySearchCache.Result] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return CompanySearchCache.parse(try await http.data(from: url("/search/company", ["query": q, "page": "1"])))
    }
}

/// Build 8: grid posters decode at most at this screen scale. Device test b7: a studio grid held 65 posters at
/// 174 MB on a 4K TV (scale 2, up to 736×1024 px each) against the 160 MB image budget; at 1.5 a poster cell decodes
/// one size step lower (about half the bytes). 1080p TVs (scale 1) are unchanged.
public enum GridImageScale {
    public static let cap: CGFloat = 1.5

    public static func scale(displayScale: CGFloat) -> CGFloat { min(displayScale, cap) }
}
