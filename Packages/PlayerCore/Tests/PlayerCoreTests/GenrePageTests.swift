import Testing
import Foundation
@testable import PlayerCore

// Wave G2: genre page (filter Filme/Serien, endless grid: next block, dedup, end, error/retry, prefetch threshold).

private func m(_ id: Int) -> MetaPreview { MetaPreview(id: "tmdb:\(id)", type: "movie", name: "T\(id)") }
private func ms(_ r: ClosedRange<Int>) -> [MetaPreview] { r.map(m) }

private func discover(_ id: String, _ t: MediaType) -> CatalogSource {
    CatalogSource(id: id, title: id, kind: .tmdbDiscover(filters: ["with_genres": "28"]), mediaType: t)
}

@Test func genreFilterDefaultsToFilme() {
    #expect(GenreFilter.initial(available: [.movies, .series]) == .movies)
    #expect(GenreFilter.initial(available: [.series, .movies]) == .movies)
    #expect(GenreFilter.initial(available: [.series]) == .series)
    #expect(GenreFilter.initial(available: []) == .movies)
    #expect(GenreFilter.movies.title == "Filme" && GenreFilter.series.title == "Serien")
}

@Test func genreSourcesFromPackageFolders() throws {
    // Every genre package folder becomes a genre page; Horror/Thriller have films only.
    for f in ReadyPackages.genreCollection.folders {
        let s = try #require(GenrePageSources.of(f))
        #expect(s.movies != nil)
        #expect(s.available.first == .movies)
    }
    let horror = try #require(ReadyPackages.genreCollection.folders.first { $0.title == "Horror" })
    #expect(GenrePageSources.of(horror)?.available == [.movies])
    // Streaming folders (four lists) keep the row page.
    for f in ReadyPackages.streamingDE.folders { #expect(GenrePageSources.of(f) == nil) }
}

@Test func genreSourcesShapeRules() {
    let addonMovie = CatalogSource(id: "a", title: "a", kind: .addon(addonId: "x", catalogId: "c", type: "movie"), mediaType: .both)
    let addonSeries = CatalogSource(id: "b", title: "b", kind: .addon(addonId: "x", catalogId: "c", type: "series"), mediaType: .both)
    let s = GenrePageSources.of(Folder(id: "f", title: "F", sources: [addonSeries, addonMovie]))
    #expect(s?.movies?.id == "a" && s?.series?.id == "b")
    // Two film lists, a Trakt list, a mixed list or no list: no genre page.
    #expect(GenrePageSources.of(Folder(id: "f", title: "F", sources: [discover("1", .movie), discover("2", .movie)])) == nil)
    let trakt = CatalogSource(id: "t", title: "t", kind: .trakt(user: "u", list: "l"), mediaType: .movie)
    #expect(GenrePageSources.of(Folder(id: "f", title: "F", sources: [trakt])) == nil)
    #expect(GenrePageSources.of(Folder(id: "f", title: "F", sources: [discover("1", .both)])) == nil)
    let anime = CatalogSource(id: "n", title: "n", kind: .addon(addonId: "x", catalogId: "c", type: "anime"), mediaType: .both)
    #expect(GenrePageSources.of(Folder(id: "f", title: "F", sources: [anime])) == nil)
    #expect(GenrePageSources.of(Folder(id: "f", title: "F", sources: [])) == nil)
}

@Test func tmdbPagingNextPageAndDedup() {
    var p = GenrePaging(source: discover("1", .movie))
    #expect(p.phase == .loadingFirst)
    let r1 = p.beginNext()
    #expect(r1 == .tmdbPage(1))
    #expect(p.beginNext() == nil)   // one block at a time
    #expect(p.receive(.tmdbPage(1), items: ms(1...20), totalPages: 10) == 20)
    #expect(p.phase == .items && p.footer == .none)
    #expect(p.beginNext() == .tmdbPage(2))
    #expect(p.footer == .loading)
    // Page 2 repeats 5 titles of page 1 (order shifted): only 15 new.
    #expect(p.receive(.tmdbPage(2), items: ms(16...35), totalPages: 10) == 15)
    #expect(p.items.count == 35)
    #expect(Set(p.items.map(\.id)).count == 35)
    #expect(p.logLine(genre: "Action", filter: .movies, added: 15) == "Genre: Action Filme Seite 2, +15 Titel (gesamt 35)")
    // A TMDB page of only duplicates does not end the source.
    _ = p.beginNext()
    #expect(p.receive(.tmdbPage(3), items: ms(1...20), totalPages: 10) == 0)
    #expect(!p.reachedEnd)
    #expect(p.beginNext() == .tmdbPage(4))
}

@Test func tmdbPagingEnd() {
    var p = GenrePaging(style: .tmdb)
    _ = p.beginNext(); p.receive(.tmdbPage(1), items: ms(1...20), totalPages: 2)
    _ = p.beginNext(); p.receive(.tmdbPage(2), items: ms(21...27), totalPages: 2)
    #expect(p.reachedEnd)
    #expect(p.beginNext() == nil)
    #expect(p.logLine(genre: "Krimi", filter: .series, added: 7) == "Genre: Krimi Serien Seite 2, +7 Titel (gesamt 27), Ende")
    // Empty page ends too (total_pages missing).
    var q = GenrePaging(style: .tmdb)
    _ = q.beginNext(); q.receive(.tmdbPage(1), items: ms(1...20))
    _ = q.beginNext(); q.receive(.tmdbPage(2), items: [])
    #expect(q.reachedEnd)
    // Nothing at all: empty phase.
    var e = GenrePaging(style: .tmdb)
    _ = e.beginNext(); e.receive(.tmdbPage(1), items: [], totalPages: 0)
    #expect(e.phase == .empty)
    // TMDB stops at page 500.
    var big = GenrePaging(style: .tmdb)
    for i in 1...GenrePaging.tmdbMaxPage {
        #expect(big.beginNext() == .tmdbPage(i))
        big.receive(.tmdbPage(i), items: [m(i)], totalPages: 9999)
    }
    #expect(big.reachedEnd && big.beginNext() == nil)
}

@Test func addonPagingSkipAndRepeatEnds() {
    let src = CatalogSource(id: "a", title: "a", kind: .addon(addonId: "x", catalogId: "c", type: "movie"), mediaType: .movie)
    var p = GenrePaging(source: src)
    #expect(p.beginNext() == .addonSkip(0))
    p.receive(.addonSkip(0), items: ms(1...100))
    #expect(p.beginNext() == .addonSkip(100))
    // Overlap: skip counts raw entries, dedup drops the overlap.
    #expect(p.receive(.addonSkip(100), items: ms(95...150)) == 50)
    #expect(p.beginNext() == .addonSkip(156))
    // An addon that ignores skip returns its first page again: one such block alone does not end (order may
    // shift), the second in a row does.
    #expect(p.receive(.addonSkip(156), items: ms(1...100)) == 0)
    #expect(!p.reachedEnd)
    #expect(p.beginNext() == .addonSkip(256))
    #expect(p.receive(.addonSkip(256), items: ms(1...100)) == 0)
    #expect(p.reachedEnd && p.beginNext() == nil)
    #expect(p.items.count == 150)
    // A new title in between resets the streak.
    var q = GenrePaging(style: .addon)
    _ = q.beginNext(); q.receive(.addonSkip(0), items: ms(1...10))
    _ = q.beginNext(); q.receive(.addonSkip(10), items: ms(1...10))
    _ = q.beginNext(); q.receive(.addonSkip(20), items: ms(11...20))
    #expect(q.duplicateStreak == 0 && !q.reachedEnd)
}

@Test func pagingErrorAndRetry() {
    var p = GenrePaging(style: .tmdb)
    _ = p.beginNext()
    p.fail(.tmdbPage(1))
    #expect(p.phase == .failedFirst)
    #expect(p.beginNext() == nil)   // needs retry
    #expect(p.retry() == .tmdbPage(1))
    p.receive(.tmdbPage(1), items: ms(1...20), totalPages: 5)
    _ = p.beginNext()
    p.fail(.tmdbPage(2))
    // Later block failed: the titles stay, retry row at the end.
    #expect(p.phase == .items && p.items.count == 20 && p.footer == .retry)
    #expect(!p.shouldPrefetch(focusedIndex: 19, columns: 6))
    #expect(p.failLine(genre: "Drama", filter: .movies, request: .tmdbPage(2), error: "Zeitüberschreitung")
            == "Genre: Drama Filme Seite 2 fehlgeschlagen: Zeitüberschreitung")
    #expect(p.retry() == .tmdbPage(2))
    #expect(p.footer == .loading)
    #expect(p.retry() == nil)
    p.receive(.tmdbPage(2), items: ms(21...40), totalPages: 5)
    #expect(p.items.count == 40 && p.footer == .none)
}

@Test func pagingIgnoresStaleAnswers() {
    var p = GenrePaging(style: .tmdb)
    _ = p.beginNext()
    #expect(p.receive(.tmdbPage(7), items: ms(1...20)) == 0)
    #expect(p.items.isEmpty && p.inFlight == .tmdbPage(1))
    p.fail(.tmdbPage(7))
    #expect(!p.failed)
}

@Test func prefetchThresholdTwoRowsBeforeEnd() {
    var p = GenrePaging(style: .tmdb)
    _ = p.beginNext(); p.receive(.tmdbPage(1), items: ms(1...40), totalPages: 10)
    // 40 titles, 6 columns: rows 0…6, last row 6. Threshold: from row 4 on.
    #expect(!p.shouldPrefetch(focusedIndex: 0, columns: 6))
    #expect(!p.shouldPrefetch(focusedIndex: 23, columns: 6))   // row 3
    #expect(p.shouldPrefetch(focusedIndex: 24, columns: 6))    // row 4
    #expect(p.shouldPrefetch(focusedIndex: 39, columns: 6))
    #expect(p.shouldPrefetch(focusedIndex: 0, columns: 0) == false)   // 1 column: 40 rows
    _ = p.beginNext()
    #expect(!p.shouldPrefetch(focusedIndex: 39, columns: 6))   // in flight
    // A short first page fills less than the screen: the first focus already asks for more.
    var s = GenrePaging(style: .tmdb)
    _ = s.beginNext(); s.receive(.tmdbPage(1), items: ms(1...8), totalPages: 3)
    #expect(s.shouldPrefetch(focusedIndex: 0, columns: 6))
}

@Test func gridColumnsFollowPosterSize() {
    let width: CGFloat = 1920 - 2 * 80
    for size in CardSize.allCases {
        let s = size.scale
        let w = PosterSize.tileSize(.poster, scale: s).width
        let n = GenreGrid.columns(width: width, tileWidth: w, spacing: PosterSize.spacing(scale: s))
        #expect(CGFloat(n) * w + CGFloat(n - 1) * PosterSize.spacing(scale: s) <= width)
        #expect(CGFloat(n + 1) * w + CGFloat(n) * PosterSize.spacing(scale: s) > width)
    }
    #expect(GenreGrid.columns(width: 1760, tileWidth: 240, spacing: 20) == 6)
    #expect(GenreGrid.columns(width: 100, tileWidth: 240, spacing: 20) == 1)
    #expect(GenreGrid.columns(width: 100, tileWidth: 0, spacing: 20) == 1)
}

@Test func tmdbPageReadsTotalPages() async throws {
    let c = TMDBClient(apiKey: "k", http: FakeHTTP(routes: [:]))
    let src = CatalogSource(id: "g", title: "g", kind: .tmdbDiscover(filters: ["with_genres": "18"]), mediaType: .series)
    let u = try c.url("/discover/tv", ["with_genres": "18", "page": "3"])
    let body = #"{"page":3,"total_pages":42,"results":[{"id":5,"name":"Serie"},{"id":6,"name":"Zwei"}]}"#
    let client = TMDBClient(apiKey: "k", http: FakeHTTP(routes: [u.absoluteString: body]))
    let r = try await client.page(for: src, page: 3)
    #expect(r.totalPages == 42)
    #expect(r.items.map(\.id) == ["tmdb:5", "tmdb:6"])
    #expect(r.items.first?.type == "series")
    await #expect(throws: TMDBError.unsupported) {
        _ = try await client.page(for: CatalogSource(id: "c", title: "c", kind: .tmdbCollection(id: "1"), mediaType: .movie), page: 1)
    }
}

@Test func tmdbDuplicateOnlyPagesStopAfterThree() {
    // A list answer that ignores `page` and has no total_pages: ends after 3 pages in a row without a new title.
    var p = GenrePaging(style: .tmdb)
    _ = p.beginNext(); p.receive(.tmdbPage(1), items: ms(1...20))
    for i in 2...3 {
        _ = p.beginNext(); p.receive(.tmdbPage(i), items: ms(1...20))
        #expect(!p.reachedEnd)
    }
    _ = p.beginNext(); p.receive(.tmdbPage(4), items: ms(1...20))
    #expect(p.reachedEnd && p.pagesLoaded == 4)
}

// Wave G2 R1 (review I-1): only genre folders open as a genre page.
private func kit(_ id: String, _ title: String, _ folders: [Folder]) -> MediaCollection {
    MediaCollection(id: id, title: title, folders: folders)
}
private func pair(_ fid: String) -> Folder {
    Folder(id: fid, title: fid, sources: [discover(fid + ".0", .movie), discover(fid + ".1", .series)])
}

@Test func genreRuleOnlyGenreFolders() throws {
    let none: (String) -> MediaCollection? = { _ in nil }
    // Genre package → page; streaming package (four lists, and also by rule) → old view.
    let action = try #require(ReadyPackages.genreCollection.folders.first)
    #expect(GenrePageRule.sources(for: action, collection: none) != nil)
    for f in ReadyPackages.streamingDE.folders {
        #expect(GenrePageRule.sources(for: f, collection: { $0 == "pkg.streaming-de" ? ReadyPackages.streamingDE : nil }) == nil)
    }
    // Kit collections with 1 film + 1 series list per tile.
    let genres = kit("fusion.widgets-genres.collection", "Genres", [pair("fusion.widgets-genres.collection.action.v2")])
    let movieGenres = kit("fusion.abc123.w1", "Film-Genres", [pair("fusion.abc123.w1.i0")])
    let streaming = kit("fusion.widgets-streaming.collection", "Streaming", [pair("fusion.widgets-streaming.collection.netflix")])
    let decades = kit("fusion.widgets-decades.collection", "Jahrzehnte", [pair("fusion.widgets-decades.collection.80s")])
    let directors = kit("fusion.widgets-directors.collection", "Regie", [pair("fusion.widgets-directors.collection.nolan")])
    let own = kit("own.1", "Meine Ordner", [pair("own.1.f")])
    let all = [genres, movieGenres, streaming, decades, directors, own]
    let lookup: (String) -> MediaCollection? = { id in all.first { $0.id == id } }
    #expect(GenrePageRule.sources(for: genres.folders[0], collection: lookup) != nil)
    #expect(GenrePageRule.sources(for: movieGenres.folders[0], collection: lookup) != nil)
    #expect(GenrePageRule.sources(for: streaming.folders[0], collection: lookup) == nil)
    #expect(GenrePageRule.sources(for: decades.folders[0], collection: lookup) == nil)
    #expect(GenrePageRule.sources(for: directors.folders[0], collection: lookup) == nil)
    #expect(GenrePageRule.sources(for: own.folders[0], collection: lookup) == nil)
    // Unknown parent: old view.
    #expect(GenrePageRule.sources(for: pair("x.y"), collection: none) == nil)
    // A genre collection tile that is not pageable keeps the old view too.
    let trakt = Folder(id: "fusion.widgets-genres.collection.t", title: "T",
                       sources: [CatalogSource(id: "t", title: "t", kind: .trakt(user: "u", list: "l"), mediaType: .movie)])
    let g2 = kit("fusion.widgets-genres.collection", "Genres", [trakt])
    #expect(GenrePageRule.sources(for: trakt, collection: { $0 == g2.id ? g2 : nil }) == nil)
}

@Test func genreRuleCollectionNames() {
    #expect(GenrePageRule.isGenreCollection(id: "pkg.genres", title: "Genres"))
    #expect(!GenrePageRule.isGenreCollection(id: "pkg.streaming-de", title: "Streaming-Dienste"))
    #expect(GenrePageRule.isGenreCollection(id: "fusion.k.collection", title: "Beliebte Genres"))
    #expect(GenrePageRule.isGenreCollection(id: "fusion.widgets-genres.collection", title: "Kacheln"))
    #expect(!GenrePageRule.isGenreCollection(id: "fusion.k.collection", title: "Preise"))
    #expect(GenrePageRule.parentCandidates(ofFolderID: "a.b.c.d") == ["a.b.c", "a.b", "a"])
    #expect(GenrePageRule.parentCandidates(ofFolderID: "plain").isEmpty)
}
