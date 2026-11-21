import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Abstraktion über HTTP, damit Tests ohne Netz laufen.
public protocol HTTPFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

public struct URLSessionFetcher: HTTPFetching {
    public init() {}
    public func data(from url: URL) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(from: url)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AddonError.http(http.statusCode)
        }
        return data
    }
}

public enum AddonError: Error, Equatable {
    case invalidManifestURL(String)
    case http(Int)
}

/// Ein installiertes Addon: Basis-URL (ohne `/manifest.json`) plus geladenes Manifest.
public struct InstalledAddon: Codable, Sendable, Equatable, Identifiable {
    public var manifestURL: String
    public var manifest: AddonManifest
    public var id: String { manifestURL }

    public init(manifestURL: String, manifest: AddonManifest) {
        self.manifestURL = manifestURL; self.manifest = manifest
    }

    /// Basis-URL; Stremio erlaubt auch `stremio://`, das wird zu `https://`.
    public var baseURL: String { AddonClient.baseURL(fromManifest: manifestURL) ?? manifestURL }
}

public struct AddonClient: Sendable {
    let http: HTTPFetching
    public init(http: HTTPFetching = URLSessionFetcher()) { self.http = http }

    public static func baseURL(fromManifest raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("stremio://") { s = "https://" + s.dropFirst("stremio://".count) }
        guard s.hasPrefix("http://") || s.hasPrefix("https://") else { return nil }
        if s.hasSuffix("/manifest.json") { s.removeLast("/manifest.json".count) }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Pfadsegmente nach Stremio-Regeln kodieren (IDs wie `tt123:1:2` bleiben lesbar).
    static func encode(_ segment: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }

    public func install(manifestURL: String) async throws -> InstalledAddon {
        guard let base = Self.baseURL(fromManifest: manifestURL), let url = URL(string: base + "/manifest.json") else {
            throw AddonError.invalidManifestURL(manifestURL)
        }
        let m = try JSONDecoder().decode(AddonManifest.self, from: try await http.data(from: url))
        return InstalledAddon(manifestURL: base + "/manifest.json", manifest: m)
    }

    public func streams(_ addon: InstalledAddon, type: String, id: String) async throws -> [StreamItem] {
        let url = try resourceURL(addon, "stream", type: type, id: id)
        return try JSONDecoder().decode(StreamsResponse.self, from: try await http.data(from: url)).streams
    }

    public func catalog(_ addon: InstalledAddon, type: String, id: String, extra: [String: String] = [:]) async throws -> [MetaPreview] {
        let url = try resourceURL(addon, "catalog", type: type, id: id, extra: extra)
        return try JSONDecoder().decode(MetasResponse.self, from: try await http.data(from: url)).metas
    }

    public func meta(_ addon: InstalledAddon, type: String, id: String) async throws -> MetaDetail {
        let url = try resourceURL(addon, "meta", type: type, id: id)
        return try JSONDecoder().decode(MetaResponse.self, from: try await http.data(from: url)).meta
    }

    public func resourceURL(_ addon: InstalledAddon, _ resource: String, type: String, id: String,
                            extra: [String: String] = [:]) throws -> URL {
        var path = "\(addon.baseURL)/\(resource)/\(Self.encode(type))/\(Self.encode(id))"
        if !extra.isEmpty {
            let parts = extra.sorted { $0.key < $1.key }.map { "\(Self.encode($0.key))=\(Self.encode($0.value))" }
            path += "/" + parts.joined(separator: "&")
        }
        guard let url = URL(string: path + ".json") else { throw AddonError.invalidManifestURL(path) }
        return url
    }

    /// Streams aller passenden Addons parallel holen; Fehler einzelner Addons werden übersprungen.
    public func streams(from addons: [InstalledAddon], type: String, id: String) async -> [(addon: InstalledAddon, streams: [StreamItem])] {
        await withTaskGroup(of: (Int, InstalledAddon, [StreamItem])?.self) { group in
            for (i, a) in addons.enumerated() where a.manifest.supports("stream", type: type, id: id) {
                group.addTask {
                    guard let s = try? await self.streams(a, type: type, id: id) else { return nil }
                    return (i, a, s)
                }
            }
            var out: [(Int, InstalledAddon, [StreamItem])] = []
            for await r in group { if let r { out.append(r) } }
            return out.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2) }
        }
    }
}
