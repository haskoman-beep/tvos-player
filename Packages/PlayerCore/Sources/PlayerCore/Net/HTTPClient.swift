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
}

public enum HTTPClientError: Error, Equatable {
    /// The body (declared or received) is larger than `maxBytes`; the transfer was stopped.
    case tooLarge(limit: Int)
    /// `resourceTimeout` passed before the body was complete.
    case timedOut
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

    static func prepared(_ request: URLRequest, limits: HTTPLimits, fresh: Bool) -> URLRequest {
        var r = request
        r.timeoutInterval = limits.requestTimeout
        // Not fresh: keep the caller's rule (e.g. the image pipeline's returnCacheDataElseLoad).
        if fresh { r.cachePolicy = .reloadIgnoringLocalCacheData }
        return r
    }

    public func data(_ request: URLRequest, limits: HTTPLimits, fresh: Bool) async throws -> (Data, HTTPURLResponse) {
        let r = Self.prepared(request, limits: limits, fresh: fresh)
        let transport = self.transport
        return try await withThrowingTaskGroup(of: (Data, HTTPURLResponse)?.self) { group in
            group.addTask { try await Self.read(r, transport: transport, maxBytes: limits.maxBytes) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, limits.resourceTimeout) * 1_000_000_000))
                return nil
            }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let result = first else { throw HTTPClientError.timedOut }
            return result
        }
    }

    static func read(_ r: URLRequest, transport: HTTPByteTransport, maxBytes: Int) async throws -> (Data, HTTPURLResponse) {
        let (resp, stream) = try await transport.open(r)
        if resp.expectedContentLength > Int64(maxBytes) { throw HTTPClientError.tooLarge(limit: maxBytes) }
        var out = Data()
        for try await chunk in stream {
            if out.count + chunk.count > maxBytes { throw HTTPClientError.tooLarge(limit: maxBytes) }
            out.append(chunk)
            try Task.checkCancellation()
        }
        return (out, resp)
    }
}

/// URLSession transport. On Apple platforms it reads via `bytes(for:)` so a too-large body stops early.
public struct URLSessionByteTransport: HTTPByteTransport {
    let session: URLSession
    public init(session: URLSession) { self.session = session }

    public static let shared: URLSessionByteTransport = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10
        // Outer bound only; the per-request resourceTimeout is enforced by LimitedHTTPClient.
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
                        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                        answered = true
                        rc.resume(returning: http)
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
