import Foundation
import Testing
@testable import PlayerCore

// Welle E-a: Poster-Plaketten, Qualitätszeile der Detailseite, Bewertungsauswahl, Bilder vom Metadaten-Addon.

private func traits(_ desc: String, cached: Bool? = nil) -> StreamTraits {
    var t = StreamTraits.parse(StreamItem(name: "x", description: desc, url: "https://x"))
    if let cached { t.cached = cached }
    return t
}

@Test func titleDisplayDefaultsAndMigration() throws {
    // Altes Aussehen ohne Feld: Poster-Plaketten aus, IMDb/RT/Trakt, Addon-Bilder an.
    let old = try JSONDecoder().decode(Appearance.self, from: Data(#"{"accent":"green","badges":{"onPosters":true}}"#.utf8))
    #expect(old.titles == TitleDisplaySettings())
    #expect(old.titles.posterBadges == .off)
    #expect(old.titles.ratingSources == ["imdb", "tomatoes", "trakt"])
    #expect(old.titles.addonImages)
    // Teilweise vorhanden, unbekannte Platzierung → Standard.
    let partial = try JSONDecoder().decode(TitleDisplaySettings.self, from: Data(#"{"posterBadges":"links","addonImages":false}"#.utf8))
    #expect(partial.posterBadges == .off && !partial.addonImages && partial.ratingSources == RatingSelection.defaultSources)
    // Rundreise.
    var a = Appearance()
    a.titles.posterBadges = .bottom
    a.titles.set(rating: "letterboxd", true)
    a.titles.set(rating: "imdb", false)
    let back = try JSONDecoder().decode(Appearance.self, from: JSONEncoder().encode(a))
    #expect(back == a)
    #expect(back.titles.shows(rating: "letterboxd") && !back.titles.shows(rating: "imdb"))
}

@Test func posterBadgesFollowPlacement() {
    let b = BestQuality.from([traits("2160p DV HDR10 TrueHD Atmos 7.1 REMUX")])!
    let s = BadgeSettings()
    #expect(QualityBadges.poster(b, settings: s, placement: .off).isEmpty)
    #expect(QualityBadges.poster(b, settings: s, placement: .topTrailing).map(\.text) == ["4K", "DV", "Atmos"])
    #expect(QualityBadges.poster(b, settings: s, placement: .bottom).count == 3)
}

@Test func detailRowPriorityAndLimit() {
    // Alles vorhanden: genau 5 in der Reihenfolge Auflösung, DV, Atmos, Ton+Kanäle, Remux.
    let q = DetailQuality.from([traits("2160p DV HDR10+ TrueHD Atmos 7.1 REMUX"), traits("1080p DTS-HD MA 5.1 WEB-DL")])!
    let row = QualityBadges.detailRow(q, settings: BadgeSettings())
    #expect(row.map(\.text) == ["4K", "Dolby Vision", "Dolby Atmos", "TrueHD 7.1", "REMUX"])
    #expect(row.count <= QualityBadges.detailRowLimit)
    #expect(row.compactMap(\.logo) == [.uhd4K, .dolbyVision, .dolbyAtmos, .remux])
    // Kein DV: HDR10+ an zweiter Stelle; Ton aus der besten Quelle mit deren Kanälen.
    let h = DetailQuality.from([traits("2160p HDR10+ DDP 5.1"), traits("1080p DTS-HD MA 7.1")])!
    #expect(QualityBadges.detailRow(h, settings: BadgeSettings()).map(\.text) == ["4K", "HDR10+", "DTS-HD MA 7.1"])
    // Nur HDR ohne Ton-Format: Kanäle allein, 2.0 allein nicht.
    let k = DetailQuality.from([traits("1080p HDR 5.1")])!
    #expect(QualityBadges.detailRow(k, settings: BadgeSettings()).map(\.text) == ["HD", "HDR", "5.1"])
    let st = DetailQuality.from([traits("720p 2.0")])!
    #expect(QualityBadges.detailRow(st, settings: BadgeSettings()).isEmpty)
    // Format ohne Kanäle bleibt Format; Kanäle einer anderen Quelle werden nicht angehängt.
    let f = DetailQuality.from([traits("1080p TrueHD"), traits("1080p AAC 5.1")])!
    #expect(QualityBadges.detailRow(f, settings: BadgeSettings()).map(\.text) == ["HD", "TrueHD"])
    // Ungecachte Quellen zählen nicht, solange gecachte da sind.
    let c = DetailQuality.from([traits("2160p TrueHD 7.1", cached: false), traits("1080p DD 5.1", cached: true)])!
    #expect(QualityBadges.detailRow(c, settings: BadgeSettings()).map(\.text) == ["HD", "DD 5.1"])
    #expect(DetailQuality.from([StreamTraits]()) == nil)
}

@Test func detailRowFollowsSettings() {
    let q = DetailQuality.from([traits("2160p DV TrueHD Atmos 7.1 REMUX")])!
    var s = BadgeSettings(style: .text)
    s.channels = false
    s.source = false
    let row = QualityBadges.detailRow(q, settings: s)
    #expect(row.map(\.text) == ["4K", "Dolby Vision", "Dolby Atmos", "TrueHD"])
    #expect(row.allSatisfy { $0.logo == nil })
    s.audio = false
    s.channels = true
    // Tonformat aus: Atmos entfällt, Kanäle bleiben allein.
    #expect(QualityBadges.detailRow(q, settings: s).map(\.text) == ["4K", "Dolby Vision", "7.1"])
}

@Test func ratingSelectionMergeAndFilter() {
    let mdb = ExternalRatings(values: ["imdb": 6.9, "tomatoes": 63, "popcorn": 49, "metacritic": 54, "letterboxd": 2.7,
                                       "trakt": 71, "tmdb": 68], certification: "PG")
    // Standard: nur IMDb, RT, Trakt – in fester Reihenfolge.
    let def = RatingSelection.badges(mdb, selected: RatingSelection.defaultSources)
    #expect(def.map(\.source) == ["imdb", "tomatoes", "trakt"])
    // Wert aus den Metadaten geht vor, MDBList ergänzt.
    let meta = RatingSelection.metaValues(imdbRating: "6.3")
    #expect(meta == ["imdb": 6.3])
    let merged = RatingSelection.merge(meta: meta, mdblist: mdb)
    #expect(merged?.values["imdb"] == 6.3 && merged?.values["trakt"] == 71 && merged?.certification == "PG")
    #expect(RatingSelection.badges(merged, selected: ["trakt", "imdb"]).map(\.text) == ["6.3", "71%"])
    // Ohne MDBList: nur der Addon-Wert.
    let only = RatingSelection.merge(meta: meta, mdblist: nil)
    #expect(RatingSelection.badges(only, selected: RatingSelection.defaultSources).map(\.source) == ["imdb"])
    #expect(RatingSelection.merge(meta: [:], mdblist: nil) == nil)
    // Unlesbare oder leere Werte zählen nicht; Komma geht.
    #expect(RatingSelection.metaValues(imdbRating: nil).isEmpty)
    #expect(RatingSelection.metaValues(imdbRating: "").isEmpty)
    #expect(RatingSelection.metaValues(imdbRating: "0").isEmpty)
    #expect(RatingSelection.metaValues(imdbRating: "11").isEmpty)
    #expect(RatingSelection.metaValues(imdbRating: "7,4") == ["imdb": 7.4])
    // Alles abgewählt: keine Plakette.
    #expect(RatingSelection.badges(mdb, selected: []).isEmpty)
}

private func addon(_ id: String, resources: [AddonResource], types: [String] = ["movie", "series"], prefixes: [String]? = ["tt"]) -> InstalledAddon {
    InstalledAddon(manifestURL: "https://\(id).example/manifest.json",
                   manifest: AddonManifest(id: id, name: id, version: "1", resources: resources, types: types, idPrefixes: prefixes))
}

private func meta(_ json: String) throws -> MetaDetail {
    try JSONDecoder().decode(MetaDetail.self, from: Data(json.utf8))
}

@Test func metadataAddonChoice() {
    let streams = addon("streams", resources: [AddonResource(name: "stream")])
    let tmdbOnly = addon("tmdbmeta", resources: [AddonResource(name: "meta")], prefixes: ["tmdb:"])
    let aio = addon("aiometa", resources: [AddonResource(name: "catalog"), AddonResource(name: "meta")])
    let cinemeta = addon("com.linvo.cinemeta", resources: [AddonResource(name: "meta")])
    #expect(MetaImageChoice.metadataAddon(in: [streams, cinemeta, tmdbOnly, aio], type: "movie", id: "tt123")?.manifest.id == "aiometa")
    #expect(MetaImageChoice.metadataAddon(in: [streams, cinemeta], type: "movie", id: "tt123") == nil)
    #expect(!MetaImageChoice.hasMetadataAddon([streams, tmdbOnly]))
    #expect(MetaImageChoice.hasMetadataAddon([streams, aio]))
    #expect(!MetaImageChoice.hasMetadataAddon([streams, cinemeta]))
}

@Test func metaImagesAndRatingFromAddon() throws {
    let base = try meta(#"{"id":"tt1","type":"movie","name":"Base","poster":"cine-p","background":"cine-b","imdbRating":"6.1"}"#)
    // Zahl statt Text wird gelesen; Unsinn bricht die Metadaten nicht.
    let addonMeta = try meta(#"{"id":"tt1","type":"movie","name":"Addon","poster":"rpdb-p","logo":"addon-l","imdbRating":6.3}"#)
    #expect(addonMeta.imdbRating == "6.3")
    let odd = try meta(#"{"id":"tt1","type":"movie","name":"X","imdbRating":{"x":1}}"#)
    #expect(odd.imdbRating == nil && odd.name == "X")
    var l = LocalizedMeta(tmdbID: 5)
    l.name = "Deutsch"; l.overview = "Text"; l.poster = "tmdb-p"; l.logo = "tmdb-l"; l.background = "tmdb-b"
    // Addon-Bilder zuerst, Texte aus TMDB, Hintergrund ohne Addon-Bild wie bisher (Cinemeta vor TMDB).
    let on = MetaImageChoice.merge(base: base, addon: addonMeta, localized: l, preferAddonImages: true)!
    #expect(on.poster == "rpdb-p" && on.logo == "addon-l" && on.background == "cine-b")
    #expect(on.name == "Deutsch" && on.description == "Text" && on.imdbRating == "6.3")
    // Schalter aus: wie vorher (TMDB-Poster/Logo), Bewertung des Addons zählt trotzdem.
    let off = MetaImageChoice.merge(base: base, addon: addonMeta, localized: l, preferAddonImages: false)!
    #expect(off.poster == "tmdb-p" && off.logo == "tmdb-l" && off.background == "cine-b" && off.imdbRating == "6.3")
    // Ohne Addon: Cinemeta-Bewertung, bisherige Bildwahl.
    let none = MetaImageChoice.merge(base: base, addon: nil, localized: l, preferAddonImages: true)!
    #expect(none.poster == "tmdb-p" && none.imdbRating == "6.1")
    // Cinemeta fehlt: Addon ist die Grundlage.
    let only = MetaImageChoice.merge(base: nil, addon: addonMeta, localized: nil, preferAddonImages: false)!
    #expect(only.poster == "rpdb-p" && only.name == "Addon")
    #expect(MetaImageChoice.merge(base: nil, addon: nil, localized: l, preferAddonImages: true) == nil)
    // Leere Addon-Adresse zählt nicht.
    #expect(MetaImageChoice.pick(addon: "", tmdb: "t", base: "b", preferAddon: true) == "t")
}
