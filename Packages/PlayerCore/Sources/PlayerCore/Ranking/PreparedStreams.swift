import Foundation

/// Build 4 follow-up S3: a finished source search, prepared off the main thread. The app filters the playable
/// entries, parses their traits and computes the best values in a detached task; on the main thread it only merges
/// the list into the cache and parses the entries kept from the old state (`StreamListMerge.keepingFailed`).
/// The results equal `playableStreams` per addon and `BestQuality.from(RankedStream.rank(_:))` of the stored list.
public struct PreparedStreams: Sendable {
    /// Playable entries (`playableStreams`) in addon order, with the label the caller gave each addon.
    public let list: [(addon: String, stream: StreamItem)]
    /// Traits of `list`, same order, parsed once.
    public let traits: [StreamTraits]
    /// Best values of `list` alone (nil when it is empty).
    public let best: BestQuality?

    public init(_ results: [(addon: String, streams: [StreamItem])]) {
        let list = results.flatMap { r in playableStreams(r.streams).map { (addon: r.addon, stream: $0) } }
        let traits = list.map { StreamTraits.parse($0.stream) }
        self.list = list
        self.traits = traits
        self.best = BestQuality.from(traits)
    }

    /// Best values of the stored list. It begins with `list`, followed by the entries kept for addons without an
    /// answer (`StreamListMerge`): only those are parsed here. Any other list is parsed whole.
    public func best(stored: [(addon: String, stream: StreamItem)]) -> BestQuality? {
        guard stored.count >= list.count,
              zip(stored, list).allSatisfy({ $0.addon == $1.addon && $0.stream == $1.stream }) else {
            return BestQuality.from(RankedStream.rank(stored))
        }
        if stored.count == list.count { return best }
        return BestQuality.from(traits + stored[list.count...].map { StreamTraits.parse($0.stream) })
    }
}

/// S3 review (Minor 1): badge values kept for a stored source list, with the number of entries they were computed
/// from. Reading the list later drops kept entries of an addon without answer once their own fetch is `usableFor`
/// old (`StreamListMerge.usable`); with fewer usable entries the values may stem from sources the list no longer
/// offers (DV, Atmos of an expired entry) and lapse, so the caller computes them again from what is left. Reading
/// only ever removes entries, so an equal count means the same entries.
public struct CachedBest: Equatable, Sendable {
    public let best: BestQuality
    public let entries: Int

    public init(best: BestQuality, entries: Int) {
        self.best = best
        self.entries = entries
    }

    public func isCurrent(usableEntries: Int) -> Bool { usableEntries == entries }
}
