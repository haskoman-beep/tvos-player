import Foundation

/// Task 3.8 ([04 §6.2]): a source plus its traits, parsed once. Ordering (`SourceRanking`, `StreamListOrder`),
/// „Beste Wahl“ (`BestChoice`, `LastSource.match`) and badges (`BestQuality`, `DetailQuality`) take it as it is,
/// so a list of 40 sources is parsed 40 times instead of several times per source.
public struct RankedStream: Equatable, Sendable {
    public var addon: String
    public var stream: StreamItem
    /// Parsed from `stream` when built with `init(addon:stream:)`; never parsed again downstream.
    public var traits: StreamTraits

    public init(addon: String, stream: StreamItem) {
        self.init(addon: addon, stream: stream, traits: StreamTraits.parse(stream))
    }

    public init(addon: String, stream: StreamItem, traits: StreamTraits) {
        self.addon = addon; self.stream = stream; self.traits = traits
    }

    /// The plain entry the app keeps in its lists.
    public var entry: (addon: String, stream: StreamItem) { (addon, stream) }

    /// One parse per entry, order unchanged.
    public static func rank(_ list: [(addon: String, stream: StreamItem)]) -> [RankedStream] {
        list.map { RankedStream(addon: $0.addon, stream: $0.stream) }
    }
}

extension SourceRanking {
    public static func order(_ ranked: [RankedStream], context: SourceRankContext) -> [RankedStream] {
        order(ranked, context: context, traits: \.traits)
    }
}

extension StreamDedupe {
    /// Same rule as the tuple form; the carried traits stay with their entry.
    public static func unique(_ ranked: [RankedStream]) -> [RankedStream] {
        unique(ranked.map { (addon: $0.addon, stream: $0) }) { $0.stream }.map(\.stream)
    }
}

extension StreamListOrder {
    /// Like the tuple form, for an already de-duplicated list.
    public static func ordered(_ unique: [RankedStream], mode: StreamOrderMode, context: SourceRankContext) -> [RankedStream] {
        mode == .smart && unique.count > 1 ? SourceRanking.order(unique, context: context) : unique
    }

    /// Like the tuple form: duplicates out, then always `SourceRanking`.
    public static func automatic(_ ranked: [RankedStream], context: SourceRankContext) -> [RankedStream] {
        let u = StreamDedupe.unique(ranked)
        return u.count > 1 ? SourceRanking.order(u, context: context) : u
    }
}

extension BestQuality {
    public static func from(_ ranked: [RankedStream]) -> BestQuality? { from(ranked.map(\.traits)) }
}

extension DetailQuality {
    public static func from(_ ranked: [RankedStream]) -> DetailQuality? { from(ranked.map(\.traits)) }
}

extension LastSource {
    /// Same rules as `match(in:)` on plain entries, with the carried traits (cache state, resolution).
    public func match(in ranked: [RankedStream]) -> StreamItem? {
        let list = ranked.filter { $0.stream.url != nil }
        if let e = list.first(where: { Self.fileKey($0.stream) == fingerprint }) { return e.stream }
        let ready = list.filter { $0.traits.cached != false }
        if let g = bingeGroup, let e = ready.first(where: { $0.stream.behaviorHints?.bingeGroup == g }) { return e.stream }
        let res = StreamTraits.parse(StreamItem(name: name, title: fingerprint)).resolution
        if let e = ready.first(where: { $0.addon == addon && $0.stream.name == name && $0.traits.resolution == res }) {
            return e.stream
        }
        return nil
    }

    static func fileKey(_ s: StreamItem) -> String { s.behaviorHints?.filename ?? s.label }
}
