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

    /// The addon and the catalog type to request. A manifest id match is taken as it is (unchanged behaviour). For a
    /// stored address the addons on that host come first, then every installed addon; for `anyAddon` every addon.
    /// The catalog must be declared in the manifest; the declared type wins when the requested one is not declared
    /// (e.g. `all::` catalogs of AIOMetadata).
    public static func resolve(_ addons: [InstalledAddon], addonId: String, catalogId: String,
                               type: String) -> (addon: InstalledAddon, type: String)? {
        if let a = addons.first(where: { $0.manifest.id == addonId }) { return (a, type) }
        let host = hostKey(addonId)
        guard addonId == anyAddon || host != nil else { return nil }
        let onHost = host.map { h in addons.filter { hostKey($0.manifestURL) == h } } ?? []
        for group in [onHost, addons] {
            if let a = group.first(where: { $0.manifest.catalogs.contains { $0.id == catalogId && $0.type == type } }) {
                return (a, type)
            }
            for a in group {
                if let c = a.manifest.catalogs.first(where: { $0.id == catalogId }) { return (a, c.type) }
            }
        }
        return nil
    }
}
