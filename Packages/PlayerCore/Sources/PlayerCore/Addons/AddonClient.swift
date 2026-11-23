import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Abstraktion über HTTP, damit Tests ohne Netz laufen.
public protocol HTTPFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

/// Task 2.3: kept for existing callers; goes through the shared `HTTPClient` with JSON limits.
public struct URLSessionFetcher: HTTPFetching {
    public init() {}
    public func data(from url: URL) async throws -> Data {
        try await HTTPClientFetcher().data(from: url)
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
    /// Wave W-a: query of the manifest link (variant links `…/manifest.json?v=…`), sent with every request.
    public var manifestQuery: String? { AddonClient.parseManifest(manifestURL)?.query }
}

public struct AddonClient: Sendable {
    let http: HTTPFetching
    /// Wave W-a: log line (category, text) for things the caller should see, e.g. skipped catalog items.
    let log: @Sendable (_ category: String, _ message: String) -> Void

    public init(http: HTTPFetching = URLSessionFetcher(),
                log: @escaping @Sendable (_ category: String, _ message: String) -> Void = { _, _ in }) {
        self.http = http; self.log = log
    }

    public static func baseURL(fromManifest raw: String) -> String? { parseManifest(raw)?.base }

    /// Wave W-a: install link → base address (without `/manifest.json`) and the manifest's query (without „?“).
    /// Accepted: `https://…/manifest.json`, the same with a query (`?v=a,b`, kept for all requests), `stremio://…`
    /// (becomes https), a link to the addon's configure page (`…/configure`, its query is dropped) and a web install
    /// link that carries the manifest address URL-encoded in `addon=`. nil without http(s) address.
    public static func parseManifest(_ raw: String) -> (base: String, query: String?)? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let inner = webInstallTarget(s) { s = inner }
        if s.lowercased().hasPrefix("stremio://") { s = "https://" + s.dropFirst("stremio://".count) }
        let low = s.lowercased()
        guard low.hasPrefix("http://") || low.hasPrefix("https://") else { return nil }
        if let hash = s.firstIndex(of: "#") { s = String(s[..<hash]) }
        var query: String?
        if let q = s.firstIndex(of: "?") {
            query = String(s[s.index(after: q)...])
            s = String(s[..<q])
        }
        while s.hasSuffix("/") { s.removeLast() }
        if s.lowercased().hasSuffix("/manifest.json") {
            s.removeLast("/manifest.json".count)
        } else {
            if s.lowercased().hasSuffix("/configure") { s.removeLast("/configure".count) }
            query = nil   // only the manifest's own query selects anything
        }
        while s.hasSuffix("/") { s.removeLast() }
        guard let host = URL(string: s)?.host, !host.isEmpty else { return nil }
        if query?.isEmpty == true { query = nil }
        return (s, query)
    }

    /// Manifest address inside a web install link (`…#/addons?addon=https%3A%2F%2F…%2Fmanifest.json`); nil otherwise.
    static func webInstallTarget(_ s: String) -> String? {
        guard let r = s.range(of: "addon=", options: .caseInsensitive) else { return nil }
        let before = s[..<r.lowerBound]
        guard before.hasSuffix("?") || before.hasSuffix("&"), !before.lowercased().contains("/manifest.json") else { return nil }
        var value = String(s[r.upperBound...])
        if let amp = value.firstIndex(of: "&") { value = String(value[..<amp]) }
        guard let decoded = value.removingPercentEncoding?.trimmingCharacters(in: .whitespaces) else { return nil }
        let low = decoded.lowercased()
        guard low.hasPrefix("http://") || low.hasPrefix("https://") || low.hasPrefix("stremio://") else { return nil }
        return decoded
    }

    /// Pfadsegmente nach Stremio-Regeln kodieren (IDs wie `tt123:1:2` bleiben lesbar).
    static func encode(_ segment: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }

    public func install(manifestURL: String) async throws -> InstalledAddon {
        guard let parsed = Self.parseManifest(manifestURL) else { throw AddonError.invalidManifestURL(manifestURL) }
        let manifest = parsed.base + "/manifest.json" + (parsed.query.map { "?" + $0 } ?? "")
        guard let url = URL(string: manifest) else { throw AddonError.invalidManifestURL(manifestURL) }
        let m = try JSONDecoder().decode(AddonManifest.self, from: try await http.data(from: url))
        return InstalledAddon(manifestURL: manifest, manifest: m)
    }

    public func streams(_ addon: InstalledAddon, type: String, id: String) async throws -> [StreamItem] {
        let url = try resourceURL(addon, "stream", type: type, id: id)
        let r = try JSONDecoder().decode(StreamsResponse.self, from: try await http.data(from: url))
        if r.skipped > 0 { log("streams", "\(addon.manifest.name) \(type)/\(id): \(AddonNotices.skippedText(r.skipped))") }
        if r.streams.count > AddonListCaps.streams {
            log("streams", "\(addon.manifest.name) \(type)/\(id): \(r.streams.count) Streams, gekappt auf \(AddonListCaps.streams)")
        }
        return AddonListCaps.cap(r.streams, AddonListCaps.streams)
    }

    public func catalog(_ addon: InstalledAddon, type: String, id: String, extra: [String: String] = [:]) async throws -> [MetaPreview] {
        try await catalogPage(addon, type: type, id: id, extra: extra).items
    }

    /// Wave W-a: a catalog answer with what was dropped (unreadable items, error items); both are logged here.
    public func catalogPage(_ addon: InstalledAddon, type: String, id: String,
                            extra: [String: String] = [:]) async throws -> AddonCatalogPage {
        let url = try resourceURL(addon, "catalog", type: type, id: id, extra: extra)
        let r = try JSONDecoder().decode(MetasResponse.self, from: try await http.data(from: url))
        if r.metas.count > AddonListCaps.catalog {
            log("katalog", "\(addon.manifest.name) \(type)/\(id): \(r.metas.count) Einträge, gekappt auf \(AddonListCaps.catalog)")
        }
        let page = AddonCatalogPage(decoded: AddonListCaps.cap(r.metas, AddonListCaps.catalog), skipped: r.skipped, catalogType: type)
        if let note = page.logNote { log("katalog", "\(addon.manifest.name) \(type)/\(id): \(note)") }
        return page
    }

    /// Wave W-a: a missing `id`/`type` is filled in from the request; an error item instead of a meta throws
    /// `AddonNoticeError` (logged).
    public func meta(_ addon: InstalledAddon, type: String, id: String) async throws -> MetaDetail {
        let url = try resourceURL(addon, "meta", type: type, id: id)
        var m = try JSONDecoder().decode(MetaResponse.self, from: try await http.data(from: url)).meta
        if AddonNotices.isErrorItem(id: m.id) {
            let text = AddonNotices.text(name: m.name, description: m.description, id: m.id)
            log("meta", "\(addon.manifest.name) \(type)/\(id): Fehlereintrag statt Metadaten: \(text)")
            throw AddonNoticeError(text)
        }
        if m.id.isEmpty { m.id = id }
        if m.type.isEmpty { m.type = type }
        return m
    }

    /// `{base}/{resource}/{type}/{id}[/{extra}].json`; Wave W-a: plus the manifest's query (`?v=…`) if it has one.
    public func resourceURL(_ addon: InstalledAddon, _ resource: String, type: String, id: String,
                            extra: [String: String] = [:]) throws -> URL {
        let parsed = Self.parseManifest(addon.manifestURL)
        var path = "\(parsed?.base ?? addon.manifestURL)/\(resource)/\(Self.encode(type))/\(Self.encode(id))"
        if !extra.isEmpty {
            let parts = extra.sorted { $0.key < $1.key }.map { "\(Self.encode($0.key))=\(Self.encode($0.value))" }
            path += "/" + parts.joined(separator: "&")
        }
        path += ".json" + (parsed?.query.map { "?" + $0 } ?? "")
        guard let url = URL(string: path) else { throw AddonError.invalidManifestURL(path) }
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
