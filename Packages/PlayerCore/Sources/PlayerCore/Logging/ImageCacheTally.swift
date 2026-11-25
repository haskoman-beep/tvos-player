import Foundation

/// Build 4 follow-up 2 (P3): the picture memory cache per 30 s line. Each miss gets a class, so the device log tells
/// why the hit rate is low: a new address (cold first load), the address in another size (target mismatch), the same
/// key decoded before and dropped since (memory budget), or a load already running for it. Downloads are split into
/// disk cache and network (URLSession metrics; downloads without metrics show as the difference), decodes timed,
/// NSCache releases counted with their bytes.
public struct ImageCacheTally: Sendable, Equatable {
    public enum Miss: Int, Sendable, CaseIterable {
        case new, otherSize, evicted, joined
    }

    /// The class of a memory-cache miss for `key`. `lastKey`: the key last decoded for the same address and blur
    /// (nil = none since launch or the last clearing); `joined`: a load for `key` is running.
    public static func classify(key: String, lastKey: String?, joined: Bool) -> Miss {
        if joined { return .joined }
        guard let lastKey else { return .new }
        return lastKey == key ? .evicted : .otherSize
    }

    public private(set) var hits = 0
    private var missCounts = [Int](repeating: 0, count: Miss.allCases.count)
    public private(set) var fetches = 0
    public private(set) var fromDisk = 0
    public private(set) var fromNetwork = 0
    public private(set) var decodes = 0
    public private(set) var longestDecodeMs = 0
    public private(set) var releases = 0
    public private(set) var releasedBytes = 0

    public init() {}

    public var misses: Int { missCounts.reduce(0, +) }
    public var isEmpty: Bool { hits == 0 && misses == 0 }
    public func count(_ kind: Miss) -> Int { missCounts[kind.rawValue] }

    public mutating func hit() { hits += 1 }
    public mutating func miss(_ kind: Miss) { missCounts[kind.rawValue] += 1 }
    /// A download started (each size variant or fallback address counts).
    public mutating func fetched() { fetches += 1 }
    public mutating func loaded(fromDisk disk: Bool) { if disk { fromDisk += 1 } else { fromNetwork += 1 } }
    public mutating func decoded(ms: Int) {
        decodes += 1
        longestDecodeMs = max(longestDecodeMs, ms)
    }
    public mutating func evicted(bytes: Int) {
        releases += 1
        releasedBytes += bytes
    }

    /// The log text: hits and misses as before (`Cache Treffer h / Fehlgriffe m`), then only the parts that happened.
    public func text() -> String {
        var line = "Cache Treffer \(hits) / Fehlgriffe \(misses)"
        if misses > 0 {
            line += " (neu \(count(.new)) · andere Größe \(count(.otherSize)) · verdrängt \(count(.evicted))"
                + " · läuft schon \(count(.joined)))"
        }
        if fetches > 0 { line += " · Ladungen \(fetches) (Platte \(fromDisk) · Netz \(fromNetwork))" }
        if decodes > 0 { line += " · dekodiert \(decodes), längstes \(longestDecodeMs) ms" }
        if releases > 0 { line += " · freigegeben \(releases) (\(PictureArrivalStats.mb(releasedBytes)) MB)" }
        return line
    }
}
