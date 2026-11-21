import Foundation
import Testing
@testable import PlayerCore

@Test func personCreditsSortedDedupedCapped() async throws {
    let body = #"""
    {"id":7,"name":"Adam","biography":"","known_for_department":"Acting","profile_path":"/p.jpg",
     "combined_credits":{
       "cast":[
         {"id":1,"media_type":"movie","title":"Wenig","popularity":1.5,"poster_path":"/a.jpg"},
         {"id":2,"media_type":"tv","name":"Serie","popularity":9.0,"first_air_date":"2020-01-01"},
         {"id":3,"media_type":"movie","title":"Ohne Poster","popularity":5.0},
         {"id":2,"media_type":"tv","name":"Serie (Gast)","popularity":9.0}
       ],
       "crew":[
         {"id":1,"media_type":"movie","title":"Wenig","popularity":1.5,"job":"Producer"},
         {"id":2,"media_type":"movie","title":"Film mit gleicher Nummer","popularity":3.0}
       ]}}
    """#
    let http = RecordingHTTP(body)
    let p = try await TMDBClient(apiKey: "K", http: http).personCredits(id: 7)
    #expect(http.urls[0].path == "/3/person/7")
    #expect(http.urls[0].absoluteString.contains("append_to_response=combined_credits"))
    #expect(p.name == "Adam" && p.knownFor == "Acting")
    #expect(p.photo == "https://image.tmdb.org/t/p/w185/p.jpg")
    #expect(p.credits.map(\.name) == ["Serie", "Ohne Poster", "Film mit gleicher Nummer", "Wenig"])
    #expect(p.credits[0].type == "series" && p.credits[0].releaseInfo == "2020")
    #expect(p.credits[1].poster == nil)
    // Leere deutsche Biografie → englische nachgeholt (gleiche Testantwort, also wieder leer).
    #expect(http.urls.count == 2 && http.urls[1].absoluteString.contains("language=en-US"))
    #expect(p.biography == nil)
}

@Test func personCreditsMax60() throws {
    let cast = (1...80).map { #"{"id":\#($0),"media_type":"movie","title":"T\#($0)","popularity":\#($0)}"# }.joined(separator: ",")
    let p = try #require(TMDBClient.parsePerson(Data(#"{"id":1,"name":"X","combined_credits":{"cast":[\#(cast)]}}"#.utf8)))
    #expect(p.credits.count == 60 && p.credits.first?.name == "T80")
}

@Test func youtubePlayerPrefersHLS() throws {
    let json = #"""
    {"playabilityStatus":{"status":"OK"},
     "streamingData":{"hlsManifestUrl":"https://manifest.example/hls_playlist/index.m3u8",
       "formats":[{"itag":18,"mimeType":"video/mp4; codecs=\"avc1.42001E, mp4a.40.2\"","height":360,"url":"https://media.example/v18"}],
       "adaptiveFormats":[{"itag":137,"mimeType":"video/mp4","height":1080,"url":"https://media.example/v137"}]}}
    """#
    let r = YouTubeResolver.parsePlayer(Data(json.utf8), client: "visionos")
    #expect(r.status == "OK")
    #expect(r.hls?.url.absoluteString == "https://manifest.example/hls_playlist/index.m3u8" && r.hls?.isHLS == true)
    #expect(r.progressive.map(\.height) == [360])
    // Client-User-Agent muss mit: googlevideo-Adressen sind an den Client gebunden.
    let ua = try #require(YouTubeResolver.clients.first { $0.key == "visionos" }?.userAgent)
    #expect(r.hls?.headers == ["User-Agent": ua] && r.progressive.first?.headers == ["User-Agent": ua])
}

@Test func youtubeProgressiveSkipsCipherAndOver1080() throws {
    let json = #"""
    {"playabilityStatus":{"status":"OK"},
     "streamingData":{"formats":[
       {"itag":22,"mimeType":"video/mp4","qualityLabel":"720p","signatureCipher":"s=abc&url=https%3A%2F%2Fmedia.example"},
       {"itag":99,"mimeType":"video/mp4","height":2160,"url":"https://media.example/v99"},
       {"itag":43,"mimeType":"video/webm","height":360,"url":"https://media.example/v43"},
       {"itag":18,"mimeType":"video/mp4","qualityLabel":"360p","url":"https://media.example/v18"}]}}
    """#
    let r = YouTubeResolver.parsePlayer(Data(json.utf8), client: "android")
    #expect(r.hls == nil)
    #expect(r.progressive.map(\.url.absoluteString) == ["https://media.example/v18", "https://media.example/v43"])
}

@Test func youtubeNotPlayable() {
    let r = YouTubeResolver.parsePlayer(Data(#"{"playabilityStatus":{"status":"LOGIN_REQUIRED"}}"#.utf8), client: "ios")
    #expect(r.status == "LOGIN_REQUIRED" && r.hls == nil && r.progressive.isEmpty)
    #expect(YouTubeResolver.isVideoID("aqz-KE-bpKQ") && !YouTubeResolver.isVideoID("zu kurz"))
}

final class ScriptedPoster: HTTPPosting, @unchecked Sendable {
    var calls: [(URL, [String: String])] = []
    let answers: [String]
    init(_ answers: [String]) { self.answers = answers }
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> Data {
        calls.append((url, headers))
        return Data(answers[min(calls.count - 1, answers.count - 1)].utf8)
    }
}

@Test func youtubeResolveFallsBackToProgressive() async throws {
    let poster = ScriptedPoster([
        #"{"responseContext":{"visitorData":"Vis%3D%3D"}}"#,
        #"{"playabilityStatus":{"status":"LOGIN_REQUIRED"}}"#,
        #"{"playabilityStatus":{"status":"OK"},"streamingData":{"adaptiveFormats":[]}}"#,
        #"{"playabilityStatus":{"status":"OK"},"streamingData":{"formats":[{"mimeType":"video/mp4","height":360,"url":"https://media.example/v18"}]}}"#,
    ])
    let s = try #require(await YouTubeResolver(poster: poster).resolve(videoID: "aqz-KE-bpKQ"))
    #expect(s.client == "android" && !s.isHLS && s.height == 360)
    #expect(s.headers["User-Agent"]?.hasPrefix("com.google.android.youtube/") == true)
    #expect(poster.calls.count == 4)
    #expect(poster.calls[1].1["X-Goog-Visitor-Id"] == "Vis==")
    #expect(poster.calls[1].0.path == "/youtubei/v1/player")
}

@Test func youtubeResolveStopsWhenCancelled() async {
    let poster = ScriptedPoster([#"{"responseContext":{"visitorData":"V"}}"#])
    let t = Task { () -> YouTubeStream? in
        withUnsafeCurrentTask { $0?.cancel() }
        return await YouTubeResolver(poster: poster).resolve(videoID: "aqz-KE-bpKQ")
    }
    let s = await t.value
    #expect(s == nil && poster.calls.count <= 1)
}

@Test func textChunksSplitParagraphsAndLongOnes() {
    let s = String(repeating: "Ein Satz mit etwas Text. ", count: 40)   // ~1000 Zeichen
    let chunks = TextChunks.split("Kurz.\n\n" + s + "\nEnde!")
    #expect(chunks.first == "Kurz." && chunks.last == "Ende!")
    let mid = chunks.dropFirst().dropLast()
    #expect(mid.count >= 3 && mid.allSatisfy { $0.count <= 400 && $0.hasSuffix(".") })
    #expect(mid.joined(separator: " ") == s.trimmingCharacters(in: .whitespaces))
    #expect(TextChunks.split("") == [])
}
