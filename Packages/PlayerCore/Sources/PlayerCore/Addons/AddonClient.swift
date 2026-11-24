import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Abstraktion über HTTP, damit Tests ohne Netz laufen.
public protocol HTTPFetching: Sendable {
    func data(from url: URL) async throws -> Data
    /// Fix round 1: with explicit limits (addon timeout); fetchers without limits ignore them.
    func data(from url: URL, limits: HTTPLimits) async throws -> Data
}

public extension HTTPFetching {
    func data(from url: URL, limits: HTTPLimits) async throws -> Data { try await data(from: url) }
}

/// Task 2.3: kept for existing callers; goes through the shared `HTTPClient` with JSON limits.
public struct URLSessionFetcher: HTTPFetching {
    public init() {}
    public func data(from url: URL) async throws -> Data {
        try await HTTPClientFetcher().data(from: url)
    }
    public func data(from url: URL, limits: HTTPLimits) async throws -> Data {
        try await HTTPClientFetcher().data(from: url, limits: limits)
    }
}

public enum AddonError: Error, Equatable {
    case invalidManifestURL(String)
    case http(Int)
}

/// Ein installiertes Addon: Basis-URL (ohne `/manifest.json`) plus geladenes Manifest.
/// Task 3.6 (A-A-9): `instanceID` tells two installations apart (also two with the same `manifest.name`),
/// `manifestID` names the addon kind. Both default to values derived from the stored data (address, manifest) and
/// are written to the profile only when they were set to something else, so builds 249/250, Build 1 and Build 2
/// read (and ignore) them and an unchanged profile is written back byte for byte.
public struct InstalledAddon: Codable, Sendable, Equatable, Identifiable {
    public var manifestURL: String
    public var manifest: AddonManifest
    public var id: String { manifestURL }
    /// Explicit values (nil = derived). Kept apart so a changed `manifestURL` (e.g. `withoutSecrets`) also changes
    /// the derived identity.
    private var storedInstanceID: String?
    private var storedManifestID: String?

    /// Stable key of this installation: set explicitly, or derived from the address (`AddonIdentity.instanceID`).
    public var instanceID: String {
        get { storedInstanceID ?? AddonIdentity.instanceID(manifestURL: manifestURL) }
        set { storedInstanceID = newValue == AddonIdentity.instanceID(manifestURL: manifestURL) ? nil : newValue }
    }

    /// The addon kind (`manifest.id` unless set explicitly).
    public var manifestID: String {
        get { storedManifestID ?? manifest.id }
        set { storedManifestID = newValue == manifest.id ? nil : newValue }
    }

    public init(manifestURL: String, manifest: AddonManifest) {
        self.manifestURL = manifestURL; self.manifest = manifest
    }

    enum CodingKeys: String, CodingKey { case manifestURL, manifest, instanceID, manifestID }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        manifestURL = try c.decode(String.self, forKey: .manifestURL)
        manifest = try c.decode(AddonManifest.self, forKey: .manifest)
        let r = DecodeReportBox.of(decoder)
        let instance = c.decodeLenient(String?.self, forKey: .instanceID, default: nil, report: r)
        let kind = c.decodeLenient(String?.self, forKey: .manifestID, default: nil, report: r)
        if let instance, !instance.isEmpty { instanceID = instance }
        if let kind, !kind.isEmpty { manifestID = kind }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(manifestURL, forKey: .manifestURL)
        try c.encode(manifest, forKey: .manifest)
        try c.encodeIfPresent(storedInstanceID, forKey: .instanceID)
        try c.encodeIfPresent(storedManifestID, forKey: .manifestID)
    }

    /// Basis-URL; Stremio erlaubt auch `stremio://`, das wird zu `https://`.
    public var baseURL: String { AddonClient.baseURL(fromManifest: manifestURL) ?? manifestURL }
    /// Wave W-a: query of the manifest link (variant links `…/manifest.json?v=…`), sent with every request.
    public var manifestQuery: String? { AddonClient.parseManifest(manifestURL)?.query }
}

/// Task 3.6 (A-A-9): which installation an entry belongs to. Lists in the app carry a display label per entry;
/// `labels` makes that label unique per `instanceID` (the first installation keeps its name, a later one with the
/// same name gets „Name (2)“), so failed/answered sets, cache merging, duplicate removal and the remembered source
/// never mix two installations with the same `manifest.name`. With distinct names nothing changes.
public enum AddonIdentity {
    /// Derived from the normalised address (base plus manifest query); a short hash, so the address with its access
    /// part never shows up where the ID is logged or compared. Unparsable addresses hash as given (trimmed).
    public static func instanceID(manifestURL: String) -> String {
        let key = AddonClient.parseManifest(manifestURL).map { $0.base + ($0.query.map { "?" + $0 } ?? "") }
            ?? manifestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return "addon-" + NuvioImport.stableHash(key)
    }

    /// Display label per `instanceID`, unique within `addons` (installation order decides who keeps the plain name).
    public static func labels(_ addons: [InstalledAddon]) -> [String: String] {
        var out: [String: String] = [:]
        var used = Set<String>()
        // Plain names first, so a later „Name (2)“ never takes a name another addon really has.
        let plain = Set(addons.map(\.manifest.name))
        for a in addons where out[a.instanceID] == nil {
            var label = a.manifest.name
            var n = 2
            while used.contains(label) || (label != a.manifest.name && plain.contains(label)) {
                label = "\(a.manifest.name) (\(n))"; n += 1
            }
            used.insert(label)
            out[a.instanceID] = label
        }
        return out
    }

    /// Label of `addon` among `addons`; its plain name if it is not (or no longer) installed.
    public static func label(of addon: InstalledAddon, in addons: [InstalledAddon]) -> String {
        labels(addons)[addon.instanceID] ?? addon.manifest.name
    }

    /// The installation an entry label points at.
    public static func addon(labeled label: String, in addons: [InstalledAddon]) -> InstalledAddon? {
        let l = labels(addons)
        return addons.first { l[$0.instanceID] == label }
    }

    /// Labels of the asked installations without an answer, compared by `instanceID` (never by name).
    public static func unanswered(asked: [InstalledAddon], answered: [InstalledAddon], in addons: [InstalledAddon]) -> Set<String> {
        let l = labels(addons)
        let done = Set(answered.map(\.instanceID))
        return Set(asked.filter { !done.contains($0.instanceID) }.map { l[$0.instanceID] ?? $0.manifest.name })
    }
}

public struct AddonClient: Sendable {
    let http: HTTPFetching
    /// Wave W-a: log line (category, text) for things the caller should see, e.g. skipped catalog items.
    let log: @Sendable (_ category: String, _ message: String) -> Void
    /// Fix round 1: the profile's addon timeout; network limits of addon calls are derived from it. Default = the
    /// longest choice, so calls without a profile timeout are never cut before the caller's own deadline.
    public var addonTimeout: Double = AddonSearch.timeoutChoices.max() ?? 45
    var addonLimits: HTTPLimits { .addon(timeout: addonTimeout) }

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

    /// Task 3.6 (A-A-13): keys and values of `extra` like Stremio (`encodeURIComponent`): only ASCII letters, digits
    /// and `-_.!~*'()` stay, so `&`, `=`, `+`, `,`, `/` and spaces inside a value cannot split or end the segment.
    static func encodeExtra(_ part: String) -> String {
        part.addingPercentEncoding(withAllowedCharacters: extraAllowed) ?? part
    }

    private static let extraAllowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")

    public func install(manifestURL: String) async throws -> InstalledAddon {
        guard let parsed = Self.parseManifest(manifestURL) else { throw AddonError.invalidManifestURL(manifestURL) }
        let manifest = parsed.base + "/manifest.json" + (parsed.query.map { "?" + $0 } ?? "")
        guard let url = URL(string: manifest) else { throw AddonError.invalidManifestURL(manifestURL) }
        let m = try JSONDecoder().decode(AddonManifest.self, from: try await http.data(from: url, limits: addonLimits))
        return InstalledAddon(manifestURL: manifest, manifest: m)
    }

    public func streams(_ addon: InstalledAddon, type: String, id: String) async throws -> [StreamItem] {
        let url = try resourceURL(addon, "stream", type: type, id: id)
        let r = try JSONDecoder().decode(StreamsResponse.self, from: try await http.data(from: url, limits: addonLimits))
        if r.skipped > 0 { log("streams", "\(addon.manifest.name) \(type)/\(id): \(AddonNotices.skippedText(r.skipped))") }
        if r.streams.count > AddonListCaps.streams {
            log("streams", "\(addon.manifest.name) \(type)/\(id): \(r.streams.count) Streams, gekappt auf \(AddonListCaps.streams)")
        }
        let streams = AddonListCaps.cap(r.streams, AddonListCaps.streams)
        // Task 2.3, shadow build: count stream addresses the TargetPolicy would refuse; nothing is dropped yet.
        let origin = URL(string: addon.manifestURL)
        let refused = streams.filter { s in s.url.flatMap(URL.init(string:)).map { !TargetPolicy.allows($0, origin: origin) } ?? false }
        if !refused.isEmpty {
            log("streams", "\(addon.manifest.name) \(type)/\(id): Zielprüfung würde \(refused.count) von \(streams.count) Streams ablehnen (Schattenbetrieb)")
        }
        return streams
    }

    public func catalog(_ addon: InstalledAddon, type: String, id: String, extra: [String: String] = [:]) async throws -> [MetaPreview] {
        try await catalogPage(addon, type: type, id: id, extra: extra).items
    }

    /// Wave W-a: a catalog answer with what was dropped (unreadable items, error items); both are logged here.
    public func catalogPage(_ addon: InstalledAddon, type: String, id: String,
                            extra: [String: String] = [:]) async throws -> AddonCatalogPage {
        let url = try resourceURL(addon, "catalog", type: type, id: id, extra: extra)
        let r = try JSONDecoder().decode(MetasResponse.self, from: try await http.data(from: url, limits: addonLimits))
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
        var m = try JSONDecoder().decode(MetaResponse.self, from: try await http.data(from: url, limits: addonLimits)).meta
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
            let parts = extra.sorted { $0.key < $1.key }.map { "\(Self.encodeExtra($0.key))=\(Self.encodeExtra($0.value))" }
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
