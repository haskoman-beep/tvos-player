import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import PlayerCore

// Task 2.3: one HTTP client with time limits and a size limit.

/// Fake transport: answers with fixed chunks and records the request it got.
private final class FakeTransport: HTTPByteTransport, @unchecked Sendable {
    let chunks: [Data]
    let contentLength: Int?
    let status: Int
    var lastRequest: URLRequest?
    var deliveredChunks = 0
    init(chunks: [Data], contentLength: Int? = nil, status: Int = 200) {
        self.chunks = chunks; self.contentLength = contentLength; self.status = status
    }
    func open(_ request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>) {
        lastRequest = request
        var headers: [String: String] = [:]
        if let contentLength { headers["Content-Length"] = String(contentLength) }
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        let chunks = self.chunks
        let stream = AsyncThrowingStream<Data, Error> { c in
            for ch in chunks { self.deliveredChunks += 1; c.yield(ch) }
            c.finish()
        }
        return (resp, stream)
    }
}

private let req = URLRequest(url: URL(string: "https://addon.example.com/catalog/movie/top.json")!)

@Test func httpLimitsPresets() {
    #expect(HTTPLimits.json.maxBytes == 8 * 1024 * 1024)
    #expect(HTTPLimits.image.maxBytes == 20 * 1024 * 1024)
    #expect(HTTPLimits.subtitle.maxBytes == 5 * 1024 * 1024)
    #expect(HTTPLimits.json.requestTimeout == 10)
    #expect(HTTPLimits.json.resourceTimeout == 20)
}

@Test func httpClientReturnsBodyUnderLimit() async throws {
    let t = FakeTransport(chunks: [Data("{\"a\":".utf8), Data("1}".utf8)])
    let (d, resp) = try await LimitedHTTPClient(transport: t).data(req, limits: HTTPLimits(maxBytes: 100), fresh: false)
    #expect(String(decoding: d, as: UTF8.self) == "{\"a\":1}")
    #expect(resp.statusCode == 200)
    #expect(t.lastRequest?.timeoutInterval == 10)
}

@Test func httpClientAbortsWhenStreamExceedsMaxBytes() async {
    let t = FakeTransport(chunks: [Data(count: 60), Data(count: 60), Data(count: 60)])
    await #expect(throws: HTTPClientError.tooLarge(limit: 100)) {
        _ = try await LimitedHTTPClient(transport: t).data(req, limits: HTTPLimits(maxBytes: 100), fresh: false)
    }
}

@Test func httpClientRejectsDeclaredContentLengthOverLimit() async {
    let t = FakeTransport(chunks: [Data(count: 10)], contentLength: 300 * 1024 * 1024)
    await #expect(throws: HTTPClientError.tooLarge(limit: HTTPLimits.image.maxBytes)) {
        _ = try await LimitedHTTPClient(transport: t).data(req, limits: .image, fresh: false)
    }
}

@Test func httpClientFreshIgnoresLocalCache() async throws {
    let t = FakeTransport(chunks: [Data("x".utf8)])
    let c = LimitedHTTPClient(transport: t)
    _ = try await c.data(req, limits: .json, fresh: true)
    #expect(t.lastRequest?.cachePolicy == .reloadIgnoringLocalCacheData)
    _ = try await c.data(req, limits: .json, fresh: false)
    #expect(t.lastRequest?.cachePolicy == .useProtocolCachePolicy)
}

@Test func httpFetcherUsesClientAndChecksStatus() async throws {
    let ok = HTTPClientFetcher(client: LimitedHTTPClient(transport: FakeTransport(chunks: [Data("{}".utf8)])))
    #expect(try await ok.data(from: req.url!) == Data("{}".utf8))
    let bad = HTTPClientFetcher(client: LimitedHTTPClient(transport: FakeTransport(chunks: [], status: 503)))
    await #expect(throws: AddonError.http(503)) { _ = try await bad.data(from: req.url!) }
}

@Test func addonListsAreCappedAfterDecoding() {
    #expect(AddonListCaps.catalog == 500)
    #expect(AddonListCaps.streams == 2000)
    #expect(AddonListCaps.cap(Array(0..<2500), AddonListCaps.streams).count == 2000)
    #expect(AddonListCaps.cap([1, 2, 3], AddonListCaps.catalog) == [1, 2, 3])
}

@Test func addonClientCapsCatalogAndStreams() async throws {
    let metas = (0..<600).map { "{\"id\":\"tt\($0)\",\"type\":\"movie\",\"name\":\"N\($0)\"}" }.joined(separator: ",")
    let streams = (0..<2100).map { "{\"url\":\"https://cdn.example.com/\($0).mkv\"}" }.joined(separator: ",")
    let http = FakeHTTP(routes: [
        "https://a.example.com/manifest.json": manifestJSON,
        "https://a.example.com/catalog/movie/top.json": "{\"metas\":[\(metas)]}",
        "https://a.example.com/stream/movie/tt1.json": "{\"streams\":[\(streams)]}",
    ])
    let c = AddonClient(http: http)
    let a = try await c.install(manifestURL: "https://a.example.com/manifest.json")
    #expect(try await c.catalog(a, type: "movie", id: "top").count == 500)
    #expect(try await c.streams(a, type: "movie", id: "tt1").count == 2000)
}

@Test func urlSessionSenderGoesThroughClientUncached() async throws {
    let t = FakeTransport(chunks: [Data("{}".utf8)], status: 201)
    let r = try await URLSessionSender(client: LimitedHTTPClient(transport: t))
        .sendFull(APIRequest(method: "POST", url: URL(string: "https://api.example.com/x")!, headers: ["A": "b"]))
    #expect(r.status == 201)
    #expect(t.lastRequest?.cachePolicy == .reloadIgnoringLocalCacheData)
    #expect(t.lastRequest?.httpMethod == "POST")
    #expect(t.lastRequest?.value(forHTTPHeaderField: "A") == "b")
}

// Fix round 1

/// Records the limits the addon client asks for.
private final class LimitRecordingHTTP: HTTPFetching, @unchecked Sendable {
    var limits: [HTTPLimits] = []
    let routes: [String: String]
    init(routes: [String: String]) { self.routes = routes }
    func data(from url: URL) async throws -> Data { try await data(from: url, limits: .json) }
    func data(from url: URL, limits: HTTPLimits) async throws -> Data {
        self.limits.append(limits)
        guard let b = routes[url.absoluteString] else { throw AddonError.http(404) }
        return Data(b.utf8)
    }
}

@Test func addonLimitsStayAboveTheProfileTimeout() {
    for t in AddonSearch.timeoutChoices {
        let l = HTTPLimits.addon(timeout: t)
        #expect(l.requestTimeout > t)
        #expect(l.resourceTimeout >= t + HTTPLimits.addonMargin)
        #expect(l.maxBytes == HTTPLimits.json.maxBytes)
    }
}

@Test func addonStreamSearchUsesProfileTimeoutForRequests() async throws {
    let http = LimitRecordingHTTP(routes: [
        "https://a.example.com/manifest.json": manifestJSON,
        "https://a.example.com/stream/movie/tt1.json": #"{"streams":[{"url":"https://cdn.example.com/1.mkv"}]}"#,
    ])
    let c = AddonClient(http: http)
    let a = try await c.install(manifestURL: "https://a.example.com/manifest.json")
    #expect(http.limits.last!.requestTimeout >= 45)   // no profile timeout: longest choice
    _ = await c.streams(from: [a], type: "movie", id: "tt1", timeout: 30) { _ in }
    #expect(http.limits.last!.requestTimeout >= 30)
    #expect(http.limits.last!.resourceTimeout >= 35)
    // The request built by the client carries it as timeoutInterval.
    let r = LimitedHTTPClient.prepared(req, limits: http.limits.last!, fresh: false)
    #expect(r.timeoutInterval >= 30)
}

/// A body that never ends (one chunk, then silence).
private struct HangingTransport: HTTPByteTransport {
    func open(_ request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>) {
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        return (resp, AsyncThrowingStream { c in c.yield(Data("{\"part".utf8)) })
    }
}

@Test func httpClientCancelledMidBodyThrows() async {
    let t = Task { try await LimitedHTTPClient(transport: HangingTransport()).data(req, limits: .json, fresh: false) }
    try? await Task.sleep(nanoseconds: 50_000_000)
    t.cancel()
    let r = await t.result
    switch r {
    case .success: Issue.record("truncated body returned as success")
    case .failure(let e): #expect(e is CancellationError)
    }
}

@Test func httpClientRejectsBodyShorterThanContentLength() async {
    let t = FakeTransport(chunks: [Data(count: 10)], contentLength: 50)
    await #expect(throws: HTTPClientError.incomplete) {
        _ = try await LimitedHTTPClient(transport: t).data(req, limits: .json, fresh: false)
    }
}

@Test func httpClientKeepsCallerCachePolicyWhenNotFresh() async throws {
    let t = FakeTransport(chunks: [Data("x".utf8)])
    _ = try await LimitedHTTPClient(transport: t)
        .data(URLRequest(url: req.url!, cachePolicy: .returnCacheDataElseLoad), limits: .image, fresh: false)
    #expect(t.lastRequest?.cachePolicy == .returnCacheDataElseLoad)
}

@Test func httpClientTimesOutAfterResourceTimeout() async {
    let limits = HTTPLimits(requestTimeout: 1, resourceTimeout: 0.1, maxBytes: 100)
    await #expect(throws: HTTPClientError.timedOut) {
        _ = try await LimitedHTTPClient(transport: HangingTransport()).data(req, limits: limits, fresh: false)
    }
}

@Test func httpClientErrorsHaveReadableMessages() {
    #expect(AddonSearch.describe(HTTPClientError.timedOut) == "Zeitüberschreitung")
    #expect(AddonSearch.describe(HTTPClientError.tooLarge(limit: 1)) == "Antwort zu groß")
    #expect(TorBoxClient.userMessage(HTTPClientError.timedOut) == "TorBox antwortet nicht (Zeitüberschreitung)")
}
