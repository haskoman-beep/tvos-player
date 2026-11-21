import Foundation
import Testing
@testable import PlayerCore

private func decodeStreams(_ json: String) throws -> [StreamItem] {
    try JSONDecoder().decode(StreamsResponse.self, from: Data(json.utf8)).streams
}

private func st(_ name: String, _ desc: String = "", hints: StreamBehaviorHints? = nil) -> StreamItem {
    StreamItem(name: name, description: desc, url: "https://x/\(name.hashValue)/\(desc.hashValue)", behaviorHints: hints)
}

// MARK: #39 AIOStreams-Felder

@Test func aioHintsDecodeAllFields() throws {
    let s = try decodeStreams(#"{"streams":[{"name":"AIO","url":"https://a/1","behaviorHints":{"service":"torbox","cached":true,"duration":1228,"seeders":42,"indexer":"Nyaa","publishDate":"2024-01-02T03:04:05Z","folderName":"Show.S01","folderSize":12000000000,"videoSize":1290000000,"filename":"Show.S01E01.1080p.mkv"}}]}"#)
    let h = try #require(s.first?.behaviorHints)
    #expect(h.service == "torbox")
    #expect(h.cached == true)
    #expect(h.duration == 1228)
    #expect(h.seeders == 42)
    #expect(h.indexer == "Nyaa")
    #expect(h.folderSize == 12_000_000_000)
    #expect(h.filename == "Show.S01E01.1080p.mkv")
}

@Test func aioHintsAreLenient() throws {
    // Falsche Typen verwerfen nur das Feld, nicht die Quelle; Zahlen/Wahrheitswerte als Text werden gelesen.
    let s = try decodeStreams(#"{"streams":[{"name":"A","url":"https://a/1","behaviorHints":{"service":{"id":"x"},"cached":"true","duration":"600","seeders":"viele","videoSize":"2000","bingeGroup":7}}]}"#)
    let h = try #require(s.first?.behaviorHints)
    #expect(h.service == nil)
    #expect(h.cached == true)
    #expect(h.duration == 600)
    #expect(h.seeders == nil)
    #expect(h.videoSize == 2000)
    #expect(h.bingeGroup == nil)
}

@Test func structuredCachedBeatsText() {
    // Text sagt ⚡, Feld sagt nicht gecacht → Feld gewinnt.
    let t = StreamTraits.parse(st("[TB⚡] 1080p", hints: StreamBehaviorHints(service: "torbox", cached: false)))
    #expect(t.cached == false)
    #expect(t.service == "TB")
    // Ohne Feld bleibt die Text-Erkennung.
    #expect(StreamTraits.parse(st("[RD+] 1080p")).cached == true)
    #expect(StreamTraits.parse(st("[RD+] 1080p")).service == "RD")
}

@Test func serviceIdMapping() {
    #expect(ReleaseName.serviceCode(id: "realdebrid") == "RD")
    #expect(ReleaseName.serviceCode(id: "Real-Debrid") == "RD")
    #expect(ReleaseName.serviceCode(id: "premiumize") == "PM")
    #expect(ReleaseName.serviceCode(id: "nzbdav") == "NZB")
    #expect(ReleaseName.serviceCode(id: "neu") == "NEU")
    #expect(ReleaseName.serviceCode(id: "") == nil)
}

@Test func bitrateFromSizeAndDuration() {
    let t = StreamTraits.parse(st("x", hints: StreamBehaviorHints(videoSize: 1_290_000_000, duration: 1228)))
    #expect(t.durationSeconds == 1228)
    #expect(abs((t.bitrateMbps ?? 0) - 8.40) < 0.01)
    #expect(StreamTraits.parse(st("x 2 GB")).bitrateMbps == nil)
}

// MARK: #30 Sprache, #33 AV1, #36 TorBox

private let de = SourceRankContext(audioPriority: ["de", "en", "orig"], av1Hardware: false)

@Test func contextFromAudioPriority() {
    #expect(SourceRankContext(audioPriority: ["ger", "en"], av1Hardware: false).primaryLanguage == "de")
    #expect(SourceRankContext(audioPriority: ["orig", "de"], av1Hardware: false).primaryLanguage == nil)
}

@Test func languageClasses() {
    func c(_ n: String, _ p: String?) -> SourceRanking.LanguageClass { SourceRanking.languageClass(StreamTraits.parse(st(n)), primary: p) }
    #expect(c("1080p GERMAN", "de") == .wanted)
    #expect(c("1080p 🇩🇪 🇬🇧", "de") == .wanted)
    #expect(c("1080p MULTI", "de") == .multi)
    #expect(c("1080p", "de") == .unknown)
    #expect(c("1080p 🇬🇧", "de") == .unknown)
    #expect(c("1080p 🇫🇷", "de") == .otherOnly)
    #expect(c("1080p", "en") == .wanted)
    #expect(c("1080p 🇩🇪", nil) == .unknown)
}

@Test func germanSourceMovesUpOrderOtherwiseKept() {
    let list = [st("A 2160p"), st("B 1080p 🇫🇷"), st("C 1080p GERMAN"), st("D 720p"), st("E 1080p MULTI")]
    let out = SourceRanking.order(list, context: de).map { String($0.name!.prefix(1)) }
    #expect(out == ["C", "E", "A", "D", "B"])
}

@Test func orderWithoutLanguageKeepsAddonOrder() {
    let list = [st("A 2160p"), st("B 1080p 🇫🇷"), st("C 1080p GERMAN")]
    let ctx = SourceRankContext(audioPriority: ["orig"], av1Hardware: true)
    #expect(SourceRanking.order(list, context: ctx).map(\.name) == list.map(\.name))
}

@Test func uncachedGoesLast() {
    let list = [st("A 2160p GERMAN ⏳"), st("B 1080p"), st("C 1080p ⚡")]
    #expect(SourceRanking.order(list, context: de).map { String($0.name!.prefix(1)) } == ["B", "C", "A"])
}

@Test func heavyAV1WithoutHardwareDropsBehindSameLanguage() {
    let list = [st("A 2160p AV1"), st("B 2160p HEVC"), st("C 1080p")]
    #expect(SourceRanking.order(list, context: de).map { String($0.name!.prefix(1)) } == ["B", "C", "A"])
    // Mit Hardware bleibt 4K-AV1 vorn.
    let hw = SourceRankContext(audioPriority: ["de"], av1Hardware: true)
    #expect(SourceRanking.order(list, context: hw).map { String($0.name!.prefix(1)) } == ["A", "B", "C"])
}

@Test func av1WithDolbyVisionYieldsWithinResolution() {
    let hw = SourceRankContext(audioPriority: ["de"], av1Hardware: true)
    let list = [st("A 1080p AV1 DV"), st("B 1080p HEVC DV"), st("C 720p")]
    #expect(SourceRanking.order(list, context: hw).map { String($0.name!.prefix(1)) } == ["B", "A", "C"])
    // 1080p-AV1 ohne Hardware: nur innerhalb der Auflösung nach hinten.
    let list2 = [st("A 1080p AV1"), st("B 1080p x265"), st("C 720p")]
    #expect(SourceRanking.order(list2, context: de).map { String($0.name!.prefix(1)) } == ["B", "A", "C"])
}

@Test func torboxFirstWithinResolutionOnlyWithSeveralServices() {
    let list = [st("[RD+] A 2160p"), st("[TB+] B 2160p"), st("[RD+] C 1080p"), st("[TB+] D 1080p")]
    #expect(SourceRanking.order(list, context: de).map { $0.name!.split(separator: " ")[1] } == ["B", "A", "D", "C"])
    let onlyRD = [st("[RD+] A 2160p"), st("[RD+] B 2160p")]
    #expect(SourceRanking.order(onlyRD, context: de).map(\.name) == onlyRD.map(\.name))
}

@Test func torboxByStructuredService() {
    let a = st("A 1080p", hints: StreamBehaviorHints(service: "realdebrid", cached: true))
    let b = st("B 1080p", hints: StreamBehaviorHints(service: "torbox", cached: true))
    #expect(SourceRanking.order([a, b], context: de).map(\.name) == ["B 1080p", "A 1080p"])
}

@Test func entriesOrderKeepsAddon() {
    let e: [(addon: String, stream: StreamItem)] = [("X", st("A 1080p")), ("Y", st("B 1080p GERMAN"))]
    let out = SourceRanking.order(e, context: de)
    #expect(out.map(\.addon) == ["Y", "X"])
}

@Test func sourceSettingsDefaultsAndOldProfiles() throws {
    let old = #"{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","name":"Alt"}"#
    let p = try JSONDecoder().decode(Profile.self, from: Data(old.utf8))
    #expect(p.sources == SourceSettings())
    #expect(p.sources.smartOrder)
    var q = p; q.sources.smartOrder = false; q.sources.ratingIconSetURL = "https://i/set.json"
    let back = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(q))
    #expect(back.sources == q.sources)
}

// MARK: #40 Untertitel-Felder

@Test func subtitleFieldsDecode() throws {
    let r = try JSONDecoder().decode(SubtitlesResponse.self, from: Data(#"{"subtitles":[{"id":"1","url":"https://s/1","lang":"eng","label":"Movie.2010.1080p.BluRay.x264-SPARKS","hearingImpaired":true},{"id":"2","url":"https://s/2","lang":"ger","forced":"true"},{"id":"3","url":"https://s/3","lang":"ger","forced":1}]}"#.utf8))
    #expect(r.subtitles.count == 3)
    #expect(r.subtitles[0].hearingImpaired && !r.subtitles[0].forced)
    #expect(r.subtitles[0].label == "Movie.2010.1080p.BluRay.x264-SPARKS")
    #expect(r.subtitles[1].forced && r.subtitles[2].forced)
}

@Test func subtitleSelectPrefersReleaseAndNonSDHKeepsOneForced() {
    func s(_ id: String, forced: Bool = false, hi: Bool = false, label: String? = nil) -> AddonSubtitle {
        AddonSubtitle(id: id, url: "https://s/\(id)", lang: "ger", addonName: "OS", forced: forced, hearingImpaired: hi, label: label)
    }
    let subs = [s("hi", hi: true), s("plain"), s("f1", forced: true), s("f2", forced: true),
                s("match", label: "Movie.2010.1080p.BluRay.x264-SPARKS"), s("other")]
    let picked = AddonSubtitlePlan.select(subs, languages: ["de"], perLanguage: 3, release: "Movie.2010.1080p.BluRay.x264-SPARKS.mkv")
    #expect(picked.map(\.id) == ["match", "plain", "other", "f1"])
}

@Test func subtitleReleaseMatchLevels() {
    #expect(AddonSubtitlePlan.releaseMatch("Movie.2010.1080p.WEB-GRP", release: "movie.2010.1080p.web-grp.mkv") == 0)
    #expect(AddonSubtitlePlan.releaseMatch("Movie.2010.720p.WEB-GRP", release: "Movie.2010.1080p.WEB-GRP.mkv") == 1)
    #expect(AddonSubtitlePlan.releaseMatch(nil, release: "x") == 2)
}

@Test func subtitleTrackNameCarriesFlagsForPicker() {
    let f = AddonSubtitle(id: "1", url: "u1", lang: "ger", addonName: "OpenSubtitles v3", forced: true)
    let h = AddonSubtitle(id: "2", url: "u2", lang: "ger", addonName: "OpenSubtitles v3", hearingImpaired: true)
    #expect(AddonSubtitlePlan.trackNames([f, h]) == ["Deutsch · OpenSubtitles · Erzwungen", "Deutsch · OpenSubtitles · SDH"])
    let track = AudioTrackInfo(id: 9, language: "de", name: "Deutsch · OpenSubtitles · Erzwungen", isExternal: true)
    #expect(SubtitlePicker.isForced(track))
    let pick = SubtitlePicker.pick([track], mode: .forcedOnly, preferredLanguage: "de", audioLanguage: "de")
    #expect(pick.track?.id == 9)
}

// MARK: #44 Trakt-Empfehlungen, #41 limit/hideTitle, #35 Datum

@Test func traktRecommendationsRequestAndParse() async throws {
    let http = FakeSender([(200, #"[{"title":"Film A","year":2020,"ids":{"imdb":"tt1","trakt":1}},{"title":"ohne IMDb","ids":{"trakt":2}}]"#)])
    let t = TraktClient(clientID: "C", clientSecret: "S", http: http)
    let tok = SyncToken(accessToken: "T", refreshToken: nil, expiresAt: Date().addingTimeInterval(3600))
    let items = try await t.list(user: nil, slug: "recommendations/movies", token: tok)
    #expect(items.map(\.id) == ["tt1"] && items[0].type == "movie")
    #expect(http.sent[0].url.absoluteString.hasSuffix("/recommendations/movies?ignore_watchlisted=true&limit=20"))
    #expect(http.sent[0].headers["Authorization"] == "Bearer T")
    // Ohne Anmeldung: nichts gefragt, leer.
    #expect(try await t.list(user: nil, slug: "recommendations/shows", token: nil).isEmpty)
    #expect(http.sent.count == 1)
}

@Test func catalogLimitAndFolderTitle() {
    let s = CatalogSource(id: "x", title: "X", kind: .watchlist, mediaType: .both, limit: 2)
    #expect(s.applyingLimit([1, 2, 3]) == [1, 2])
    #expect(CatalogSource(id: "x", title: "X", kind: .watchlist, mediaType: .both, limit: 0).limit == nil)
    #expect(Folder(id: "f", title: "F", sources: [], hideTitle: false).showsTitleOverImage)
    #expect(!Folder(id: "f", title: "F", sources: []).showsTitleOverImage)
}

@Test func sharedISODate() {
    #expect(ISODate.dateTime("2024-01-02T03:04:05.123Z") != nil)
    #expect(ISODate.dateTime("2024-01-02T03:04:05Z") == Date(timeIntervalSince1970: 1_704_164_645))
    #expect(ISODate.parse("2024-01-02") == Date(timeIntervalSince1970: 1_704_153_600))
    #expect(ISODate.parse("kaputt") == nil)
    #expect(ISODate.germanDay("2024-03-05") == "05.03.2024")
    #expect(ISODate.germanDay("2024") == "2024")
}

@Test func torboxFirstAlsoWithMixedResolutions() {
    // Auflösungen gemischt: die 2160p-Plätze (1, 3) tauschen untereinander, 1080p bleibt auf Platz 2.
    let list = [st("[RD+] A 2160p"), st("[RD+] B 1080p"), st("[TB+] C 2160p")]
    #expect(SourceRanking.order(list, context: de).map { $0.name!.split(separator: " ")[1] } == ["C", "B", "A"])
}

@Test func av1From1440pCountsAsHeavy() {
    let list = [st("A 1440p AV1"), st("B 1080p HEVC")]
    #expect(SourceRanking.order(list, context: de).map { String($0.name!.prefix(1)) } == ["B", "A"])
}

@Test func tvmazeAirstampMovesDayAndAddsTime() throws {
    let data = Data(#"[{"season":1,"number":2,"airstamp":"2026-11-21T01:00:00+00:00"},{"season":1,"number":3,"airstamp":null},{"season":2,"number":1,"airstamp":"2026-12-30T20:00:00+00:00"}]"#.utf8)
    let stamps = TVmazeClient.parseAirstamps(data)
    #expect(stamps.count == 2)
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
    let e1 = UpcomingEpisode(seriesID: "tt1", seriesName: "S", season: 1, episode: 2, airDate: "2026-11-20")
    let e2 = UpcomingEpisode(seriesID: "tt1", seriesName: "S", season: 2, episode: 1, airDate: "2026-12-01")   // > 1 Tag daneben
    let e3 = UpcomingEpisode(seriesID: "tt1", seriesName: "S", season: 1, episode: 3, airDate: "2026-11-27")
    let out = TVmazeClient.apply([e1, e2, e3], stamps: stamps, calendar: cal)
    #expect(out[0].airDate == "2026-11-21" && out[0].airTime == "02:00")
    #expect(out[0].label == "02:00 · S1 F2")
    #expect(out[1] == e2 && out[2] == e3)
}

@Test func tvmazeLookupAndCache() async throws {
    let http = FakeSender([(200, #"{"id":42,"name":"S"}"#), (200, #"[{"season":1,"number":1,"airstamp":"2026-11-21T01:00:00+00:00"}]"#)])
    let a = TVmazeAirtimes(client: TVmazeClient(http: http, sleep: { _ in }))
    let s1 = await a.stamps(imdb: "tt123")
    let s2 = await a.stamps(imdb: "tt123")
    #expect(s1.count == 1 && s1 == s2)
    #expect(http.sent.count == 2)
    #expect(http.sent.first?.url.absoluteString == "https://api.tvmaze.com/lookup/shows?imdb=tt123")
    #expect(http.sent.last?.url.absoluteString == "https://api.tvmaze.com/shows/42/episodes")
    // Unbekannt (404) → leer, ohne weitere Abfrage der Folgen.
    let http2 = FakeSender([(404, "")])
    let b = TVmazeAirtimes(client: TVmazeClient(http: http2, sleep: { _ in }))
    #expect(await b.stamps(imdb: "tt9").isEmpty && http2.sent.count == 1)
}

@Test func torboxFilesAndLink() async throws {
    let list = #"{"success":true,"data":[{"id":7,"name":"Film.2020.2160p","download_finished":true,"created_at":"2026-11-20T10:00:00Z","files":[{"id":0,"short_name":"Film.2020.2160p.mkv","size":20000000000},{"id":1,"short_name":"sample.mkv","size":1},{"id":2,"short_name":"info.nfo","size":1}]},{"id":8,"name":"halb","download_finished":false,"files":[{"id":0,"short_name":"x.mkv"}]}]}"#
    let http = FakeSender([(200, list), (500, ""), (200, #"{"data":[]}"#), (200, #"{"success":true,"data":"https://cdn.example/x.mkv"}"#)])
    let c = TorBoxClient(apiKey: "K", http: http, sleep: { _ in })
    let files = try await c.files()
    #expect(files.count == 1)
    let f = try #require(files.first)
    #expect(f.name == "Film.2020.2160p.mkv" && f.kind == .torrent && f.itemID == 7 && f.sizeLabel == "20,0 GB")
    #expect(http.sent[0].headers["Authorization"] == "Bearer K")
    #expect(http.sent[0].url.path == "/v1/api/torrents/mylist")
    #expect(try await c.link(for: f).absoluteString == "https://cdn.example/x.mkv")
    let q = URLComponents(url: http.sent[3].url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(q.contains(URLQueryItem(name: "torrent_id", value: "7")) && q.contains(URLQueryItem(name: "file_id", value: "0")))
}
