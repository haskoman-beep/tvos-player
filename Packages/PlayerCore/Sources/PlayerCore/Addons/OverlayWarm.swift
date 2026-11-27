import Foundation

/// Build 8 (poster): warming the metadata addon's posters (rating overlays) of a page block as soon as it lands,
/// instead of one request per visible tile after a 300 ms rest. Visible tiles stay ahead (urgent in `AsyncLimiter`).
public enum OverlayWarmPlan {
    /// Warm-up titles not yet answered at most (a fast scroll through many blocks does not pile up requests).
    public static let maxPending = 80

    /// Titles of a block worth warming: TMDB tiles only (the addon poster replaces the TMDB one there), each id once,
    /// in block order (top rows first), at most so many that `pending` stays within `maxPending`.
    public static func pick(_ ids: [String], pending: Int, cap: Int = maxPending) -> [String] {
        let room = max(0, cap - pending)
        var seen = Set<String>()
        var out: [String] = []
        for id in ids where id.hasPrefix("tmdb:") && out.count < room && seen.insert(id).inserted { out.append(id) }
        return out
    }
}

/// Build 8 (poster): one `poster` line per warmed block: `Overlays N/M in X ms (Cache K, Netz L)`.
/// N = titles with an addon poster, M = titles warmed, K = answered from memory or the disk map, L = asked the addon.
public struct OverlayWarmTally: Sendable, Equatable {
    public enum Source: Sendable { case cache, network, failed }

    public private(set) var total: Int
    public private(set) var found = 0
    public private(set) var cache = 0
    public private(set) var network = 0
    public private(set) var failed = 0

    public init(total: Int) { self.total = total }

    public mutating func record(_ source: Source, found poster: Bool) {
        switch source {
        case .cache: cache += 1
        case .network: network += 1
        case .failed: failed += 1
        }
        if poster { found += 1 }
    }

    public func line(ms: Int) -> String {
        let miss = failed > 0 ? " · ohne Antwort \(failed)" : ""
        return "Overlays \(found)/\(total) in \(ms) ms (Cache \(cache), Netz \(network))\(miss)"
    }
}
