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

// Item 3: the detail page showed another backdrop than the tile and hero (meta image first, then the catalogue
// one) and loaded it again. The page now takes the tile's image first; the meta image only fills a gap.
@Test func detailBackdropKeepsTheTileImage() {
    #expect(DetailPage.backdrop(tile: "https://a/tile.jpg", meta: "https://b/meta.jpg") == "https://a/tile.jpg")
    #expect(DetailPage.backdrop(tile: nil, meta: "https://b/meta.jpg") == "https://b/meta.jpg")
    #expect(DetailPage.backdrop(tile: "  ", meta: "https://b/meta.jpg") == "https://b/meta.jpg")
    #expect(DetailPage.backdrop(tile: nil, meta: nil) == nil)
}
