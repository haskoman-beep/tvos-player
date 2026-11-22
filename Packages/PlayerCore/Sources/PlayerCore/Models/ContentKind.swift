import Foundation

/// Wave W-a: whether a catalog or meta type has seasons and episodes. Addons use more types than "movie" and
/// "series": anime catalogs send "anime" (or "anime.series" / "anime.movie"), others "tv", "channel" or their own.
public enum ContentKind {
    /// Series-like: "series", "anime" and every type ending in ".series". Films: "movie" and types ending in ".movie".
    /// Any other type counts as series-like when its meta lists episodes (`hasVideos`, i.e. more than one video).
    public static func isEpisodic(type: String, hasVideos: Bool = false) -> Bool {
        let t = type.trimmingCharacters(in: .whitespaces).lowercased()
        if t == "movie" || t.hasSuffix(".movie") { return false }
        if t == "series" || t == "anime" || t.hasSuffix(".series") { return true }
        return hasVideos
    }
}
