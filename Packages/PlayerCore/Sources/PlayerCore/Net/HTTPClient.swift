import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Task 2.3: limits for one request. `requestTimeout` = idle time without data, `resourceTimeout` = whole request.
public struct HTTPLimits: Sendable, Equatable {
    public var requestTimeout: TimeInterval = 10
    public var resourceTimeout: TimeInterval = 20
    public var maxBytes: Int

    public init(requestTimeout: TimeInterval = 10, resourceTimeout: TimeInterval = 20, maxBytes: Int) {
        self.requestTimeout = requestTimeout; self.resourceTimeout = resourceTimeout; self.maxBytes = maxBytes
    }

    public static let json = HTTPLimits(maxBytes: 8 * 1024 * 1024)
    public static let image = HTTPLimits(maxBytes: 20 * 1024 * 1024)
    public static let subtitle = HTTPLimits(maxBytes: 5 * 1024 * 1024)

    /// Fix round 1: addon calls (streams, catalogs, meta) wait as long as the profile's addon timeout allows.
    /// Aggregator addons often send nothing until the whole answer is ready, so both limits sit above `timeout`
    /// (the caller's own deadline, e.g. `AddonSearch.withDeadline`, ends the wait first).
    public static let addonMargin: TimeInterval = 5
    public static func addon(timeout: TimeInterval) -> HTTPLimits {
        let t = max(timeout, HTTPLimits.json.requestTimeout)
        return HTTPLimits(requestTimeout: t + addonMargin, resourceTimeout: t + 2 * addonMargin, maxBytes: json.maxBytes)
    }
}

public enum HTTPClientError: Error, Equatable {
    /// The body (declared or received) is larger than `maxBytes`; the transfer was stopped.
    case tooLarge(limit: Int)
    /// `resourceTimeout` passed before the body was complete.
    case timedOut
    /// The body ended before the declared Content-Length (connection lost).
    case incomplete
}

/// Task 2.3: the one way to fetch data. Callers check the status code themselves.
public protocol HTTPClient: Sendable {
    func data(_ request: URLRequest, limits: HTTPLimits, fresh: Bool) async throws -> (Data, HTTPURLResponse)
}

/// Opens a request and delivers the body in chunks (replaceable in tests).
public protocol HTTPByteTransport: Sendable {
    func open(_ request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>)
}

/// Applies the limits on top of a transport: timeouts, cache rule, size limit (declared length and while reading).
public struct LimitedHTTPClient: HTTPClient {
    let transport: HTTPByteTransport

    public init(transport: HTTPByteTransport = URLSessionByteTransport.shared) { self.transport = transport }

    /// The shared client of the app.
    public static let shared = LimitedHTTPClient()
    /// Task 3.10: on the ephemeral transport (nothing cached, no cookies).
    public static let ephemeral = LimitedHTTPClient(transport: URLSessionByteTransport.ephemeral)

    static func prepared(_ request: URLRequest, limits: HTTPLimits, fresh: Bool) -> URLRequest {
        var r = request
        r.timeoutInterval = limits.requestTimeout
        // Not fresh: keep the caller's rule (e.g. the image pipeline's returnCacheDataElseLoad).
        if fresh { r.cachePolicy = .reloadIgnoringLocalCacheData }
        return r
    }

    public func data(_ request: URLRequest, limits: HTTPLimits, fresh: Bool) async throws -> (Data, HTTPURLResponse) {
        try await run(request, limits: limits, fresh: fresh, prefixOnly: false)
    }

    /// Task 3.10: the first `limits.maxBytes` bytes of the body, without `tooLarge` (Range probes: a server that
    /// ignores the Range header is not read further). Time limits and the cut-body check stay as in `data`.
    public func prefix(_ request: URLRequest, limits: HTTPLimits, fresh: Bool) async throws -> (Data, HTTPURLResponse) {
        try await run(request, limits: limits, fresh: fresh, prefixOnly: true)
    }

    func run(_ request: URLRequest, limits: HTTPLimits, fresh: Bool, prefixOnly: Bool) async throws -> (Data, HTTPURLResponse) {
        let r = Self.prepared(request, limits: limits, fresh: fresh)
        let transport = self.transport
        return try await withThrowingTaskGroup(of: (Data, HTTPURLResponse)?.self) { group in
            group.addTask { try await Self.read(r, transport: transport, maxBytes: limits.maxBytes, prefixOnly: prefixOnly) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, limits.resourceTimeout) * 1_000_000_000))
                return nil
            }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let result = first else { throw HTTPClientError.timedOut }
            return result
        }
    }

    /// Fewer bytes than the declared length (only checkable without Content-Encoding: compressed lengths differ).
    static func isIncomplete(_ received: Int, _ resp: HTTPURLResponse) -> Bool {
        let declared = resp.expectedContentLength
        guard declared >= 0 else { return false }
        let enc = (resp.value(forHTTPHeaderField: "Content-Encoding") ?? "identity").lowercased()
        guard enc.isEmpty || enc == "identity" else { return false }
        return Int64(received) < declared
    }

    static func read(_ r: URLRequest, transport: HTTPByteTransport, maxBytes: Int,
                     prefixOnly: Bool = false) async throws -> (Data, HTTPURLResponse) {
        let (resp, stream) = try await transport.open(r)
        if !prefixOnly, resp.expectedContentLength > Int64(maxBytes) { throw HTTPClientError.tooLarge(limit: maxBytes) }
        var out = Data()
        for try await chunk in stream {
            if out.count + chunk.count > maxBytes {
                guard prefixOnly else { throw HTTPClientError.tooLarge(limit: maxBytes) }
                // Prefix read: keep exactly maxBytes and stop (leaving the loop drops the stream, which ends the download).
                out.append(chunk.prefix(maxBytes - out.count))
                try Task.checkCancellation()
                return (out, resp)
            }
            out.append(chunk)
            try Task.checkCancellation()
            if prefixOnly, out.count == maxBytes { return (out, resp) }
        }
        // Fix round 1: a cancelled caller ends the stream without an error; never return that partial body.
        try Task.checkCancellation()
        if isIncomplete(out.count, resp) { throw HTTPClientError.incomplete }
        return (out, resp)
    }
}

/// URLSession transport. On Apple platforms it reads via `bytes(for:)` so a too-large body stops early.
public struct URLSessionByteTransport: HTTPByteTransport {
    let session: URLSession
    public init(session: URLSession) { self.session = session }

    public static let shared: URLSessionByteTransport = {
        let cfg = URLSessionConfiguration.default
        // Fix round 1: high so each request's own timeoutInterval (from its HTTPLimits) governs.
        cfg.timeoutIntervalForRequest = 60
        // Outer bound only; the per-request resourceTimeout is enforced by LimitedHTTPClient.
        cfg.timeoutIntervalForResource = 60
        return URLSessionByteTransport(session: URLSession(configuration: cfg))
    }()

    /// Task 3.10: no cache, no cookies (collection links, Range probes). Same outer bounds as `shared`.
    public static let ephemeral: URLSessionByteTransport = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.urlCache = nil
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 60
        return URLSessionByteTransport(session: URLSession(configuration: cfg))
    }()

    static let chunkSize = 64 * 1024

    public func open(_ request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>) {
        #if canImport(FoundationNetworking)
        // Linux (tests only): no bytes(for:); the whole body arrives at once and is checked afterwards.
        let (d, resp) = try await session.data(for: request)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (http, AsyncThrowingStream { c in c.yield(d); c.finish() })
        #else
        // Everything non-Sendable (AsyncBytes) lives inside one reader task; the response comes back through a
        // continuation, the body through the stream. Dropping the stream (limit hit) or cancelling stops the task.
        let session = self.session, size = Self.chunkSize
        let (stream, c) = AsyncThrowingStream<Data, Error>.makeStream()
        let box = ReaderBox()
        let http: HTTPURLResponse = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (rc: CheckedContinuation<HTTPURLResponse, Error>) in
                let t = Task {
                    var answered = false
                    do {
                        let (bytes, resp) = try await session.bytes(for: request)
                        guard let httpResp = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                        answered = true
                        rc.resume(returning: httpResp)
                        var buf = Data(); buf.reserveCapacity(size)
                        for try await b in bytes {
                            buf.append(b)
                            if buf.count >= size { c.yield(buf); buf = Data(); buf.reserveCapacity(size) }
                        }
                        if !buf.isEmpty { c.yield(buf) }
                        c.finish()
                    } catch {
                        if answered { c.finish(throwing: error) } else { rc.resume(throwing: error); c.finish() }
                    }
                }
                box.set(t)
                c.onTermination = { _ in t.cancel() }
            }
        } onCancel: { box.cancel() }
        return (http, stream)
        #endif
    }
}

/// Holds the reader task so a cancelled caller can stop it.
final class ReaderBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var cancelled = false
    func set(_ t: Task<Void, Never>) {
        lock.lock(); task = t; let c = cancelled; lock.unlock()
        if c { t.cancel() }
    }
    func cancel() {
        lock.lock(); cancelled = true; let t = task; lock.unlock()
        t?.cancel()
    }
}

/// `HTTPFetching` (addon JSON) on top of `HTTPClient`: JSON limits, non-2xx throws `AddonError.http`.
public struct HTTPClientFetcher: HTTPFetching {
    let client: HTTPClient
    let limits: HTTPLimits
    public init(client: HTTPClient = LimitedHTTPClient.shared, limits: HTTPLimits = .json) {
        self.client = client; self.limits = limits
    }
    public func data(from url: URL) async throws -> Data {
        try await data(from: url, limits: limits)
    }
    public func data(from url: URL, limits: HTTPLimits) async throws -> Data {
        let (d, resp) = try await client.data(URLRequest(url: url), limits: limits, fresh: false)
        if !(200..<300).contains(resp.statusCode) { throw AddonError.http(resp.statusCode) }
        return d
    }
}

/// Task 2.3: lists from addon answers are cut after decoding.
public enum AddonListCaps {
    public static let catalog = 500
    public static let streams = 2000
    public static func cap<T>(_ items: [T], _ limit: Int) -> [T] {
        items.count > limit ? Array(items.prefix(limit)) : items
    }
}
