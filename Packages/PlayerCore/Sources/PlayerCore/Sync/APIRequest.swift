import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Anfrage mit Methode/Kopfzeilen/Body (für Trakt/Simkl). Status wird zurückgegeben, nicht geworfen.
public struct APIRequest: Sendable, Equatable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: String = "GET", url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method; self.url = url; self.headers = headers; self.body = body
    }
}

/// Antwort mit Kopfzeilen (Schlüssel klein geschrieben), z. B. für `Retry-After`.
public struct APIResponse: Sendable, Equatable {
    public var status: Int
    public var data: Data
    public var headers: [String: String]
    public init(status: Int, data: Data, headers: [String: String] = [:]) {
        self.status = status; self.data = data
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
    }
}

public protocol APISending: Sendable {
    func send(_ r: APIRequest) async throws -> (status: Int, data: Data)
    /// Wie `send`, zusätzlich mit Kopfzeilen. Standard: ohne Kopfzeilen.
    func sendFull(_ r: APIRequest) async throws -> APIResponse
}

extension APISending {
    public func sendFull(_ r: APIRequest) async throws -> APIResponse {
        let (s, d) = try await send(r)
        return APIResponse(status: s, data: d)
    }

    /// Bei 429 genau einmal nach `Retry-After` (höchstens 10 s) wiederholen.
    func sendRespectingRateLimit(_ r: APIRequest, sleep: APISleep) async throws -> APIResponse {
        let first = try await sendFull(r)
        guard first.status == 429 else { return first }
        await sleep(SyncRetry.retryAfter(first.headers["retry-after"]))
        return try await sendFull(r)
    }
}

public struct URLSessionSender: APISending {
    public init() {}
    public func send(_ r: APIRequest) async throws -> (status: Int, data: Data) {
        let x = try await sendFull(r)
        return (x.status, x.data)
    }
    public func sendFull(_ r: APIRequest) async throws -> APIResponse {
        var u = URLRequest(url: r.url)
        u.httpMethod = r.method
        for (k, v) in r.headers { u.setValue(v, forHTTPHeaderField: k) }
        u.httpBody = r.body
        let (d, resp) = try await URLSession.shared.data(for: u)
        let http = resp as? HTTPURLResponse
        var h: [String: String] = [:]
        for (k, v) in http?.allHeaderFields ?? [:] { h[String(describing: k)] = String(describing: v) }
        return APIResponse(status: http?.statusCode ?? 0, data: d, headers: h)
    }
}

/// Warten in Sekunden (in Tests ersetzbar).
public typealias APISleep = @Sendable (Double) async -> Void
public let defaultAPISleep: APISleep = { s in try? await Task.sleep(nanoseconds: UInt64(max(0, s) * 1_000_000_000)) }

/// App-Angaben, die Simkl bei jeder Anfrage erwartet. Version wie `CFBundleShortVersionString` in App/project.yml.
public enum SyncAppInfo {
    public static let name = "player"
    public static let version = "0.4.0"
    public static var userAgent: String { "Player/\(version)" }
}

enum SyncRetry {
    static let maxRetryAfter: Double = 10
    /// `Retry-After` in Sekunden (Zahl); fehlt/unlesbar → 1 s. Begrenzt auf 0…10 s.
    static func retryAfter(_ v: String?) -> Double {
        let s = v.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } ?? 1
        return min(max(s, 0), maxRetryAfter)
    }

    /// Scrobble senden: 409 (schon erfasst) zählt als Erfolg; `stop` wird nach einem Netzfehler einmal wiederholt.
    static func scrobble(_ action: ScrobbleAction, sleep: APISleep, _ perform: () async throws -> APIResponse) async throws {
        let attempts = action == .stop ? 2 : 1
        for i in 1...attempts {
            let res: APIResponse
            do { res = try await perform() } catch {
                if i < attempts { await sleep(1.5); continue }
                throw error
            }
            guard (200..<300).contains(res.status) || res.status == 409 else { throw APIError.status(res.status) }
            return
        }
    }
}

public enum APIError: Error, Equatable { case status(Int), notConnected, decoding(String) }

/// Poster für IMDb-IDs ohne eigenes Bild (Stremio-Metahub).
public func metahubPoster(_ imdb: String) -> String { "https://images.metahub.space/poster/medium/\(imdb)/img" }
public func metahubBackground(_ imdb: String) -> String { "https://images.metahub.space/background/medium/\(imdb)/img" }
