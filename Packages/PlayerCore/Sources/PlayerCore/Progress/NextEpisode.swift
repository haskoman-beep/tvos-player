import Foundation

/// Eine Folge in Ausstrahlungsreihenfolge (ohne Specials/Staffel 0).
public struct EpisodeRef: Codable, Sendable, Hashable {
    public var season: Int
    public var episode: Int
    public var title: String?

    public init(season: Int, episode: Int, title: String? = nil) {
        self.season = season; self.episode = episode; self.title = title
    }

    /// Folgenliste ohne Specials und ohne noch nicht ausgestrahlte Folgen (released in der Zukunft).
    public static func list(from videos: [MetaVideo], now: Date = Date()) -> [EpisodeRef] {
        var seen = Set<[Int]>()
        return videos.compactMap { v -> EpisodeRef? in
            guard let s = v.season, let e = v.episode, s > 0 else { return nil }
            if let r = v.released, let d = releaseDate(r), d > now { return nil }
            guard seen.insert([s, e]).inserted else { return nil }
            return EpisodeRef(season: s, episode: e, title: v.name ?? v.title)
        }
        .sorted { ($0.season, $0.episode) < ($1.season, $1.episode) }
    }

    static func releaseDate(_ s: String) -> Date? {
        ISODate.parse(s)
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

extension ProgressBook {
    /// Welche Folge „Abspielen“ startet (wie Weiterschauen): die angefangene Folge, nach einer gesehenen die nächste,
    /// sonst (nie gestartet oder Serie zu Ende) die erste Folge, ohne Folgenliste S1F1.
    public func nextOpenEpisode(seriesID: String, in episodes: [EpisodeRef]) -> EpisodeRef {
        let first = episodes.first ?? EpisodeRef(season: 1, episode: 1)
        guard let e = latest(forItem: seriesID), let s = e.season, let ep = e.episode else { return first }
        if !e.finished { return EpisodeRef(season: s, episode: ep) }
        return EpisodeRef.next(after: s, ep, in: episodes) ?? first
    }
}
