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
