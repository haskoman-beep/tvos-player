import Foundation
import Testing
@testable import PlayerCore

@Test func mdblistParsesAndDropsOffScale() {
    let json = #"""
    {"title":"X","certification":"PG-13","ratings":[
      {"source":"imdb","value":7.4},{"source":"metacritic","value":0},{"source":"trakt","value":76},
      {"source":"tomatoes","value":85},{"source":"popcorn","value":90},{"source":"letterboxd","value":3.9},
      {"source":"tvdb","value":null},{"source":"imdb","value":1.0},{"source":"tmdb","value":120}]}
    """#
    let r = MDBList.parse(status: 200, data: Data(json.utf8))
    #expect(r == .ratings(ExternalRatings(values: ["imdb": 7.4, "trakt": 76, "tomatoes": 85, "popcorn": 90, "letterboxd": 3.9], certification: "PG-13")))
    if case .ratings(let x) = r {
        #expect(MDBList.badges(x).map(\.text) == ["7.4", "85%", "90%", "3.9", "76%"])
    }
}

@Test func mdblistStatuses() {
    #expect(MDBList.parse(status: 429, data: Data()) == .limitReached)
    #expect(MDBList.parse(status: 200, data: Data(#"{"error":"API Limit Reached!"}"#.utf8)) == .limitReached)
    #expect(MDBList.parse(status: 404, data: Data(#"{"error":"Item not found"}"#.utf8)) == .notFound)
    #expect(MDBList.parse(status: 401, data: Data(#"{"error":"Invalid API key"}"#.utf8)) == .failed)
    #expect(MDBList.parse(status: 200, data: Data("<html>".utf8)) == .failed)
}

@Test func ratingsFreshness() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(MDBList.isFresh(storedAt: now - 23 * 3600, found: true, now: now))
    #expect(!MDBList.isFresh(storedAt: now - 25 * 3600, found: true, now: now))
    #expect(!MDBList.isFresh(storedAt: now - 7 * 3600, found: false, now: now))
}

@Test func techBadgesUseBestUsableStream() {
    let s = [StreamItem(name: "⚡ 2160p", title: "Film.2160p.DV.HDR10.TrueHD.Atmos.7.1", url: "https://a"),
             StreamItem(name: "⚡ 1080p", title: "Film.1080p.DDP.5.1", url: "https://b"),
             StreamItem(name: "🎫 2160p", title: "Film.2160p.HDR10+", url: "https://c")]
    #expect(TechBadges.summary(s) == ["4K", "Dolby Vision", "HDR", "Dolby Atmos", "7.1"])
}

@Test func cardStates() {
    var b = ProgressBook()
    let film = MetaPreview(id: "tt1", type: "movie", name: "F")
    let show = MetaPreview(id: "tt2", type: "series", name: "S")
    b.record(id: "tt1", item: film, position: 1800, duration: 6000)
    #expect(b.cardState(itemID: "tt1") == CardState(fraction: 0.3, remainingSeconds: 4200))
    b.record(id: "tt1", item: film, position: 5900, duration: 6000)
    #expect(b.cardState(itemID: "tt1")?.watched == true)
    b.record(id: "tt2:1:3", item: show, season: 1, episode: 3, position: 600, duration: 2400)
    #expect(b.cardState(itemID: "tt2") == CardState(fraction: 0.25, remainingSeconds: 1800, episode: "S1 F3"))
    #expect(b.cardState(itemID: "tt9") == nil)
}

@Test func extendedStreamTraits() {
    let a = StreamTraits.parse(StreamItem(name: "⚡ 4K", title: "Film.2160p.UHD.BluRay.REMUX.DV.HDR10.HEVC.10bit.DTS-X.7.1", url: "https://a"))
    #expect(a.source == "REMUX"); #expect(a.videoCodec == "HEVC"); #expect(a.tenBit)
    #expect(a.audio == ["DTS:X"]); #expect(a.channels == "7.1"); #expect(a.hdr == ["DV", "HDR10"])
    let b = StreamTraits.parse(StreamItem(name: "1080p", title: "Show.S01E01.1080p.WEB-DL.DDP5.1.H.264", url: "https://b"))
    #expect(b.source == "WEB-DL"); #expect(b.videoCodec == "H.264"); #expect(b.channels == "5.1"); #expect(b.audio == ["DD+"])
    let c = StreamTraits.parse(StreamItem(name: "720p", title: "Film.HDRip.x264", url: "https://c"))
    #expect(c.hdr.isEmpty); #expect(c.videoCodec == "H.264")
}

@Test func tmdbLocalizedParsing() {
    let json = #"""
    {"id":27205,"title":"Inception","overview":"Dom Cobb ist ein Dieb …","poster_path":"/de.jpg","backdrop_path":"/bg.jpg",
     "genres":[{"name":"Action"},{"name":"Science Fiction"}],
     "images":{"logos":[{"iso_639_1":"en","file_path":"/en.png"},{"iso_639_1":"de","file_path":"/de.png"}]},
     "release_dates":{"results":[{"iso_3166_1":"US","release_dates":[{"certification":"PG-13"}]},
                                 {"iso_3166_1":"DE","release_dates":[{"certification":""},{"certification":"12"}]}]}}
    """#
    let m = TMDBClient.parseLocalized(Data(json.utf8), lang: "de", region: "DE", series: false)
    #expect(m?.logo == "https://image.tmdb.org/t/p/w500/de.png")
    #expect(m?.certification == "FSK 12")
    #expect(m?.name == "Inception")
    let s = TMDBClient.parseSeason(Data(#"{"episodes":[{"episode_number":1,"name":"Der Anfang","overview":""},{"episode_number":2,"name":"Folge 2"}]}"#.utf8))
    #expect(s[1]?.name == "Der Anfang"); #expect(s[1]?.overview == nil); #expect(s[2]?.name == nil)
}

@Test func tmdbClientUsesShortImageLanguage() throws {
    let c = TMDBClient(apiKey: "k", language: "de-DE")
    #expect(c.languageCode == "de"); #expect(c.regionCode == "DE")
}

@Test func episodeListSkipsUnaired() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15
    let v = [MetaVideo(id: "a", season: 1, episode: 1, released: "2026-01-01T00:00:00.000Z"),
             MetaVideo(id: "b", season: 1, episode: 2, released: "2027-06-01T00:00:00.000Z"),
             MetaVideo(id: "c", season: 1, episode: 3, released: nil)]
    #expect(EpisodeRef.list(from: v, now: now).map(\.episode) == [1, 3])
}

@Test func tmdbExtrasParsing() {
    let json = #"""
    {"id":38365,"title":"Kindsköpfe","original_title":"Grown Ups","overview":"Fünf Freunde …","tagline":"Jungs bleiben Jungs",
     "release_date":"2010-06-24","budget":80000000,"revenue":271430189,"status":"Released",
     "production_companies":[{"name":"Happy Madison"},{"name":"Columbia Pictures"}],"production_countries":[{"name":"United States of America"}],
     "credits":{"cast":[{"id":19292,"name":"Adam Sandler","character":"Lenny Feder","profile_path":"/a.jpg"}],
                "crew":[{"job":"Director","name":"Dennis Dugan"},{"job":"Writer","name":"Fred Wolf"},{"job":"Screenplay","name":"Adam Sandler"}]},
     "videos":{"results":[{"site":"YouTube","key":"teaserEN","type":"Teaser","iso_639_1":"en"},
                          {"site":"YouTube","key":"trailerEN","type":"Trailer","iso_639_1":"en","official":true},
                          {"site":"YouTube","key":"trailerDE","type":"Trailer","iso_639_1":"de"},
                          {"site":"Vimeo","key":"x","type":"Trailer","iso_639_1":"de"}]},
     "recommendations":{"results":[{"id":89492,"title":"Kindsköpfe 2","poster_path":"/p.jpg","release_date":"2013-07-11","media_type":"movie"}]}}
    """#
    let m = TMDBClient.parseLocalized(Data(json.utf8), lang: "de", region: "DE", series: false)
    #expect(m?.cast.first == CastMember(id: 19292, name: "Adam Sandler", role: "Lenny Feder", photo: "https://image.tmdb.org/t/p/w185/a.jpg"))
    #expect(m?.creators == ["Dennis Dugan"]); #expect(m?.writers == ["Adam Sandler", "Fred Wolf"])
    #expect(m?.studios == ["Happy Madison", "Columbia Pictures"]); #expect(m?.originalTitle == "Grown Ups")
    #expect(m?.trailerYouTube == "trailerDE")
    #expect(m?.recommendations.map(\.id) == ["tmdb:89492"]); #expect(m?.budget == 80_000_000)
}
