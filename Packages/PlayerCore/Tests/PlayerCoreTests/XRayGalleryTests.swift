import Foundation
import Testing
@testable import PlayerCore

// Wave X3: TMDB credits and portraits for the gallery, and the background precompute with a fake embedder.

/// Answers by URL path; a path in `fails` throws HTTP 404, one in `broken` HTTP 500, one in `limitedOnce`
/// throws 429 the first time.
final class XRayHTTP: HTTPFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [URL] = []
    private var limited: Set<String>
    let bodies: [String: String]
    let fails: Set<String>
    let broken: Set<String>
    init(_ bodies: [String: String], fails: Set<String> = [], broken: Set<String> = [], limitedOnce: Set<String> = []) {
        self.bodies = bodies; self.fails = fails; self.broken = broken; self.limited = limitedOnce
    }
    var urls: [URL] { lock.lock(); defer { lock.unlock() }; return log }
    var paths: [String] { urls.map(\.path) }
    func data(from url: URL) async throws -> Data {
        let first = lock.withLock { () -> Bool in
            log.append(url)
            return limited.remove(url.path) != nil
        }
        if first { throw AddonError.http(429) }
        if broken.contains(url.path) { throw AddonError.http(500) }
        guard !fails.contains(url.path), let b = bodies[url.path] else { throw AddonError.http(404) }
        return Data(b.utf8)
    }
}

/// Picture bytes are a text naming the faces: "w=120:1,0,0|w=30:0,1,0" (width, then embedding); "bad" throws,
/// and `failAll` throws for every picture (model not loaded). `onCall` runs before each picture.
struct FakeFaceEmbedder: FaceEmbedder {
    var modelID = "fake-1"
    var cancelOn: String? = nil
    var failAll = false
    var onCall: (@Sendable () async -> Void)? = nil
    struct Failed: Error {}
    func faces(inImage data: Data) async throws -> [EmbeddedFace] {
        await onCall?()
        let s = String(decoding: data, as: UTF8.self)
        if s == cancelOn { withUnsafeCurrentTask { $0?.cancel() } }
        if failAll || s == "bad" { throw Failed() }
        if s.isEmpty { return [] }
        return s.split(separator: "|").map { part in
            let bits = part.split(separator: ":")
            let w = Double(bits[0].dropFirst(2))!
            let v = bits[1].split(separator: ",").map { Float($0)! }
            return EmbeddedFace(face: DetectedFace(width: w), embedding: FaceEmbedding(v)!)
        }
    }
}

private final class XRaySleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var s: [Double] = []
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return s }
    var sleep: APISleep { { [self] v in lock.withLock { s.append(v) } } }
}

// MARK: TMDB

@Test func movieCastIsCompleteAndInBillingOrder() async throws {
    let rows = (0..<30).reversed().map { #"{"id":\#($0 + 1),"name":"P\#($0)","character":"R\#($0)","order":\#($0),"profile_path":"/p\#($0).jpg"}"# }
    let http = XRayHTTP(["/3/movie/5/credits": #"{"cast":[\#(rows.joined(separator: ",")),{"id":1,"name":"Dup","order":99}]}"#])
    let cast = try await TMDBClient(apiKey: "K", http: http).xrayCast(for: .movie(tmdbID: 5))
    #expect(cast.count == 30)   // no 20-person cut, duplicate dropped
    #expect(cast.first == XRayCastEntry(personID: 1, name: "P0", role: "R0", profilePath: "/p0.jpg", order: 0))
    #expect(cast.map(\.order) == Array(0..<30))
}

@Test func episodeCastPutsEpisodeAndGuestsBeforeSeries() async throws {
    let http = XRayHTTP([
        "/3/tv/7/season/1/episode/2/credits": #"""
        {"cast":[{"id":2,"name":"Reg B","character":"B","order":1},{"id":1,"name":"Reg A","character":"A","order":0}],
         "guest_stars":[{"id":9,"name":"Gast","character":"Bote","order":0},{"id":1,"name":"Reg A","order":5}]}
        """#,
        "/3/tv/7/aggregate_credits": #"""
        {"cast":[{"id":1,"name":"Reg A","roles":[{"character":"A"}],"order":0},
                 {"id":3,"name":"Reg C","roles":[{"character":""},{"character":"C"}],"order":2},
                 {"id":2,"name":"Reg B","roles":[],"order":1}]}
        """#,
    ])
    let cast = try await TMDBClient(apiKey: "K", http: http).xrayCast(for: .episode(tvID: 7, season: 1, episode: 2))
    #expect(cast.map(\.personID) == [1, 2, 9, 3])
    #expect(cast.map(\.guest) == [false, false, true, false])
    #expect(cast[3].role == "C" && cast.map(\.order) == [0, 1, 2, 3])
    #expect(http.urls.allSatisfy { $0.absoluteString.contains("api_key=K") })
}

@Test func episodeCastFallsBackToSeriesWhenEpisodeFails() async throws {
    let http = XRayHTTP(["/3/tv/7/aggregate_credits": #"{"cast":[{"id":3,"name":"C","order":0}]}"#])
    let cast = try await TMDBClient(apiKey: "K", http: http).xrayCast(for: .episode(tvID: 7, season: 9, episode: 9))
    #expect(cast.map(\.personID) == [3])
    let none = XRayHTTP([:])
    await #expect(throws: AddonError.self) {
        try await TMDBClient(apiKey: "K", http: none).xrayCast(for: .episode(tvID: 7, season: 1, episode: 1))
    }
}

@Test func personImagesSortedByRating() async throws {
    let http = XRayHTTP(["/3/person/4/images": #"""
    {"id":4,"profiles":[{"file_path":"/low.jpg","vote_average":1.2,"vote_count":3,"width":400,"height":600},
      {"file_path":"/top.jpg","vote_average":5.4,"vote_count":10,"width":800,"height":1200},
      {"file_path":"/tie.jpg","vote_average":5.4,"vote_count":12,"height":200},
      {"file_path":"","vote_average":9}, {"file_path":"/zero.jpg","vote_average":0}]}
    """#])
    let imgs = try await TMDBClient(apiKey: "K", http: http).personImages(id: 4)
    #expect(imgs.map(\.filePath) == ["/tie.jpg", "/top.jpg", "/low.jpg", "/zero.jpg"])
    let picked = XRayGalleryPlan.pickImages(imgs, settings: XRayGallerySettings(imagesPerPerson: 2))
    #expect(picked.map(\.filePath) == ["/top.jpg", "/low.jpg"])   // /tie.jpg is only 200 high
    #expect(TMDBClient.galleryImageURL("/top.jpg")?.absoluteString == "https://image.tmdb.org/t/p/h632/top.jpg")
}

// MARK: Plan

@Test func portraitNeedsExactlyOneClearFace() {
    let s = XRayGallerySettings()
    let e = FaceEmbedding([1, 0])!
    func f(_ w: Double) -> EmbeddedFace { EmbeddedFace(face: DetectedFace(width: w), embedding: e) }
    #expect(XRayGalleryPlan.portraitFace([f(200), f(40)], settings: s)?.face.width == 200)
    #expect(XRayGalleryPlan.portraitFace([f(200), f(120)], settings: s) == nil)   // group photo
    #expect(XRayGalleryPlan.portraitFace([f(30)], settings: s) == nil)            // too small
    #expect(XRayGalleryPlan.portraitFace([], settings: s) == nil)
}

@Test func throttleSpacesRequests() async {
    let sleeps = XRaySleepLog()
    let t0 = Date(timeIntervalSince1970: 0)
    let th = RequestThrottle(limit: 2, window: 1, now: { t0 }, sleep: sleeps.sleep)
    for _ in 0..<4 { await th.wait() }
    #expect(sleeps.values == [1, 1])
}

// MARK: Precompute

private let movieCredits = #"""
{"cast":[{"id":1,"name":"A","order":0,"profile_path":"/a0.jpg"},{"id":2,"name":"B","order":1,"profile_path":"/b0.jpg"},
         {"id":3,"name":"C","order":2}]}
"""#

private func galleryHTTP(fails: Set<String> = [], broken: Set<String> = [], limitedOnce: Set<String> = []) -> XRayHTTP {
    XRayHTTP([
        "/3/movie/5/credits": movieCredits,
        "/3/person/1/images": #"{"profiles":[{"file_path":"/a1.jpg","vote_average":5},{"file_path":"/a2.jpg","vote_average":4},{"file_path":"/a3.jpg","vote_average":3},{"file_path":"/a4.jpg","vote_average":2}]}"#,
        "/3/person/2/images": #"{"profiles":[]}"#,
        "/3/person/3/images": #"{"profiles":[{"file_path":"/c1.jpg","vote_average":1}]}"#,
        "/t/p/h632/a1.jpg": "w=180:1,0,0",
        "/t/p/h632/a2.jpg": "w=150:0.9,0.1,0|w=20:0,1,0",
        "/t/p/h632/a3.jpg": "w=150:1,0,0|w=140:0,0,1",   // two people: discarded
        "/t/p/h632/a4.jpg": "",
        "/t/p/h632/b0.jpg": "w=90:0,1,0",
        "/t/p/h632/c1.jpg": "",
    ], fails: fails, broken: broken, limitedOnce: limitedOnce)
}

private func builder(_ http: XRayHTTP, store: XRayStore, embedder: FakeFaceEmbedder = FakeFaceEmbedder(),
                     settings: XRayGallerySettings = XRayGallerySettings(), sleeps: XRaySleepLog = XRaySleepLog(),
                     log: (@Sendable (String) -> Void)? = nil) -> XRayGalleryBuilder {
    XRayGalleryBuilder(tmdb: TMDBClient(apiKey: "K", http: http), images: http, embedder: embedder, store: store,
                       throttle: RequestThrottle(limit: 1000, window: 1, sleep: sleeps.sleep),
                       settings: settings, sleep: sleeps.sleep, log: log)
}

final class LineLog: @unchecked Sendable {
    private let lock = NSLock()
    private var l: [String] = []
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return l }
    func add(_ s: String) { lock.lock(); l.append(s); lock.unlock() }
}

@Test func prepareBuildsAndCachesGallery() async throws {
    let http = galleryHTTP(), clock = XRayClock()
    let store = XRayStore(storage: XRayMemoryBlobs(), now: { clock.now })
    let lines = LineLog()
    let b = builder(http, store: store, log: lines.add)
    let key = XRayTitleKey.movie(tmdbID: 5)
    let r = await b.prepare(key)
    #expect(r.people == 3 && r.computed == 3 && r.cached == 0 && r.usable == 2)
    #expect(r.downloads == 6 && r.discarded == 3 && r.failures == 0 && !r.cancelled && !r.castFromCache)
    #expect(lines.lines == [r.logLine] && r.logLine.hasPrefix("xray: gallery m5 people=3"))

    let a = try #require(await store.person(1, model: "fake-1"))
    #expect(a.faces.map(\.filePath) == ["/a1.jpg", "/a2.jpg"])
    // Person 2 has no portraits listed: the credit's own picture is used.
    #expect(await store.person(2, model: "fake-1")?.faces.map(\.filePath) == ["/b0.jpg"])
    #expect(await store.person(3, model: "fake-1")?.faces == [])
    let g = await b.gallery(for: key)
    #expect(g.map(\.personID) == [1, 2] && g[0].embeddings.count == 2)

    // The gallery matches a face from the paused picture.
    let probe = FaceEmbedding([0.95, 0.05, 0.1])!
    #expect(FaceMatcher.decide(probe, gallery: g, config: .sface).personID == 1)

    // Second run: all from the cache, no network.
    let before = http.urls.count
    let again = await b.prepare(key)
    #expect(again.cached == 3 && again.computed == 0 && again.castFromCache && http.urls.count == before)

    // A new model recomputes the embeddings but keeps the cast list.
    let other = builder(http, store: store, embedder: FakeFaceEmbedder(modelID: "fake-2"))
    let r2 = await other.prepare(key)
    #expect(r2.castFromCache && r2.computed == 3)
}

@Test func prepareRespectsMaxPeople() async {
    let http = galleryHTTP()
    let b = builder(http, store: XRayStore(storage: XRayMemoryBlobs()), settings: XRayGallerySettings(maxPeople: 1))
    let r = await b.prepare(.movie(tmdbID: 5))
    #expect(r.people == 1 && r.computed == 1)
    #expect(!http.paths.contains("/3/person/2/images"))
}

@Test func failedPersonIsRetriedNextRun() async {
    let store = XRayStore(storage: XRayMemoryBlobs())
    let first = await builder(galleryHTTP(fails: ["/3/person/1/images", "/t/p/h632/b0.jpg"]), store: store).prepare(.movie(tmdbID: 5))
    #expect(first.failures == 2 && first.computed == 1)   // only C finished (with no face)
    #expect(await store.person(1, model: "fake-1") == nil)
    #expect(await store.person(2, model: "fake-1") == nil)
    let second = await builder(galleryHTTP(), store: store).prepare(.movie(tmdbID: 5))
    #expect(second.computed == 2 && second.cached == 1 && second.usable == 2)
}

@Test func rateLimitIsRetriedOnceAfterPause() async {
    let sleeps = XRaySleepLog()
    let http = galleryHTTP(limitedOnce: ["/3/movie/5/credits", "/t/p/h632/a1.jpg"])
    let r = await builder(http, store: XRayStore(storage: XRayMemoryBlobs()), sleeps: sleeps).prepare(.movie(tmdbID: 5))
    #expect(r.failures == 0 && r.usable == 2)
    #expect(sleeps.values == [XRayGalleryBuilder.rateLimitPause, XRayGalleryBuilder.rateLimitPause])
    #expect(http.paths.filter { $0 == "/3/movie/5/credits" }.count == 2)
}

@Test func cancelledRunCachesNothingHalfDone() async {
    let store = XRayStore(storage: XRayMemoryBlobs())
    let http = galleryHTTP()
    let b = builder(http, store: store, embedder: FakeFaceEmbedder(cancelOn: "w=150:0.9,0.1,0|w=20:0,1,0"))
    let r = await Task { await b.prepare(.movie(tmdbID: 5)) }.value
    #expect(r.cancelled && r.computed == 0)
    #expect(await store.person(1, model: "fake-1") == nil)
    #expect(!http.paths.contains("/3/person/2/images"))
    // The cast list was finished and stays cached.
    #expect(await store.title(.movie(tmdbID: 5)) != nil)
}

@Test func castFailureIsReportedNotThrown() async {
    let r = await builder(XRayHTTP([:]), store: XRayStore(storage: XRayMemoryBlobs())).prepare(.movie(tmdbID: 5))
    #expect(r.failures == 1 && r.people == 0)
}

// MARK: Round 1 (review X2: I1, I2, m7, m9)

private let episodeBodies = [
    "/3/tv/7/season/1/episode/2/credits": #"{"cast":[{"id":1,"name":"A","order":0}],"guest_stars":[{"id":9,"name":"Gast","order":0}]}"#,
    "/3/tv/7/aggregate_credits": #"{"cast":[{"id":1,"name":"A","order":0},{"id":3,"name":"C","order":1}]}"#,
]

@Test func transientEpisodeCreditErrorsAreNotSwallowed() async throws {
    let key = XRayTitleKey.episode(tvID: 7, season: 1, episode: 2)
    for path in episodeBodies.keys {
        // 500 on either half: no degraded list, the error goes on.
        await #expect(throws: AddonError.http(500)) {
            try await TMDBClient(apiKey: "K", http: XRayHTTP(episodeBodies, broken: [path])).xrayCast(for: key)
        }
        // In the builder: reported as failure, nothing cached, the next run gets the full list.
        let store = XRayStore(storage: XRayMemoryBlobs())
        let r = await builder(XRayHTTP(episodeBodies, broken: [path]), store: store).prepare(key)
        #expect(r.failures == 1 && r.people == 0)
        #expect(await store.title(key) == nil)
        _ = await builder(XRayHTTP(episodeBodies), store: store).prepare(key)
        #expect(await store.title(key)?.cast.map(\.personID) == [1, 9, 3])
    }
}

@Test func rateLimitOnEpisodeCreditsIsRetriedPerRequest() async throws {
    let key = XRayTitleKey.episode(tvID: 7, season: 1, episode: 2)
    let sleeps = XRaySleepLog()
    let http = XRayHTTP(episodeBodies, limitedOnce: Set(episodeBodies.keys))
    let store = XRayStore(storage: XRayMemoryBlobs())
    let r = await builder(http, store: store, sleeps: sleeps).prepare(key)
    #expect(!r.castFromCache && r.people == 3)
    #expect(sleeps.values == [XRayGalleryBuilder.rateLimitPause, XRayGalleryBuilder.rateLimitPause])
    #expect(await store.title(key)?.cast.map(\.personID) == [1, 9, 3])
}

@Test func embedderFailureIsNotCachedAsNoFace() async {
    let store = XRayStore(storage: XRayMemoryBlobs())
    let r = await builder(galleryHTTP(), store: store, embedder: FakeFaceEmbedder(failAll: true)).prepare(.movie(tmdbID: 5))
    #expect(r.computed == 0 && r.usable == 0 && r.failures == 6 && r.discarded == 0)
    for id in 1...3 { #expect(await store.person(id, model: "fake-1") == nil) }
    let again = await builder(galleryHTTP(), store: store).prepare(.movie(tmdbID: 5))
    #expect(again.computed == 3 && again.usable == 2)
}

@Test func partlyFailedPersonIsKeptOnlyOneDay() async throws {
    let clock = XRayClock()
    let store = XRayStore(storage: XRayMemoryBlobs(), now: { clock.now })
    let r = await builder(galleryHTTP(broken: ["/t/p/h632/a2.jpg"]), store: store).prepare(.movie(tmdbID: 5))
    #expect(r.partial == 1 && r.failures == 1 && r.usable == 2)
    let a = try #require(await store.person(1, model: "fake-1"))
    #expect(a.partial && a.faces.map(\.filePath) == ["/a1.jpg"])
    clock.advance(25 * 3600)
    #expect(await store.person(1, model: "fake-1") == nil)
    #expect(await store.person(2, model: "fake-1") != nil)
}

private final class BuilderBox: @unchecked Sendable {
    var builder: XRayGalleryBuilder?
    var nested: [XRayPrepareReport] = []
}

@Test func secondPrepareOfSameTitleReturnsAtOnce() async {
    let box = BuilderBox()
    let store = XRayStore(storage: XRayMemoryBlobs())
    let embedder = FakeFaceEmbedder(onCall: {
        guard box.nested.isEmpty, let b = box.builder else { return }
        box.nested.append(await b.prepare(.movie(tmdbID: 5)))
    })
    let b = builder(galleryHTTP(), store: store, embedder: embedder)
    box.builder = b
    let r = await b.prepare(.movie(tmdbID: 5))
    #expect(box.nested.count == 1 && box.nested[0].alreadyRunning && box.nested[0].people == 0)
    #expect(!r.alreadyRunning && r.computed == 3)
    #expect(box.nested[0].logLine.hasSuffix("already-running"))
}
