import Foundation
import Testing
@testable import PlayerCore

// Build 5 device test 1, item 4: TMDB lists an actor once per role. The cast row (`CastRow`, ForEach by person ID)
// must never get the same ID twice (duplicate identities in a lazy stack break focus restore on the way back).
@Test func castKeepsEachPersonOnceAndJoinsTheRoles() {
    let json = #"""
    {"id":13682,"title":"Heffalump","credits":{"cast":[
      {"id":19540,"name":"Peter Cullen","character":"I-Aah","profile_path":"/pc.jpg"},
      {"id":77,"name":"Jim Cummings","character":"Winnie Puuh"},
      {"id":19540,"name":"Peter Cullen","character":"Erzähler"},
      {"id":77,"name":"Jim Cummings","character":"Tigger"},
      {"id":88,"name":"Kath Soucie"}]}}
    """#
    let m = TMDBClient.parseLocalized(Data(json.utf8), lang: "de", region: "DE", series: false)
    #expect(m?.cast.map(\.id) == [19540, 77, 88])
    #expect(m?.cast.first?.role == "I-Aah / Erzähler")
    #expect(m?.cast.first?.photo == "https://image.tmdb.org/t/p/w185/pc.jpg")
    #expect(m?.cast[1].role == "Winnie Puuh / Tigger")
    #expect(m?.cast[2].role == nil)
}

// Item 5: studios (movie: production companies; series: networks first) with their TMDB logos for the detail row.
@Test func studiosCarryTheirLogos() {
    let movie = #"""
    {"id":1,"title":"A","production_companies":[
      {"id":2,"name":"Pixar","logo_path":"/pixar.png"},{"id":3,"name":"Disney","logo_path":null},
      {"id":4,"name":"Third","logo_path":"/t.png"},{"id":5,"name":"Fourth","logo_path":"/f.png"}]}
    """#
    let m = TMDBClient.parseLocalized(Data(movie.utf8), lang: "de", region: "DE", series: false)
    #expect(m?.studios == ["Pixar", "Disney", "Third"])
    #expect(m?.studioLogos.map(\.name) == ["Pixar", "Disney", "Third"])
    #expect(m?.studioLogos.first?.logo == "https://image.tmdb.org/t/p/w300/pixar.png")
    #expect(m?.studioLogos[1].logo == nil)
    let series = #"""
    {"id":9,"name":"S","networks":[{"name":"HBO","logo_path":"/hbo.png"}],
     "production_companies":[{"name":"P1","logo_path":"/p1.png"},{"name":"P2"},{"name":"P3"}]}
    """#
    let s = TMDBClient.parseLocalized(Data(series.utf8), lang: "de", region: "DE", series: true)
    #expect(s?.studios == ["HBO", "P1", "P2"])
    #expect(s?.studioLogos.map(\.name) == ["HBO", "P1", "P2"])
    #expect(s?.studioLogos.first?.logo == "https://image.tmdb.org/t/p/w300/hbo.png")
}

// Item 3 (review W1b): the meta image is the backdrop; the tile's (cached) image stands in until it arrives and
// takes over when the meta address fails.
@Test func detailBackdropShowsTheTileImageUntilTheMetaImage() {
    let b = DetailPage.backdrop(tile: "https://a/tile.jpg", meta: "https://b/meta.jpg")
    #expect(b.main == "https://b/meta.jpg"); #expect(b.placeholder == "https://a/tile.jpg")
    let early = DetailPage.backdrop(tile: "https://a/tile.jpg", meta: nil)
    #expect(early.main == "https://a/tile.jpg"); #expect(early.placeholder == nil)
    let failed = DetailPage.backdrop(tile: "https://a/tile.jpg", meta: "https://b/meta.jpg", failed: "https://b/meta.jpg")
    #expect(failed.main == "https://a/tile.jpg"); #expect(failed.placeholder == nil)
    let same = DetailPage.backdrop(tile: "https://a/x.jpg", meta: "https://a/x.jpg")
    #expect(same.main == "https://a/x.jpg"); #expect(same.placeholder == nil)
    #expect(DetailPage.backdrop(tile: "  ", meta: nil).main == nil)
}

// Item 6: a preview pack (20 videos, "0 Kacheln zugeordnet" in device test 1) applies to the built-in package tiles
// by title too, and the pack's video becomes the focus motion of such a tile.
@Test func previewPackFillsBuiltInPackageTiles() {
    let pack = PreviewPack.Index([PreviewPackEntry(title: "Netflix", video: "https://v.example/netflix.mp4"),
                                  PreviewPackEntry(title: "action", video: "https://v.example/action.mp4")])
    #expect(PreviewPack.matches(pack, in: ReadyPackages.all) == 2)
    let streaming = PreviewPack.apply(pack, to: ReadyPackages.streamingDE)
    let netflix = streaming.folders.first { $0.title == "Netflix" }
    #expect(netflix?.focusVideo == "https://v.example/netflix.mp4")
    if let netflix { #expect(TileMotion.of(netflix, reduceMotion: false) == .video("https://v.example/netflix.mp4")) }
    // Fallback reason for the log line of a focused tile that stays a still.
    let wow = streaming.folders.first { $0.title == "WOW" }
    if let wow {
        #expect(TileMotion.stillReason(wow, reduceMotion: false) == "kein Video/GIF (kein Pack-Treffer)")
        #expect(TileMotion.stillReason(wow, reduceMotion: true) == "Bewegung reduziert")
    }
    if let netflix { #expect(TileMotion.stillReason(netflix, reduceMotion: false) == nil) }
}

// Review M3: English pack titles reach the German genre tiles through the package art aliases.
@Test func previewPackUsesThePackageAliases() {
    let pack = PreviewPack.Index([PreviewPackEntry(title: "Comedy", video: "https://v.example/comedy.mp4")])
    let genres = PreviewPack.apply(pack, to: ReadyPackages.genreCollection)
    #expect(genres.folders.first { $0.title == "Komödie" }?.focusVideo == "https://v.example/comedy.mp4")
    #expect(PreviewPack.matches(pack, in: [ReadyPackages.genreCollection]) == 1)
}

// Review N6/N8: a series names the same company as network and producer; a person's role repeats; a
// recommendation repeats. Each once.
@Test func studiosRolesAndRecommendationsOnce() {
    let json = #"""
    {"id":9,"name":"S","networks":[{"id":49,"name":"HBO","logo_path":"/hbo.png"}],
     "production_companies":[{"id":49,"name":"HBO","logo_path":"/hbo.png"},{"id":7,"name":"P1"}],
     "aggregate_credits":{"cast":[
       {"id":1,"name":"A","roles":[{"character":"X"}]},
       {"id":1,"name":"A","roles":[{"character":"Y"}]},
       {"id":1,"name":"A","roles":[{"character":"X"}]}]},
     "recommendations":{"results":[
       {"id":5,"name":"R","media_type":"tv","poster_path":"/r.jpg"},
       {"id":5,"name":"R","media_type":"tv","poster_path":"/r.jpg"}]}}
    """#
    let s = TMDBClient.parseLocalized(Data(json.utf8), lang: "de", region: "DE", series: true)
    #expect(s?.studios == ["HBO", "P1"])
    #expect(s?.cast.first?.role == "X / Y")
    #expect(s?.recommendations.count == 1)
}
