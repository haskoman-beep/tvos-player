import Foundation

/// Eine Folge in Ausstrahlungsreihenfolge (ohne Specials/Staffel 0).
public struct EpisodeRef: Codable, Sendable, Hashable {
    public var season: Int
    public var episode: Int
    public var title: String?

    public init(season: Int, episode: Int, title: String? = nil) {
        self.season = season; self.episode = episode; self.title = title
    }

    public static func list(from videos: [MetaVideo]) -> [EpisodeRef] {
        var seen = Set<[Int]>()
        return videos.compactMap { v -> EpisodeRef? in
            guard let s = v.season, let e = v.episode, s > 0, seen.insert([s, e]).inserted else { return nil }
            return EpisodeRef(season: s, episode: e, title: v.name ?? v.title)
        }
        .sorted { ($0.season, $0.episode) < ($1.season, $1.episode) }
    }

    /// Folge nach (season, episode); nil = Serie zu Ende.
    public static func next(after season: Int, _ episode: Int, in list: [EpisodeRef]) -> EpisodeRef? {
        list.first { ($0.season, $0.episode) > (season, episode) }
    }
}

/// Stream für die nächste Folge: gleiche `bingeGroup` (gleiche Qualität/Quelle) bevorzugt, sonst der erste.
/// Sicher nicht gecachte Quellen ("lädt erst") werden übersprungen, solange es andere gibt.
public func nextEpisodeStream(_ streams: [StreamItem], bingeGroup: String?) -> StreamItem? {
    let all = playableStreams(streams)
    let ready = all.filter { StreamTraits.parse($0).cached != false }
    let playable = ready.isEmpty ? all : ready
    if let g = bingeGroup, let same = playable.first(where: { $0.behaviorHints?.bingeGroup == g }) { return same }
    return playable.first
}
