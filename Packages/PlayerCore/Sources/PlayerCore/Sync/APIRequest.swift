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

public protocol APISending: Sendable {
    func send(_ r: APIRequest) async throws -> (status: Int, data: Data)
}

public struct URLSessionSender: APISending {
    public init() {}
    public func send(_ r: APIRequest) async throws -> (status: Int, data: Data) {
        var u = URLRequest(url: r.url)
        u.httpMethod = r.method
        for (k, v) in r.headers { u.setValue(v, forHTTPHeaderField: k) }
        u.httpBody = r.body
        let (d, resp) = try await URLSession.shared.data(for: u)
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, d)
    }
}

public enum APIError: Error, Equatable { case status(Int), notConnected, decoding(String) }

/// Poster für IMDb-IDs ohne eigenes Bild (Stremio-Metahub).
public func metahubPoster(_ imdb: String) -> String { "https://images.metahub.space/poster/medium/\(imdb)/img" }
public func metahubBackground(_ imdb: String) -> String { "https://images.metahub.space/background/medium/\(imdb)/img" }
