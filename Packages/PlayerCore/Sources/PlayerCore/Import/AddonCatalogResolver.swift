import Foundation

/// Build 5 (b5f): which installed addon serves an addon catalog source.
///
/// Nuvio exports and addon rows name the addon by its manifest id. Widget exports of the Fusion Widget Manager name it
/// by its manifest address (with the user's addon configuration in the path) or by the placeholder `YOUR_AIOMETADATA`.
/// The importer keeps only scheme and host of such an address (`storedID`), never the path, so no configuration ends up
/// in the start page layout. At load time the catalog is looked up in the installed addons.
public enum AddonCatalogResolver {
    /// Stored addon id for "any installed addon that declares this catalog" (placeholder or unusable address).
    public static let anyAddon = "*"

    /// Placeholder the manager writes before the user synced an AIOMetadata manifest.
    static let placeholder = "YOUR_AIOMETADATA"

    /// Addon reference to store for an `addonId` of a widget export.
    static func storedID(_ raw: String?) -> String {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty, s != placeholder else { return anyAddon }
        if let host = hostKey(s) { return "https://" + host }
        // Something with a path but no readable host: never stored (could carry configuration).
        if s.contains("/") || s.contains("?") || s.contains(" ") { return anyAddon }
        return s
    }

    /// `host[:port]` (lower case) of an http(s)/stremio address, else nil.
    static func hostKey(_ s: String) -> String? {
        guard let u = URL(string: s), let scheme = u.scheme?.lowercased(), ["https", "http", "stremio"].contains(scheme),
              let host = u.host?.lowercased(), !host.isEmpty else { return nil }
        return u.port.map { "\(host):\($0)" } ?? host
    }

    /// The addon and the catalog type to request (builds a one-off index; for many sources use `AddonCatalogIndex`).
    public static func resolve(_ addons: [InstalledAddon], addonId: String, catalogId: String,
                               type: String) -> (addon: InstalledAddon, type: String)? {
        resolve(AddonCatalogIndex(addons), addonId: addonId, catalogId: catalogId, type: type)
    }

    /// A manifest id match is taken as it is (unchanged behaviour). For a stored address the addons on that host come
    /// first. The catalog must be declared in the manifest. When the requested type is not declared, the declared
    /// type is taken only if that is unambiguous: the addon declares the id as `all` (AIOMetadata `all::` catalogs,
    /// which the manager exports as `series`), or with exactly one type (a guessed type of an Omni id). So a series
    /// source never loads the movie catalog of the same id.
    /// Review L7: outside the stored host, a catalog id declared by several addons (generic ids such as `top`) is
    /// taken only from the first addon whose manifest id or name says AIOMetadata (the manager's addon); otherwise no
    /// match instead of a guess.
    public static func resolve(_ index: AddonCatalogIndex, addonId: String, catalogId: String,
                               type: String) -> (addon: InstalledAddon, type: String)? {
        if let i = index.byManifestID[addonId] { return (index.addons[i], type) }
        let host = hostKey(addonId)
        guard addonId == anyAddon || host != nil else { return nil }
        let entries = index.declared[catalogId] ?? []
        guard !entries.isEmpty else { return nil }
        // Per addon (in installed order): the type to request, if unambiguous.
        var picks: [(addon: Int, type: String)] = []
        var exact: [Int] = []
        var seen = Set<Int>()
        for e in entries where seen.insert(e.addon).inserted {
            let types = entries.filter { $0.addon == e.addon }.map(\.type)
            if types.contains(type) { picks.append((e.addon, type)); exact.append(e.addon) }
            else if types.contains("all") { picks.append((e.addon, "all")) }
            else if types.count == 1 { picks.append((e.addon, types[0])) }
        }
        // Exact type before a fallback type, as before.
        let ordered = picks.filter { exact.contains($0.addon) } + picks.filter { !exact.contains($0.addon) }
        if let host, let p = ordered.first(where: { index.hosts[$0.addon] == host }) { return (index.addons[p.addon], p.type) }
        let distinct = Set(ordered.map(\.addon))
        if distinct.count == 1, let p = ordered.first { return (index.addons[p.addon], p.type) }
        if let p = ordered.first(where: { index.isAIOMetadata[$0.addon] }) { return (index.addons[p.addon], p.type) }
        return nil
    }
}

/// Review L5: installed addons indexed once (manifest ids, hosts, declared catalogs), for syncs over many sources.
public struct AddonCatalogIndex: Sendable {
    struct Entry: Sendable { var addon: Int; var type: String }
    let addons: [InstalledAddon]
    let byManifestID: [String: Int]
    let hosts: [String?]
    let isAIOMetadata: [Bool]
    /// Catalog id → declarations in installed order.
    let declared: [String: [Entry]]

    public init(_ addons: [InstalledAddon]) {
        self.addons = addons
        var ids: [String: Int] = [:]
        var decl: [String: [Entry]] = [:]
        for (i, a) in addons.enumerated() {
            if ids[a.manifest.id] == nil { ids[a.manifest.id] = i }
            for c in a.manifest.catalogs { decl[c.id, default: []].append(Entry(addon: i, type: c.type)) }
        }
        byManifestID = ids
        declared = decl
        hosts = addons.map { AddonCatalogResolver.hostKey($0.manifestURL) }
        isAIOMetadata = addons.map { a in
            [a.manifest.id, a.manifest.name].contains { $0.lowercased().filter { $0.isLetter }.contains("aiometadata") }
        }
    }
}
