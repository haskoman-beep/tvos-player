import Foundation
import Testing
@testable import PlayerCore

// Build 8: studio and streaming tiles of the home screen open the studio grid.

private func addonFolder(_ id: String, _ title: String, cover: String? = "https://example.invalid/t.jpg") -> Folder {
    Folder(id: id, title: title, coverImage: cover, sources: [
        CatalogSource(id: id + ".0", title: title, kind: .addon(addonId: "aio", catalogId: "x.\(title).movie", type: "movie"), mediaType: .movie),
        CatalogSource(id: id + ".1", title: title, kind: .addon(addonId: "aio", catalogId: "x.\(title).series", type: "series"), mediaType: .series),
    ])
}

private func lookup(_ cols: [MediaCollection]) -> (String) -> MediaCollection? {
    { id in cols.first { $0.id == id } }
}

private func grid(_ r: BrandPage.Resolution) -> BrandPage.Grid? {
    if case .grid(let g) = r { return g }
    return nil
}

private func noSearch(_ key: String) -> CompanySearchCache.Lookup? { nil }

@Test func brandRowKindByTitle() {
    #expect(BrandPage.rowKind(collectionID: "kit.a.studios", title: "Studios") == .studios)
    #expect(BrandPage.rowKind(collectionID: "kit.a.x", title: "Top-Studios") == .studios)
    #expect(BrandPage.rowKind(collectionID: "kit.a.x", title: "Networks") == .studios)
    #expect(BrandPage.rowKind(collectionID: "kit.a.x", title: "Streaming-Dienste") == .streaming)
    #expect(BrandPage.rowKind(collectionID: "kit.a.x", title: "Streaming Services") == .streaming)
    #expect(BrandPage.rowKind(collectionID: "kit.a.x", title: "Dienste") == .streaming)
    #expect(BrandPage.rowKind(collectionID: "kit.a.x", title: "Anbieter") == .streaming)
    #expect(BrandPage.rowKind(collectionID: "kit.a.x", title: "Streaminganbieter") == .streaming)
    #expect(BrandPage.rowKind(collectionID: "pkg.streaming-de", title: "Streaming-Dienste") == .streaming)
    // Genre rows, other packages and other rows stay out.
    #expect(BrandPage.rowKind(collectionID: "kit.a.x", title: "Streaming-Genres") == nil)
    #expect(BrandPage.rowKind(collectionID: "pkg.genres", title: "Genres") == nil)
    #expect(BrandPage.rowKind(collectionID: "kit.a.x", title: "Preise") == nil)
    #expect(BrandPage.rowKind(collectionID: "kit.a.x", title: "Regisseure") == nil)
}

@Test func brandTablesNormaliseAndPreferRowKind() {
    func n(_ s: String) -> String { ReadyPackages.normalizedArtName(s) }
    #expect(BrandPage.entry(normalizedName: n("Netflix"), row: .streaming)?.ids == "8")
    #expect(BrandPage.entry(normalizedName: n("Disney+"), row: .streaming)?.ids == "337")
    #expect(BrandPage.entry(normalizedName: n("Apple TV+"), row: .streaming)?.ids == "350")
    #expect(BrandPage.entry(normalizedName: n("Prime Video"), row: .streaming)?.ids == "9|119")
    #expect(BrandPage.entry(normalizedName: n("HBO Max"), row: .streaming)?.ids == "1899|384")
    // „Disney“ / „Paramount“: the service in a streaming row, the studio in a studio row.
    #expect(BrandPage.entry(normalizedName: n("Disney"), row: .streaming)?.kind == .provider)
    #expect(BrandPage.entry(normalizedName: n("Disney"), row: .studios)?.ids == "2")
    #expect(BrandPage.entry(normalizedName: n("Paramount"), row: .studios)?.ids == "4")
    #expect(BrandPage.entry(normalizedName: n("Paramount"), row: .streaming)?.ids == "531")
    // An own name beats an alias of the preferred table.
    #expect(BrandPage.entry(normalizedName: n("Paramount+"), row: .studios)?.ids == "531")
    #expect(BrandPage.entry(normalizedName: n("AMC+"), row: .studios)?.kind == .provider)
    #expect(BrandPage.entry(normalizedName: n("AMC"), row: .streaming)?.kind == .network)
    // Studios: punctuation, case and accents do not matter.
    #expect(BrandPage.entry(normalizedName: n("Warner Bros. Pictures"), row: .studios)?.ids == "174")
    #expect(BrandPage.entry(normalizedName: n("Metro-Goldwyn-Mayer"), row: .studios)?.ids == "21|8411")
    #expect(BrandPage.entry(normalizedName: n("PIXAR"), row: .studios)?.ids == "3")
    #expect(BrandPage.entry(normalizedName: n("Studio Ghibli"), row: .studios)?.ids == "10342")
    #expect(BrandPage.entry(normalizedName: n("HBO"), row: .studios)?.kind == .network)
    #expect(BrandPage.entry(normalizedName: n("Witt/Thomas Productions"), row: .studios) == nil)
    #expect(BrandPage.entry(normalizedName: "", row: .studios) == nil)
    // Every normalised name is unique within its table (a doubled alias would make the order matter).
    for t in [BrandPage.providers, BrandPage.companies, BrandPage.networks] {
        let all = t.flatMap(\.names)
        #expect(Set(all).count == all.count)
    }
}

@Test func streamingTileOpensProviderGridWithUSFallback() throws {
    let netflix = addonFolder("kit.f.streaming.netflix", "Netflix")
    let col = MediaCollection(id: "kit.f.streaming", title: "Streaming-Dienste", folders: [netflix])
    let g = try #require(grid(BrandPage.resolve(netflix, collection: lookup([col]), searched: noSearch)))
    #expect(g.label == "Dienst" && g.origin == .tmdbProvider && g.initial == .movies)
    let m = try #require(g.sources.movies), s = try #require(g.sources.series)
    guard case .tmdbDiscover(let f) = m.kind else { Issue.record("not discover"); return }
    #expect(f["with_watch_providers"] == "8" && f["watch_region"] == "DE" && f["sort_by"] == "popularity.desc")
    #expect(m.mediaType == .movie && s.mediaType == .series)
    #expect(m.id == "brand.provider.8.movies")
    // US variant of both lists, other IDs (own cache entries).
    let us = try #require(g.regionFallback[m.id])
    guard case .tmdbDiscover(let uf) = us.kind else { Issue.record("not discover"); return }
    #expect(uf["watch_region"] == "US" && uf["with_watch_providers"] == "8" && us.id != m.id)
    #expect(g.regionFallback[s.id]?.mediaType == .series)
    #expect(g.header.tile == "https://example.invalid/t.jpg" && g.header.logo == nil && g.header.tmdbLogo == nil)
    #expect(BrandPage.openLine(g, title: "Netflix", filter: g.initial)
            == "Dienst: Netflix geöffnet, Quelle tmdb-provider, Filter Filme (Filme/Serien)")
    #expect(BrandPage.warmSources(g).map(\.id) == ["brand.provider.8.movies", "brand.provider.8.series"])
    // Crunchyroll starts on Serien and warms the series list first.
    let cr = addonFolder("kit.f.streaming.cr", "Crunchyroll")
    let col2 = MediaCollection(id: "kit.f.streaming", title: "Streaming-Dienste", folders: [cr])
    let g2 = try #require(grid(BrandPage.resolve(cr, collection: lookup([col2]), searched: noSearch)))
    #expect(g2.initial == .series && BrandPage.warmSources(g2).first?.mediaType == .series)
}

@Test func studioTileOpensCompanyAndNetworkGrid() throws {
    let pixar = addonFolder("kit.f.studios.pixar", "Pixar")
    let hbo = addonFolder("kit.f.studios.hbo", "HBO", cover: nil)
    let col = MediaCollection(id: "kit.f.studios", title: "Studios", folders: [pixar, hbo])
    let g = try #require(grid(BrandPage.resolve(pixar, collection: lookup([col]), searched: noSearch)))
    #expect(g.label == "Studio" && g.origin == .tmdbCompany && g.initial == .movies && g.regionFallback.isEmpty)
    guard case .tmdbDiscover(let f)? = g.sources.series?.kind else { Issue.record("no series"); return }
    #expect(f["with_companies"] == "3")
    #expect(g.header.tmdbLogo == StudioLogo(name: "Pixar", logo: nil, id: 3, kind: .company))
    let h = try #require(grid(BrandPage.resolve(hbo, collection: lookup([col]), searched: noSearch)))
    #expect(h.origin == .tmdbNetwork && h.initial == .series && h.sources.available == [.series])
    guard case .tmdbDiscover(let nf)? = h.sources.series?.kind else { Issue.record("no series"); return }
    #expect(nf["with_networks"] == "49")
    #expect(h.header.tmdbLogo?.kind == .network && h.header.tile == nil)
    // A logo of the folder wins over the TMDB lookup.
    var withLogo = pixar; withLogo.logo = "https://example.invalid/l.png"
    let col2 = MediaCollection(id: "kit.f.studios", title: "Studios", folders: [withLogo])
    let g2 = try #require(grid(BrandPage.resolve(withLogo, collection: lookup([col2]), searched: noSearch)))
    #expect(g2.header.logo == "https://example.invalid/l.png" && g2.header.tmdbLogo == nil)
}

@Test func unknownStudioSearchesThenFallsBackToAddonGrid() throws {
    let xyz = addonFolder("kit.f.studios.xyz", "XYZ Films")
    let col = MediaCollection(id: "kit.f.studios", title: "Studios", folders: [xyz])
    let key = CompanySearchCache.searchKey("XYZ Films")
    #expect(key == "suche:xyzfilms")
    #expect(BrandPage.resolve(xyz, collection: lookup([col]), searched: noSearch) == .search(query: "XYZ Films", key: key))
    // Found: the company grid with the search logo.
    let hit = StudioLogo(name: "XYZ Films", logo: "https://example.invalid/x.png", id: 12345, kind: .company)
    let g = try #require(grid(BrandPage.afterSearch(xyz, collection: lookup([col]), answer: .found(hit))))
    #expect(g.origin == .search && g.header.logo == "https://example.invalid/x.png")
    guard case .tmdbDiscover(let f)? = g.sources.movies?.kind else { Issue.record("no movies"); return }
    #expect(f["with_companies"] == "12345")
    // Nothing found (or the search failed): the addon catalogs, paged by skip.
    let a = try #require(grid(BrandPage.afterSearch(xyz, collection: lookup([col]), answer: .miss)))
    #expect(a.origin == .addon && a.label == "Studio" && a.sources.movies?.id == "kit.f.studios.xyz.0")
    #expect(grid(BrandPage.withoutSearch(xyz, collection: lookup([col])))?.origin == .addon)
}

@Test func brandRuleKeepsOtherFolders() throws {
    // A Trakt list in a studio row without a table entry: no search hit, not pageable → row page.
    let trakt = Folder(id: "kit.f.studios.t", title: "Some List", sources: [
        CatalogSource(id: "t.0", title: "L", kind: .trakt(user: "u", list: "l"), mediaType: .both)])
    let col = MediaCollection(id: "kit.f.studios", title: "Studios", folders: [trakt])
    #expect(BrandPage.afterSearch(trakt, collection: lookup([col]), answer: .miss) == .rowPage)
    // A folder of another row (awards) never opens the grid, even with a known name.
    let a24 = addonFolder("kit.f.awards.a24", "A24")
    let awards = MediaCollection(id: "kit.f.awards", title: "Preise", folders: [a24])
    #expect(BrandPage.resolve(a24, collection: lookup([awards]), searched: noSearch) == .rowPage)
    // No parent found: none.
    #expect(BrandPage.resolve(a24, collection: { _ in nil }, searched: noSearch) == .rowPage)
    // Own TMDB lists in a studio row are used as they are, without a search.
    let own = Folder(id: "kit.f.studios.o", title: "Silver Screen Partners IV", sources: [
        CatalogSource(id: "o.m", title: "M", kind: .tmdbCompany(id: "999"), mediaType: .movie)])
    let col2 = MediaCollection(id: "kit.f.studios", title: "Studios", folders: [own])
    let g = try #require(grid(BrandPage.resolve(own, collection: lookup([col2]), searched: noSearch)))
    #expect(g.origin == .folder && g.sources.movies?.id == "o.m")
}

@Test func streamingPackageUsesItsPopularLists() throws {
    let netflix = try #require(ReadyPackages.streamingDE.folders.first { $0.title == "Netflix" })
    let g = try #require(grid(BrandPage.resolve(netflix, collection: { _ in nil }, searched: noSearch)))
    #expect(g.origin == .tmdbProvider && g.label == "Dienst")
    #expect(g.sources.movies?.id == "pkg.streaming-de.8.popular-movies")
    #expect(g.sources.series?.id == "pkg.streaming-de.8.popular-series")
}

@Test func companySearchCacheKeepsHitsAndMisses() throws {
    var c = CompanySearchCache()
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let hit = StudioLogo(name: "XYZ Films", logo: nil, id: 7, kind: .company)
    c.store("suche:xyzfilms", hit, now: t0)
    c.store("suche:nothing", nil, now: t0)
    #expect(c.lookup("suche:xyzfilms", now: t0)?.foundID == 7)
    #expect(c.lookup("suche:nothing", now: t0) == .miss)
    #expect(c.lookup("suche:other", now: t0) == nil)
    // A miss is asked again after 3 days, a hit after 90.
    #expect(c.lookup("suche:nothing", now: t0.addingTimeInterval(4 * 86400)) == nil)
    #expect(c.lookup("suche:xyzfilms", now: t0.addingTimeInterval(30 * 86400))?.foundID == 7)
    #expect(c.lookup("suche:xyzfilms", now: t0.addingTimeInterval(91 * 86400)) == nil)
    // Round trip on disk.
    let back = CompanySearchCache.decode(c.encoded())
    #expect(back == c)
    #expect(CompanySearchCache.decode(Data("nope".utf8)) == CompanySearchCache())
    // Bounded: the oldest entries go first.
    var big = CompanySearchCache()
    for i in 0..<(CompanySearchCache.maxEntries + 5) { big.store("k\(i)", nil, now: t0.addingTimeInterval(Double(i))) }
    #expect(big.entries.count == CompanySearchCache.maxEntries && big.entries["k0"] == nil && big.entries["k404"] != nil)
}

@Test func companySearchExactMatchOnly() async throws {
    let json = #"""
    {"results":[{"id":1,"name":"XYZ Films International","logo_path":"/a.png"},
                {"id":2,"name":"xyz films","logo_path":null},
                {"id":3,"name":"XYZ Films","logo_path":"/c.png"},
                {"id":4,"name":"XYZ","logo_path":"/d.svg"}]}
    """#
    let r = CompanySearchCache.parse(Data(json.utf8))
    #expect(r.map(\.id) == [1, 2, 3, 4])
    #expect(r[3].logo == nil)   // SVG does not decode
    // Exact folded name only; of two such, the one with a logo.
    #expect(CompanySearchCache.exactMatch(r, title: "XYZ Films")?.id == 3)
    #expect(CompanySearchCache.exactMatch(r, title: "XYZ Film") == nil)
    #expect(CompanySearchCache.exactMatch(r, title: "  ") == nil)
    // The request goes to /search/company.
    let probe = TMDBClient(apiKey: "k", language: "de-DE", http: FakeHTTP(routes: [:]))
    let u = try probe.url("/search/company", ["query": "XYZ Films", "page": "1"])
    let client = TMDBClient(apiKey: "k", language: "de-DE", http: FakeHTTP(routes: [u.absoluteString: json]))
    #expect(try await client.searchCompany(" XYZ Films ").count == 4)
    #expect(try await client.searchCompany("  ").isEmpty)
}

@Test func brandLogLinesAndGridScale() {
    #expect(BrandPage.firstPageLine(label: "Dienst", title: "Netflix", filter: .movies, count: 20, fetchMs: 312, sinceOpenMs: 340)
            == "Dienst: Netflix erste Seite Filme: 20 Titel in 312 ms (seit Öffnen 340 ms)")
    #expect(BrandPage.firstPageLine(label: "Studio", title: "Pixar", filter: .series, count: 0, fetchMs: 90, sinceOpenMs: nil)
            == "Studio: Pixar erste Seite Serien: 0 Titel in 90 ms")
    #expect(BrandPage.regionLine(label: "Dienst", title: "Hulu", filter: .movies) == "Dienst: Hulu Filme: in DE nichts, Region US")
    #expect(GridImageScale.scale(displayScale: 2) == 1.5)
    #expect(GridImageScale.scale(displayScale: 1) == 1)
    let src = GenrePageSources(movies: CatalogSource(id: "m", title: "", kind: .tmdbList(id: "1"), mediaType: .movie), series: nil)
    #expect(src.filter(ofSourceID: "m") == .movies && src.filter(ofSourceID: "x") == nil)
}

@Test func earlyPrefetchAsksMoreThanAPageAhead() {
    var p = GenrePaging(style: .tmdb)
    _ = p.beginNext(); p.receive(.tmdbPage(1), items: (1...30).map { MetaPreview(id: "m\($0)", type: "movie", name: "T\($0)") }, totalPages: 10)
    // 30 titles, 7 columns: rows 0…4. With 4 rows ahead the focus on the first row already asks for the next page.
    #expect(p.shouldPrefetch(focusedIndex: 0, columns: 7, rows: BrandPage.prefetchRows))
    #expect(!p.shouldPrefetch(focusedIndex: 0, columns: 7))   // the old threshold (2 rows) would not
}

private extension CompanySearchCache.Lookup {
    var foundID: Int? { if case .found(let s) = self { return s.id }; return nil }
}
