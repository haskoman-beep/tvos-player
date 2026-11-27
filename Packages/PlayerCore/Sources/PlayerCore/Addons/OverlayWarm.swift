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

/// Build 8 review: failures of the tile/warm-up requests (429, timeouts during a burst). The warm-up waits after a
/// failure (15 s, then 30 s, at most 60 s while failures go on; one answer resets it), and a failed title counts as
/// "no poster" for `tileRetry` only (not the 10 min of the detail page), so the next tile or warm-up asks again.
public struct OverlayBackoff: Sendable, Equatable {
    public static let steps: [TimeInterval] = [15, 30, 60]
    public static let tileRetry: TimeInterval = 45

    public private(set) var failures = 0
    public private(set) var until: Date?

    public init() {}

    public mutating func noteFailure(now: Date = Date()) {
        let wait = Self.steps[min(failures, Self.steps.count - 1)]
        failures += 1
        until = now.addingTimeInterval(wait)
    }

    public mutating func noteSuccess() { failures = 0; until = nil }

    /// Seconds the warm-up still waits (0 = go).
    public func wait(now: Date = Date()) -> TimeInterval {
        guard let until else { return 0 }
        return max(0, until.timeIntervalSince(now))
    }
}

extension OverlayWarmPlan {
    /// Build 8 review: whether a poster address carries the title id as a whole path or query part
    /// (`…/imdb/poster-default/tt123.jpg`, `?id=123`), not inside a longer number.
    public static func urlCarriesID(_ url: String, id: String) -> Bool {
        let bare = id.hasPrefix("tmdb:") ? String(id.dropFirst(5)) : id
        guard !bare.isEmpty else { return false }
        let parts = url.split(whereSeparator: { "/?&=.:".contains($0) })
        return parts.contains { $0 == bare[...] }
    }
}
