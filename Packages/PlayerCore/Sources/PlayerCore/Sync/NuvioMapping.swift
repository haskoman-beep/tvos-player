import Foundation

// Nuvio account sync, T4: ids, units and keys between the app and the account (plan section 1.5). Pure functions,
// no I/O. The account counts in milliseconds, the app in seconds; the app's progress ids are `tt…`/`tmdb:N` for a
// film and `<item>:<season>:<episode>` for an episode.

/// One pulled title in the app's units, ready for `ProgressBook.merge(nuvio:)`. `id` is the local progress id
/// (`tt…` or `tt…:S:E`), `item` the tile entry (the series for an episode). `watched`: the account holds a
/// watched-history item for it (otherwise "finished" follows from position and duration).
public struct NuvioProgressEntry: Equatable, Sendable {
    public var id: String
    public var item: MetaPreview
    public var season: Int?
    public var episode: Int?
    /// Seconds.
    public var position: Double
    /// Seconds; 0 = unknown.
    public var duration: Double
    public var updated: Date
    public var watched: Bool

    public init(id: String, item: MetaPreview, season: Int? = nil, episode: Int? = nil, position: Double,
                duration: Double, updated: Date, watched: Bool = false) {
        self.id = id; self.item = item; self.season = season; self.episode = episode
        self.position = position; self.duration = duration; self.updated = updated; self.watched = watched
    }
}

public enum NuvioMapping {
    /// The forms a `content_id` can take for the app.
    public enum RemoteID: Equatable, Sendable {
        /// `tt…`: kept as the local id.
        case imdb(String)
        /// `tmdb:N`: the app looks up the IMDb id, or keeps `tmdb:N` as the item id.
        case tmdb(Int)
        /// Anything else (`kitsu:`, `mal:`, addon ids): skipped and counted.
        case other(String)
    }

    public static func remoteID(_ contentID: String) -> RemoteID {
        let s = contentID.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("tt"), s.count > 2, s.dropFirst(2).allSatisfy(\.isASCIIDigit) { return .imdb(s) }
        if s.hasPrefix("tmdb:"), let n = digits(s.dropFirst(5)), n > 0 { return .tmdb(n) }
        return .other(s)
    }

    /// The documented progress key: film `{content_id}`, episode `{content_id}_s{season}e{episode}`.
    public static func progressKey(contentID: String, season: Int?, episode: Int?) -> String {
        NuvioProgressRow.key(contentID: contentID, season: season, episode: episode)
    }

    /// The inverse of `progressKey`. A key without a well-formed `_s<digits>e<digits>` suffix is a film key.
    public static func parseKey(_ key: String) -> (contentID: String, season: Int?, episode: Int?) {
        guard let r = key.range(of: "_s", options: .backwards), r.lowerBound > key.startIndex else { return (key, nil, nil) }
        let tail = key[r.upperBound...]
        guard let e = tail.firstIndex(of: "e"), let s = digits(tail[..<e]),
              let ep = digits(tail[tail.index(after: e)...]) else { return (key, nil, nil) }
        return (String(key[..<r.lowerBound]), s, ep)
    }

    /// `video_id` of a push: `content_id` for a film, `<content_id>:<season>:<episode>` for an episode.
    public static func videoID(contentID: String, season: Int?, episode: Int?) -> String {
        guard let s = season, let e = episode else { return contentID }
        return "\(contentID):\(s):\(e)"
    }

    /// The app's progress id: the item id for a film, `<item>:<season>:<episode>` for an episode.
    public static func localProgressID(itemID: String, season: Int?, episode: Int?) -> String {
        guard let s = season, let e = episode else { return itemID }
        return "\(itemID):\(s):\(e)"
    }

    public static func seconds(ms: Int) -> Double { Double(ms) / 1000 }

    /// nil when not finite, negative, or too large for the account's integer.
    public static func ms(seconds: Double) -> Int? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        let v = (seconds * 1000).rounded()
        guard v < 9.0e15 else { return nil }   // far beyond any real length; keeps the conversion exact and safe
        return Int(v)
    }

    /// Epoch milliseconds (`last_watched`).
    public static func epochMS(_ date: Date) -> Int {
        Int((ProgressNumbers.date(date).timeIntervalSince1970 * 1000).rounded())
    }

    public static func date(ms: Int) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }

    /// The push row for a local entry, or nil when the entry cannot be addressed on the account: no content id, a
    /// length that is not finite and > 0 (streams without a known length are never pushed), a position that is not
    /// finite, or a whole-series marker. The position is clamped to `0…duration`; a finished entry (stored with
    /// position 0) is sent as position = duration, so the account records it as complete (addendum A8).
    public static func push(_ p: WatchProgress, contentID: String) -> NuvioProgressPush? {
        let cid = contentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty, p.duration.isFinite, p.duration > 0, p.position.isFinite else { return nil }
        let ep = episode(type: p.item.type, season: p.season, episode: p.episode)
        if ep == nil, ContentKind.isEpisodic(type: p.item.type) { return nil }
        let position = p.finished ? p.duration : min(max(p.position, 0), p.duration)
        guard let d = ms(seconds: p.duration), let pos = ms(seconds: position) else { return nil }
        return NuvioProgressPush(contentID: cid, contentType: ep == nil ? "movie" : "series",
                                 videoID: videoID(contentID: cid, season: ep?.season, episode: ep?.episode),
                                 season: ep?.season, episode: ep?.episode, position: min(pos, d), duration: d,
                                 lastWatched: epochMS(p.updated))
    }

    /// A pulled progress row as a local entry. `itemID`: the local item id the caller resolved for the row's
    /// `content_id` (`tt…` or `tmdb:N`). `name`: the title when known (progress rows carry none). A `last_watched` in
    /// the future is clamped to `now`. nil for a series row without an episode, or an empty item id.
    public static func entry(_ row: NuvioProgressRow, itemID: String, name: String?, now: Date) -> NuvioProgressEntry? {
        guard !itemID.isEmpty else { return nil }
        let ep = episode(type: row.contentType, season: row.season, episode: row.episode)
        if ep == nil, ContentKind.isEpisodic(type: row.contentType) { return nil }
        let duration = row.duration > 0 ? seconds(ms: row.duration) : 0
        var position = row.position > 0 ? seconds(ms: row.position) : 0
        if duration > 0 { position = min(position, duration) }
        return NuvioProgressEntry(id: localProgressID(itemID: itemID, season: ep?.season, episode: ep?.episode),
                                  item: meta(itemID, series: ep != nil, name: name), season: ep?.season,
                                  episode: ep?.episode, position: position, duration: duration,
                                  updated: clamped(row.lastWatched, now: now))
    }

    /// A pulled watched-history item as a finished local entry (position and length unknown). A film's `title` becomes
    /// the name; an episode gets none (its `title` may be "Show S01E01", review 2 finding 5), so it waits for the
    /// series title. nil for a whole-series item (no episode, plan section 7.8) or an empty item id.
    public static func entry(_ watched: NuvioWatchedItem, itemID: String, now: Date) -> NuvioProgressEntry? {
        guard !itemID.isEmpty else { return nil }
        let ep = episode(type: watched.contentType, season: watched.season, episode: watched.episode)
        if ep == nil, ContentKind.isEpisodic(type: watched.contentType) { return nil }
        return NuvioProgressEntry(id: localProgressID(itemID: itemID, season: ep?.season, episode: ep?.episode),
                                  item: meta(itemID, series: ep != nil, name: ep == nil ? watched.title : nil), season: ep?.season,
                                  episode: ep?.episode, position: 0, duration: 0,
                                  updated: clamped(watched.watchedAt, now: now), watched: true)
    }

    // MARK: Helpers

    /// Season and episode when the row is an episode: both present and ≥ 0, and the type is not `movie`. An unknown
    /// type with season and episode counts as an episode.
    static func episode(type: String, season: Int?, episode: Int?) -> (season: Int, episode: Int)? {
        guard type.trimmingCharacters(in: .whitespaces).lowercased() != "movie",
              let s = season, let e = episode, s >= 0, e >= 0 else { return nil }
        return (s, e)
    }

    static func meta(_ itemID: String, series: Bool, name: String?) -> MetaPreview {
        let imdb: Bool = if case .imdb = remoteID(itemID) { true } else { false }
        return MetaPreview(id: itemID, type: series ? "series" : "movie", name: name ?? "",
                           poster: imdb ? metahubPoster(itemID) : nil, background: imdb ? metahubBackground(itemID) : nil)
    }

    static func clamped(_ ms: Int, now: Date) -> Date { min(ProgressNumbers.date(date(ms: ms)), now) }

    private static func digits<S: StringProtocol>(_ s: S) -> Int? {
        guard !s.isEmpty, s.count <= 18, s.allSatisfy(\.isASCIIDigit) else { return nil }
        return Int(s)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
