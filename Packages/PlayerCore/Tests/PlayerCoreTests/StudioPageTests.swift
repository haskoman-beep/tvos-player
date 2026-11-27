import Foundation
import Testing
@testable import PlayerCore

// Build 7: studio plates carry ID and kind (company / network), each studio once.
@Test func studiosCarryIDAndKindOnce() {
    let movie = #"""
    {"id":1,"title":"A","production_companies":[
      {"id":2,"name":"Pixar","logo_path":"/pixar.png"},{"id":2,"name":"Pixar","logo_path":"/pixar.png"},
      {"id":3,"name":"Disney","logo_path":null},{"id":4,"name":"Third"}]}
    """#
    let m = TMDBClient.parseLocalized(Data(movie.utf8), lang: "de", region: "DE", series: false)
    #expect(m?.studioLogos.map(\.name) == ["Pixar", "Disney", "Third"])
    #expect(m?.studioLogos.map(\.id) == [2, 3, 4])
    #expect(m?.studioLogos.allSatisfy { $0.kind == .company } == true)
    #expect(m?.studioLogos.first?.key == "company:2")
    let series = #"""
    {"id":9,"name":"S","networks":[{"id":49,"name":"HBO","logo_path":"/hbo.png"}],
     "production_companies":[{"id":49,"name":"HBO"},{"id":7,"name":"P1"},{"id":8,"name":"P2"},{"id":9,"name":"P3"}]}
    """#
    let s = TMDBClient.parseLocalized(Data(series.utf8), lang: "de", region: "DE", series: true)
    #expect(s?.studioLogos.map(\.name) == ["HBO", "P1", "P2"])
    #expect(s?.studioLogos.map(\.kind) == [.network, .company, .company])
    #expect(s?.studioLogos.first?.key == "network:49")
}

// A company page lists films and series by `with_companies`, a network page series by `with_networks`, by popularity.
@Test func studioPageQueries() {
    let pixar = StudioLogo(name: "Pixar", logo: "https://example.invalid/p.png", id: 3, kind: .company)
    let f = StudioPage.folder(for: pixar)
    #expect(f?.id == "studio.company.3")
    #expect(f?.title == "Pixar")
    #expect(f?.sources.map(\.mediaType) == [.movie, .series])
    #expect(f?.sources.first?.kind == .tmdbDiscover(filters: ["with_companies": "3", "sort_by": "popularity.desc"]))
    #expect(Set(f?.sources.map(\.id) ?? []).count == 2)
    let hbo = StudioLogo(name: "HBO", logo: nil, id: 49, kind: .network)
    let n = StudioPage.folder(for: hbo)
    #expect(n?.sources.map(\.mediaType) == [.series])
    #expect(n?.sources.first?.kind == .tmdbDiscover(filters: ["with_networks": "49", "sort_by": "popularity.desc"]))
    #expect(StudioPage.folder(for: StudioLogo(name: "X", logo: nil)) == nil)
}

// The studio folder opens as a genre page (Filme / Serien, endless grid); header logo and log word only there.
@Test func studioFolderIsAGenrePage() {
    let pixar = StudioLogo(name: "Pixar", logo: "https://example.invalid/p.png", id: 3, kind: .company)
    guard let f = StudioPage.folder(for: pixar) else { Issue.record("no folder"); return }
    let g = GenrePageRule.sources(for: f, collection: { _ in nil })
    #expect(g?.available == [.movies, .series])
    #expect(GenreFilter.initial(available: g?.available ?? []) == .movies)
    #expect(StudioPage.headerLogo(f) == "https://example.invalid/p.png")
    #expect(StudioPage.logLabel(f) == "Studio")
    let net = StudioPage.folder(for: StudioLogo(name: "HBO", logo: nil, id: 49, kind: .network))
    #expect(net.flatMap { GenrePageRule.sources(for: $0, collection: { _ in nil }) }?.available == [.series])
    #expect(net.flatMap(StudioPage.headerLogo) == nil)
    // A genre folder keeps its title header and log word, even with a logo.
    let genre = Folder(id: "pkg.genres.action", title: "Action", logo: "https://example.invalid/a.png", sources: [])
    #expect(StudioPage.headerLogo(genre) == nil)
    #expect(StudioPage.logLabel(genre) == "Genre")
    var p = GenrePaging(style: .tmdb)
    if let r = p.beginNext() { p.receive(r, items: [], totalPages: 1) }
    #expect(p.logLine(genre: "Pixar", filter: .movies, added: 0, label: "Studio").hasPrefix("Studio: Pixar Filme Seite 1"))
    #expect(p.logLine(genre: "Action", filter: .movies, added: 0).hasPrefix("Genre: Action"))
}

// The company / network discover goes to the TMDB endpoint with the page number (same client as the genre page).
@Test func studioPageRequestsDiscover() async throws {
    let f = StudioPage.folder(for: StudioLogo(name: "HBO", logo: nil, id: 49, kind: .network))!
    let src = f.sources[0]
    let client = TMDBClient(apiKey: "k", language: "de-DE", http: FakeHTTP(routes: [:]))
    let u = try client.url("/discover/tv", ["with_networks": "49", "sort_by": "popularity.desc", "page": "2"])
    let body = #"{"page":2,"total_pages":7,"results":[{"id":1399,"name":"GoT","poster_path":"/g.jpg"}]}"#
    let answering = TMDBClient(apiKey: "k", language: "de-DE", http: FakeHTTP(routes: [u.absoluteString: body]))
    let page = try await answering.page(for: src, page: 2)
    #expect(page.totalPages == 7)
    #expect(page.items.map(\.id) == ["tmdb:1399"])
    #expect(page.items.first?.type == "series")
}

// Missing logos: the best raster logo of the image list (SVG paths skipped), else none.
@Test func studioLogoFallbackPicksTheBestRasterLogo() {
    let json = #"""
    {"id":3,"logos":[
      {"file_path":"/vector.svg","file_type":".svg","vote_average":9,"width":500},
      {"file_path":"/low.png","file_type":".png","vote_average":5.2,"vote_count":2,"width":800},
      {"file_path":"/best.png","file_type":".svg","vote_average":5.4,"vote_count":1,"width":300},
      {"file_path":"/same.png","file_type":".png","vote_average":5.4,"vote_count":1,"width":200}]}
    """#
    #expect(StudioLogoFill.bestLogo(imagesJSON: Data(json.utf8)) == "https://image.tmdb.org/t/p/w300/best.png")
    #expect(StudioLogoFill.bestLogo(imagesJSON: Data(#"{"id":3,"logos":[]}"#.utf8)) == nil)
    #expect(StudioLogoFill.bestLogo(imagesJSON: Data(#"{"id":3,"logos":[{"file_path":"/x.svg"}]}"#.utf8)) == nil)
    #expect(StudioLogoFill.bestLogo(imagesJSON: Data("nope".utf8)) == nil)
}

@Test func studioLogoFillAndLogLine() async throws {
    let a = StudioLogo(name: "A", logo: "https://example.invalid/a.png", id: 1, kind: .company)
    let b = StudioLogo(name: "B", logo: nil, id: 2, kind: .company)
    let c = StudioLogo(name: "C", logo: nil, id: 2, kind: .network)
    let d = StudioLogo(name: "D", logo: nil)
    let list = [a, b, c, d]
    #expect(StudioLogoFill.lookups(list).map(\.name) == ["B", "C"])
    let filled = StudioLogoFill.apply(list, found: ["company:2": "https://example.invalid/b.png"])
    #expect(filled.map(\.logo) == ["https://example.invalid/a.png", "https://example.invalid/b.png", nil, nil])
    #expect(StudioLogoFill.logLine(filled) == "Studios 4, mit Logo 2, Text 2")
    // The image list of a network comes from /network/{id}/images.
    let probe = TMDBClient(apiKey: "k", language: "de-DE", http: FakeHTTP(routes: [:]))
    let u = try probe.url("/network/2/images")
    let client = TMDBClient(apiKey: "k", language: "de-DE",
                            http: FakeHTTP(routes: [u.absoluteString: #"{"logos":[{"file_path":"/n.png"}]}"#]))
    #expect(try await client.studioLogo(c) == "https://image.tmdb.org/t/p/w300/n.png")
    #expect(try await client.studioLogo(d) == nil)
}

// Review 2: a company that is the network too (folded name: „HBO“ / „hbo “) is one plate, the network wins; the row
// IDs are unique even for two plates without ID and the same name.
@Test func studiosDedupeAcrossKindsAndRowIDsAreUnique() {
    let series = #"""
    {"id":9,"name":"S","networks":[{"id":49,"name":"HBO","logo_path":"/hbo.png"}],
     "production_companies":[{"id":3268,"name":"hbo ","logo_path":"/c.png"},{"id":7,"name":"Pathé"},{"name":"PATHE"}]}
    """#
    let s = TMDBClient.parseLocalized(Data(series.utf8), lang: "de", region: "DE", series: true)
    #expect(s?.studioLogos.map(\.name) == ["HBO", "Pathé", "PATHE"])
    #expect(s?.studioLogos.first?.kind == .network)
    let noID = #"{"id":1,"title":"A","production_companies":[{"name":"X"},{"name":"x"},{"name":"Y"}]}"#
    let m = TMDBClient.parseLocalized(Data(noID.utf8), lang: "de", region: "DE", series: false)
    #expect(m?.studioLogos.map(\.name) == ["X", "Y"])
    let twins = [StudioLogo(name: "A", logo: nil), StudioLogo(name: "a", logo: nil),
                 StudioLogo(name: "B", logo: nil, id: 1), StudioLogo(name: "B", logo: nil, id: 1, kind: .network)]
    let ids = StudioLogoFill.rowIDs(twins)
    #expect(ids == ["name:a", "name:a#2", "company:1", "network:1"])
    #expect(Set(ids).count == ids.count)
}

// Review 1: opened from a series (or a network) the studio page opens on Serien; genre pages keep Filme.
@Test func studioPageOpensOnSeriesFromASeries() {
    let pixar = StudioLogo(name: "Pixar", logo: nil, id: 3, kind: .company)
    let fromSeries = StudioPage.folder(for: pixar, preferSeries: true)!
    let all: [GenreFilter] = [.movies, .series]
    #expect(StudioPage.initialFilter(fromSeries, available: all) == .series)
    #expect(GenrePageRule.sources(for: fromSeries, collection: { _ in nil })?.available == all)
    #expect(StudioPage.initialFilter(StudioPage.folder(for: pixar)!, available: all) == .movies)
    let hbo = StudioPage.folder(for: StudioLogo(name: "HBO", logo: nil, id: 49, kind: .network))!
    #expect(StudioPage.initialFilter(hbo, available: [.series]) == .series)
    let genre = Folder(id: "pkg.genres.action", title: "Action", sources: [
        CatalogSource(id: "s", title: "S", kind: .tmdbDiscover(filters: [:]), mediaType: .series)])
    #expect(StudioPage.initialFilter(genre, available: all) == nil)
}

// Review 3: only `studio.(company|network).<digits>` is a studio page; an imported „studio.x“ stays a folder.
@Test func studioPrefixIsReserved() {
    let src = CatalogSource(id: "s", title: "S", kind: .tmdbDiscover(filters: [:]), mediaType: .movie)
    for id in ["studio.x", "studio.company.", "studio.company.12a", "studio.label.3", "studio.company.3.extra", "studio."] {
        let f = Folder(id: id, title: "X", logo: "https://example.invalid/x.png", sources: [src])
        #expect(!StudioPage.isStudio(f), "\(id)")
        #expect(GenrePageRule.sources(for: f, collection: { _ in nil }) == nil, "\(id)")
        #expect(StudioPage.headerLogo(f) == nil)
    }
    #expect(StudioPage.isStudioID("studio.company.3"))
    #expect(StudioPage.isStudioID("studio.network.49"))
}
