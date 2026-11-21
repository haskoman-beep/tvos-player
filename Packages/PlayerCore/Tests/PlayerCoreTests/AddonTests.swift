import Foundation
import Testing
@testable import PlayerCore

struct FakeHTTP: HTTPFetching {
    var routes: [String: String]
    func data(from url: URL) async throws -> Data {
        guard let body = routes[url.absoluteString] else { throw AddonError.http(404) }
        return Data(body.utf8)
    }
}

let manifestJSON = """
{"id":"com.aio","name":"AIOStreams","version":"2.0.0","resources":["stream",{"name":"meta","types":["series"],"idPrefixes":["kitsu"]}],
 "types":["movie","series"],"idPrefixes":["tt"],"catalogs":[{"type":"movie","id":"top","name":"Top"}]}
"""

@Test func baseURLNormalisation() {
    #expect(AddonClient.baseURL(fromManifest: " https://a.b/x/manifest.json ") == "https://a.b/x")
    #expect(AddonClient.baseURL(fromManifest: "stremio://a.b/x/manifest.json") == "https://a.b/x")
    #expect(AddonClient.baseURL(fromManifest: "https://a.b/x/") == "https://a.b/x")
    #expect(AddonClient.baseURL(fromManifest: "ftp://a") == nil)
}

@Test func manifestDecodesMixedResources() throws {
    let m = try JSONDecoder().decode(AddonManifest.self, from: Data(manifestJSON.utf8))
    #expect(m.resources.map(\.name) == ["stream", "meta"])
    #expect(m.supports("stream", type: "movie", id: "tt123"))
    #expect(!m.supports("stream", type: "movie", id: "kitsu:1"))
    #expect(m.supports("meta", type: "series", id: "kitsu:1"))
    #expect(!m.supports("meta", type: "movie", id: "kitsu:1"))
    #expect(!m.supports("catalog", type: "movie", id: "tt1"))
}

@Test func installAndFetchStreams() async throws {
    let http = FakeHTTP(routes: [
        "https://aio.example/u/manifest.json": manifestJSON,
        "https://aio.example/u/stream/series/tt0903747:1:2.json":
            #"{"streams":[{"name":"[TB+] 2160p","description":"Breaking.Bad.S01E02.2160p.DV.TrueHD","url":"https://cdn/x.mkv","behaviorHints":{"bingeGroup":"aio|tb|2160p","videoSize":123}},{"name":"P2P","infoHash":"abc"}]}"#,
    ])
    let client = AddonClient(http: http)
    let addon = try await client.install(manifestURL: "https://aio.example/u/manifest.json")
    #expect(addon.baseURL == "https://aio.example/u")
    let s = try await client.streams(addon, type: "series", id: "tt0903747:1:2")
    #expect(s.count == 2)
    #expect(s[0].isPlayable && !s[1].isPlayable)
    #expect(s[0].behaviorHints?.bingeGroup == "aio|tb|2160p")
    #expect(s[0].label.contains("TrueHD"))
}

@Test func streamsFromManySkipsFailures() async throws {
    let m = try JSONDecoder().decode(AddonManifest.self, from: Data(manifestJSON.utf8))
    let ok = InstalledAddon(manifestURL: "https://ok/manifest.json", manifest: m)
    let broken = InstalledAddon(manifestURL: "https://broken/manifest.json", manifest: m)
    let http = FakeHTTP(routes: ["https://ok/stream/movie/tt1.json": #"{"streams":[{"url":"https://a/b.mkv"}]}"#])
    let r = await AddonClient(http: http).streams(from: [broken, ok], type: "movie", id: "tt1")
    #expect(r.count == 1 && r[0].addon.manifestURL == "https://ok/manifest.json")
}

@Test func catalogURLWithExtra() throws {
    let m = try JSONDecoder().decode(AddonManifest.self, from: Data(manifestJSON.utf8))
    let a = InstalledAddon(manifestURL: "https://x/manifest.json", manifest: m)
    let u = try AddonClient().resourceURL(a, "catalog", type: "movie", id: "top", extra: ["skip": "20", "genre": "Sci-Fi"])
    #expect(u.absoluteString == "https://x/catalog/movie/top/genre=Sci-Fi&skip=20.json")
}
