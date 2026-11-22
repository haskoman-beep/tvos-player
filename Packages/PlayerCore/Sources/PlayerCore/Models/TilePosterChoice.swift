import Foundation

/// Wave F-k: which picture a poster tile shows. Order: the metadata addon's poster (setting “pictures from the
/// metadata addon”, when the addon delivered one), then the catalogue or TMDB poster. Empty and repeated addresses
/// are skipped, addresses that failed to load are left out. nil = no picture left: the tile shows its title
/// instead of an empty grey card.
public enum TilePosterChoice {
    /// Addresses to try, best first, without empty or repeated entries.
    public static func candidates(addon: String?, poster: String?) -> [String] {
        var out: [String] = []
        for s in [addon, poster] {
            guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty, !out.contains(s) else { continue }
            out.append(s)
        }
        return out
    }

    /// First address that has not failed; nil when none is left.
    public static func current(addon: String?, poster: String?, failed: Set<String>) -> String? {
        candidates(addon: addon, poster: poster).first { !failed.contains($0) }
    }

    /// Log text after a failed address: what the tile shows next („nächstes Poster“ or „Titel“).
    public static func fallbackText(addon: String?, poster: String?, failed: Set<String>) -> String {
        current(addon: addon, poster: poster, failed: failed) == nil ? "Titel" : "nächstes Poster"
    }
}

/// Wave F-k: log line for the quality badges of a tile row (how many tiles already know their best quality).
/// Badges come only from the source cache (prefetch on focus rest, or an opened detail page), never from a
/// request of their own.
public enum PosterBadgeStats {
    /// Whether `best` yields at least one poster badge with the user's badge settings (independent of placement).
    public static func hasBadges(_ best: BestQuality?, settings: BadgeSettings) -> Bool {
        best.map { !QualityBadges.poster($0, settings: settings).isEmpty } ?? false
    }

    /// „Plaketten: <row> n/m mit Qualität“, with „ (Anzeige aus)“ when the poster badges are switched off.
    public static func logLine(row: String, withQuality: Int, total: Int, placement: PosterBadgePlacement) -> String {
        "Plaketten: \(row) \(withQuality)/\(total) mit Qualität" + (placement == .off ? " (Anzeige aus)" : "")
    }
}
