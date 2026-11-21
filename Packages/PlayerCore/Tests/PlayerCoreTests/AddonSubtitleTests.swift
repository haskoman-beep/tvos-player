import Foundation
import Testing
@testable import PlayerCore

private let osManifest = #"{"id":"org.stremio.opensubtitlesv3","version":"1.0.0","name":"OpenSubtitles v3","catalogs":[],"resources":["subtitles"],"types":["movie","series"],"idPrefixes":["tt"]}"#
private let streamManifest = #"{"id":"com.aio","name":"AIOStreams","version":"1","resources":["stream"],"types":["movie","series"],"idPrefixes":["tt"]}"#
private let otherSubsManifest = #"{"id":"x.subs","name":"Andere UT","version":"1","resources":[{"name":"subtitles","types":["movie"]}],"types":["movie"]}"#

private func addon(_ base: String, _ json: String) throws -> InstalledAddon {
    InstalledAddon(manifestURL: base + "/manifest.json", manifest: try JSONDecoder().decode(AddonManifest.self, from: Data(json.utf8)))
}

/// Wartet lange, um den Zeitablauf zu prüfen.
private struct SlowHTTP: HTTPFetching {
    func data(from url: URL) async throws -> Data {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return Data(#"{"subtitles":[{"id":"1","url":"https://s/slow","lang":"ger"}]}"#.utf8)
    }
}

@Test func subtitlesDecodeExampleJSON() async throws {
    let a = try addon("https://os.example", osManifest)
    let http = FakeHTTP(routes: [
        "https://os.example/subtitles/movie/tt1.json":
            #"{"subtitles":[{"id":"30949","url":"https://subs.example/file/1","lang":"ger","subtitleFileName":"film.ger.srt","SubEncoding":"CP1252"},{"id":7,"url":"https://subs.example/file/2.vtt","lang":"eng"},{"lang":"fre"}]}"#,
    ])
    let subs = try await AddonClient(http: http).subtitles(a, type: "movie", id: "tt1")
    #expect(subs.map(\.id) == ["30949", "7"])          // Eintrag ohne url übersprungen, Zahl-ID gelesen
    #expect(subs.map(\.languageCode) == ["de", "en"])
    #expect(subs[0].addonName == "OpenSubtitles v3")
    #expect(subs[0].formatHint == "srt")
    #expect(subs[1].formatHint == "vtt")
    #expect(AddonSubtitle(id: "x", url: "https://a/b", lang: nil, addonName: "A", fileName: "x.ass").formatHint == "ass")
    #expect(AddonSubtitle(id: "x", url: "https://a/b", lang: nil, addonName: "A").formatHint == "srt")
}

@Test func subtitlesFromAddonsSeriesFilterAndDedupe() async throws {
    let os = try addon("https://os.example", osManifest)
    let streams = try addon("https://aio.example", streamManifest)
    let movieOnly = try addon("https://other.example", otherSubsManifest)
    let http = FakeHTTP(routes: [
        "https://os.example/subtitles/series/tt9:1:2.json":
            #"{"subtitles":[{"id":"a","url":"https://s/1","lang":"ger"},{"id":"b","url":"https://s/1","lang":"ger"},{"id":"c","url":"https://s/2","lang":"eng"}]}"#,
        // Würde bei einer Abfrage auffallen: Stream- und Nur-Film-Addon dürfen nicht gefragt werden.
        "https://aio.example/subtitles/series/tt9:1:2.json": #"{"subtitles":[{"id":"z","url":"https://s/z","lang":"ger"}]}"#,
        "https://other.example/subtitles/series/tt9:1:2.json": #"{"subtitles":[{"id":"y","url":"https://s/y","lang":"ger"}]}"#,
    ])
    let subs = await AddonClient(http: http).subtitles(from: [streams, os, movieOnly], type: "series", id: "tt9:1:2")
    #expect(subs.map(\.id) == ["a", "c"])
    #expect(AddonClient.hasSubtitleAddon([streams, os]))
    #expect(!AddonClient.hasSubtitleAddon([streams]))
}

@Test func subtitlesIgnoreFailingAndSlowAddons() async throws {
    let os = try addon("https://os.example", osManifest)
    let failing = await AddonClient(http: FakeHTTP(routes: [:])).subtitles(from: [os], type: "movie", id: "tt1")
    #expect(failing.isEmpty)
    let start = Date()
    let slow = await AddonClient(http: SlowHTTP()).subtitles(from: [os], type: "movie", id: "tt1", timeout: 0.2)
    #expect(slow.isEmpty)
    #expect(Date().timeIntervalSince(start) < 3)
}

@Test func planLanguagesAndSelection() {
    #expect(AddonSubtitlePlan.languages(subtitleLanguage: "de", audioLanguage: "eng") == ["de", "en"])
    #expect(AddonSubtitlePlan.languages(subtitleLanguage: "ger", audioLanguage: "jpn") == ["de", "ja", "en"])
    #expect(AddonSubtitlePlan.languages(subtitleLanguage: "de", audioLanguage: nil) == ["de", "en"])
    let subs = (1...5).map { AddonSubtitle(id: "e\($0)", url: "https://s/e\($0)", lang: "eng", addonName: "OS") }
        + [AddonSubtitle(id: "f", url: "https://s/f", lang: "fre", addonName: "OS")]
        + (1...4).map { AddonSubtitle(id: "g\($0)", url: "https://s/g\($0)", lang: "ger", addonName: "OS") }
        + [AddonSubtitle(id: "dup", url: "https://s/g1", lang: "ger", addonName: "OS")]
    let picked = AddonSubtitlePlan.select(subs, languages: ["de", "en"])
    #expect(picked.map(\.id) == ["g1", "g2", "g3", "e1", "e2", "e3"])
}

@Test func planTrackNames() {
    #expect(AddonSubtitlePlan.displayAddonName("OpenSubtitles v3") == "OpenSubtitles")
    #expect(AddonSubtitlePlan.displayAddonName("Subsource") == "Subsource")
    #expect(AddonSubtitlePlan.displayAddonName("Addon v") == "Addon v")
    let s = [AddonSubtitle(id: "1", url: "u1", lang: "ger", addonName: "OpenSubtitles v3"),
             AddonSubtitle(id: "2", url: "u2", lang: "ger", addonName: "OpenSubtitles v3"),
             AddonSubtitle(id: "3", url: "u3", lang: "eng", addonName: "OpenSubtitles v3")]
    #expect(AddonSubtitlePlan.trackNames(s) == ["Deutsch · OpenSubtitles", "Deutsch · OpenSubtitles 2", "Englisch · OpenSubtitles"])
}

@Test func planAutoSelect() {
    let added = [AddonSubtitle(id: "e", url: "ue", lang: "eng", addonName: "OS"),
                 AddonSubtitle(id: "d", url: "ud", lang: "ger", addonName: "OS")]
    let engOnly = [AudioTrackInfo(id: 2, language: "eng", name: nil)]
    let gerForced = [AudioTrackInfo(id: 3, language: "ger", name: nil, isForced: true)]
    let gerFull = [AudioTrackInfo(id: 4, language: "deu", name: nil)]
    #expect(AddonSubtitlePlan.autoSelect(added, subtitlesWanted: true, wishLanguage: "de", embedded: engOnly)?.id == "d")
    #expect(AddonSubtitlePlan.autoSelect(added, subtitlesWanted: true, wishLanguage: "de", embedded: gerForced)?.id == "d")
    #expect(AddonSubtitlePlan.autoSelect(added, subtitlesWanted: true, wishLanguage: "de", embedded: gerFull) == nil)
    #expect(AddonSubtitlePlan.autoSelect(added, subtitlesWanted: false, wishLanguage: "de", embedded: engOnly) == nil)
    #expect(AddonSubtitlePlan.autoSelect(added, subtitlesWanted: true, wishLanguage: "fr", embedded: engOnly) == nil)
}
