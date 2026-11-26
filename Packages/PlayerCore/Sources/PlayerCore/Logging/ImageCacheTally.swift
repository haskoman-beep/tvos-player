import Foundation

/// Build 4 follow-up 2 (P3): the picture memory cache per 30 s line. Each miss gets a class, so the device log tells
/// why the hit rate is low: a new address (cold first load), the address in another size (target mismatch), the same
/// key decoded before and dropped since (memory budget), or a load already running for it. Downloads are split into
/// local (URLCache, its memory or disk part: `.localCache` does not tell them apart) and network (URLSession metrics;
/// downloads without metrics show as the difference), decodes timed (the decode itself and until it is done, with the
/// wait for a utility thread), NSCache releases counted with their bytes (budget pressure only, not deliberate clears).
/// Two candidates for the low hit rate (P3 review I1): cold first loads (`neu`) and budget pressure (`verdrängt`, with
/// `freigegeben`): 4K backdrop originals are ≈ 32 MB each, about 5 swaps fill the 160 MB budget.
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
    public private(set) var fromLocalCache = 0
    public private(set) var fromNetwork = 0
    public private(set) var decodes = 0
    public private(set) var longestDecodeMs = 0
    public private(set) var longestUntilDecodedMs = 0
    /// b5r: decodes that gave a picture (reported pixels), the sum of their decode times and of their pixels; the
    /// line shows both means over this same set (review L3).
    public private(set) var pictureDecodes = 0
    public private(set) var totalDecodeMs = 0
    public private(set) var decodedPixels = 0
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
    /// A download finished: from the URLCache (`local`) or the network.
    public mutating func loaded(local: Bool) { if local { fromLocalCache += 1 } else { fromNetwork += 1 } }
    /// One decode: `ms` the decode itself, `untilDoneMs` from the decode request until its result (thread wait too).
    /// b5r: `pixels` of the decoded bitmap (width × height), 0 when unknown.
    public mutating func decoded(ms: Int, untilDoneMs: Int, pixels: Int = 0) {
        decodes += 1
        if pixels > 0 {
            pictureDecodes += 1
            totalDecodeMs += max(0, ms)
            decodedPixels += pixels
        }
        longestDecodeMs = max(longestDecodeMs, ms)
        longestUntilDecodedMs = max(longestUntilDecodedMs, untilDoneMs)
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
        if fetches > 0 { line += " · Ladungen \(fetches) (lokal \(fromLocalCache) · Netz \(fromNetwork))" }
        if decodes > 0 {
            line += " · dekodiert \(decodes), längstes \(longestDecodeMs) ms (bis fertig \(longestUntilDecodedMs) ms)"
            if pictureDecodes > 0 {
                let tenths = Int((Double(decodedPixels) / Double(pictureDecodes) / 100_000).rounded())
                line += " · Ø \(totalDecodeMs / pictureDecodes) ms · Ø \(tenths / 10),\(tenths % 10) Mpx"
            }
        }
        if releases > 0 { line += " · freigegeben \(releases) (\(PictureArrivalStats.mb(releasedBytes)) MB)" }
        return line
    }
}
