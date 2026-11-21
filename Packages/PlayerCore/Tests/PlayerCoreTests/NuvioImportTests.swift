import Foundation
import Testing
@testable import PlayerCore

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Test func nuvioExportMergesDuplicates() throws {
    let r = try NuvioImport.parse(fixture("nuvio.json"))
    #expect(r.collections.count == 9)
    let streaming = try #require(r.collections.first { $0.title == "Streaming" })
    #expect(streaming.folders.count >= 22)
    for c in r.collections { for f in c.folders { #expect(Set(f.sources.map(\.id)).count == f.sources.count) } }
    #expect(r.pendingAddonSources.count > 0)
    let netflix = try #require(streaming.folders.first { $0.title == "Netflix" })
    let newMovies = try #require(netflix.sources.first { $0.title == "New Movies" })
    guard case .tmdbDiscover(let f) = newMovies.kind else { Issue.record("kein Discover"); return }
    #expect(f["with_watch_providers"] == "8|1796")
    #expect(f["watch_region"] == "DE")
    #expect(f["withWatchProviders"] == nil)
    #expect(f["sort_by"] == "primary_release_date.desc")
    #expect(newMovies.mediaType == .movie)
}

@Test func camelOnlyFiltersTranslated() {
    #expect(NuvioImport.tmdbKey(camel: "releaseDateGte", mediaType: .movie) == "primary_release_date.gte")
    #expect(NuvioImport.tmdbKey(camel: "releaseDateLte", mediaType: .series) == "first_air_date.lte")
    #expect(NuvioImport.tmdbKey(camel: "voteCountGte", mediaType: .movie) == "vote_count.gte")
    #expect(NuvioImport.tmdbKey(camel: "withOriginalLanguage", mediaType: .movie) == "with_original_language")
    #expect(NuvioImport.tmdbKey(camel: "sortBy", mediaType: .movie) == nil)
}

@Test func unknownFieldsIgnored() throws {
    let json = #"[{"title":"X","neu":1,"folders":[{"title":"F","sources":[{"provider":"foo"},{"id":"a","provider":"tmdb","tmdbSourceType":"LIST","tmdbId":5,"mediaType":"TV","extra":{"z":1}}]}]}]"#
    let r = try NuvioImport.parse(Data(json.utf8))
    #expect(r.skippedSources == 1)
    #expect(r.collections[0].folders[0].sources == [CatalogSource(id: "a", title: "?", kind: .tmdbList(id: "5"), mediaType: .series)])
}

@Test func yearFilterMapsPerMediaType() throws {
    let json = #"""
    [{"title":"C","folders":[{"title":"F","sources":[
      {"provider":"tmdb","tmdbSourceType":"DISCOVER","mediaType":"TV","title":"T","filters":{"year":2026,"primary_release_date.gte":"2026-01-01"}},
      {"provider":"tmdb","tmdbSourceType":"DISCOVER","mediaType":"MOVIE","title":"M","filters":{"year":2025}}]}]}]
    """#
    let s = try NuvioImport.parse(Data(json.utf8)).collections[0].folders[0].sources
    guard case .tmdbDiscover(let tv) = s[0].kind, case .tmdbDiscover(let mv) = s[1].kind else { Issue.record("kein Discover"); return }
    #expect(tv == ["first_air_date_year": "2026", "first_air_date.gte": "2026-01-01"])
    #expect(mv == ["primary_release_year": "2025"])
}

@Test func fixtureTVYearUsesFirstAirDateYear() throws {
    let r = try NuvioImport.parse(fixture("nuvio.json"))
    var tvYears = 0
    for c in r.collections { for f in c.folders { for s in f.sources where s.mediaType == .series {
        guard case .tmdbDiscover(let fl) = s.kind else { continue }
        #expect(fl["year"] == nil && fl["primary_release_year"] == nil)
        if fl["first_air_date_year"] != nil { tvYears += 1 }
    } } }
    #expect(tvYears > 0)
}

@Test func sourcesWithoutProviderAndLegacyCatalogSources() throws {
    let json = #"""
    [{"title":"C","folders":[{"title":"F",
      "sources":[{"addonId":"a.b","type":"series","catalogId":"top"}],
      "catalogSources":[{"addonId":"a.b","type":"movie","catalogId":"best","genre":null},{"addonId":"a.b","type":"series","catalogId":"top"}]}]}]
    """#
    let r = try NuvioImport.parse(Data(json.utf8))
    let s = r.collections[0].folders[0].sources
    #expect(s.map(\.id) == ["addon:a.b:series:top", "addon:a.b:movie:best"])
    #expect(s[1].kind == .addon(addonId: "a.b", catalogId: "best", type: "movie"))
    #expect(r.skippedSources == 0 && r.pendingAddonSources.count == 2)
}

@Test func reimportWithoutIDsDoesNotDuplicate() throws {
    let json = #"""
    [{"title":"C","folders":[{"title":"F","sources":[
      {"provider":"tmdb","tmdbSourceType":"DISCOVER","mediaType":"MOVIE","title":"D","filters":{"withGenres":"28","vote_count.gte":100}},
      {"provider":"tmdb","tmdbSourceType":"LIST","mediaType":"MOVIE","title":"L","tmdbId":7},
      {"provider":"trakt","traktListId":99,"mediaType":"MOVIE","title":"T"}]}]}]
    """#
    let a = try NuvioImport.parse(Data(json.utf8)), b = try NuvioImport.parse(Data(json.utf8))
    #expect(a.collections.map(\.id) == b.collections.map(\.id))
    #expect(a.collections[0].folders.map(\.id) == b.collections[0].folders.map(\.id))
    #expect(a.collections[0].folders[0].sources.map(\.id) == b.collections[0].folders[0].sources.map(\.id))
    #expect(!a.collections[0].id.contains("-"))   // keine UUID
    let merged = NuvioImport.mergeFolders(a.collections[0].folders, b.collections[0].folders)
    #expect(merged.count == 1 && merged[0].sources.count == 3)
}

@Test func addonGenreKeptAsDistinctSourceWithWarning() throws {
    let json = #"""
    [{"title":"C","folders":[{"title":"F","sources":[
      {"provider":"addon","addonId":"x","type":"movie","catalogId":"top","genre":"Action"},
      {"provider":"addon","addonId":"x","type":"movie","catalogId":"top","genre":"Drama"},
      {"provider":"addon","addonId":"x","type":"movie","catalogId":"top","genre":"None"}]}]}]
    """#
    let r = try NuvioImport.parse(Data(json.utf8))
    let s = r.collections[0].folders[0].sources
    #expect(s.map(\.id) == ["addon:x:movie:top:genre=Action", "addon:x:movie:top:genre=Drama", "addon:x:movie:top"])
    #expect(s[0].title == "top · Action")
    #expect(r.warnings["Addon-Genre ignoriert"] == 2)
}

@Test func networkMapsToDiscoverPersonDirectorSkippedWithWarning() throws {
    let json = #"""
    [{"title":"C","folders":[{"title":"F","sources":[
      {"provider":"tmdb","tmdbSourceType":"NETWORK","mediaType":"TV","title":"N","tmdbId":213,"sortBy":"primary_release_date.desc"},
      {"provider":"tmdb","tmdbSourceType":"PERSON","mediaType":"MOVIE","title":"P","tmdbId":1},
      {"provider":"tmdb","tmdbSourceType":"DIRECTOR","mediaType":"MOVIE","title":"D","tmdbId":2}]}]}]
    """#
    let r = try NuvioImport.parse(Data(json.utf8))
    let s = r.collections[0].folders[0].sources
    #expect(s.count == 1)
    #expect(s[0].kind == .tmdbDiscover(filters: ["with_networks": "213", "sort_by": "first_air_date.desc"]) && s[0].mediaType == .series)
    #expect(r.skippedSources == 2)
    #expect(r.warnings == ["tmdb PERSON übersprungen": 1, "tmdb DIRECTOR übersprungen": 1])
}

@Test func sortConvertedPerMediaType() {
    #expect(NuvioImport.convertSort("primary_release_date.desc", mediaType: .series) == "first_air_date.desc")
    #expect(NuvioImport.convertSort("first_air_date.asc", mediaType: .movie) == "primary_release_date.asc")
    #expect(NuvioImport.convertSort("popularity.desc", mediaType: .series) == "popularity.desc")
    #expect(NuvioImport.convertSort("original", mediaType: .movie) == nil)
    #expect(NuvioImport.convertSort("", mediaType: .movie) == nil)
    #expect(NuvioImport.convertSort(nil, mediaType: .movie) == nil)
}

@Test func tvCompanySortConverted() throws {
    let json = #"[{"title":"C","folders":[{"title":"F","sources":[{"provider":"tmdb","tmdbSourceType":"COMPANY","mediaType":"TV","title":"X","tmdbId":3,"sortBy":"primary_release_date.desc"}]}]}]"#
    let s = try NuvioImport.parse(Data(json.utf8)).collections[0].folders[0].sources[0]
    #expect(s.sortBy == "first_air_date.desc" && s.kind == .tmdbCompany(id: "3"))
}
