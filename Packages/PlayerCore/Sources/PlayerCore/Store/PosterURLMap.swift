import Foundation

/// Build 8 (poster): the metadata addon's poster address per tile (key = addon | type | id, as `AddonMetaCache`),
/// kept on disk so a second visit of a studio or genre page shows the rating posters at once instead of asking the
/// addon for every title again. Bounded (least recently used goes first) and aged: a poster 7 days, "the addon has
/// no poster" 1 day. Failed or cancelled requests are never stored here.
public struct PosterURLMap: Sendable, Equatable {
    public static let defaultLimit = 5000
    public static let posterTTL: TimeInterval = 7 * 24 * 3600
    public static let noPosterTTL: TimeInterval = 24 * 3600
    static let version = 1

    public enum Hit: Sendable, Equatable {
        case poster(String)
        /// The addon answered without a poster: keep the TMDB poster, ask no more.
        case noPoster
    }

    struct Entry: Codable, Sendable, Equatable {
        var url: String?
        /// When the addon answered.
        var at: Date
        /// Last use (insert or hit), for the least-recently-used order.
        var used: UInt64
    }

    public let limit: Int
    private(set) var entries: [String: Entry] = [:]
    private var clock: UInt64 = 0
    /// Changed since the last `encoded()` (the app writes only then).
    public private(set) var dirty = false

    public init(limit: Int = defaultLimit) { self.limit = max(1, limit) }

    public var count: Int { entries.count }

    /// Valid entry for `key` (counts as a use); an aged one is dropped.
    public mutating func lookup(_ key: String, now: Date = Date()) -> Hit? {
        guard var e = entries[key] else { return nil }
        guard Self.isFresh(e, now: now) else { entries[key] = nil; dirty = true; return nil }
        clock += 1
        e.used = clock
        entries[key] = e
        return e.url.map(Hit.poster) ?? .noPoster
    }

    /// Without counting as a use (body passes, logging).
    public func peek(_ key: String, now: Date = Date()) -> Hit? {
        guard let e = entries[key], Self.isFresh(e, now: now) else { return nil }
        return e.url.map(Hit.poster) ?? .noPoster
    }

    /// The addon's answer for `key`: its poster address, or nil when it has none. An empty address counts as none.
    public mutating func store(_ key: String, poster: String?, now: Date = Date()) {
        clock += 1
        let url = poster.flatMap { $0.isEmpty ? nil : $0 }
        entries[key] = Entry(url: url, at: now, used: clock)
        dirty = true
        if entries.count > limit { evict() }
    }

    /// Over the limit: drops the least recently used entries down to 95 % of it (one sort per 5 % of inserts, not per
    /// insert).
    private mutating func evict() {
        guard entries.count > limit else { return }
        let over = entries.count - (limit - limit / 20)
        let oldest = entries.sorted { $0.value.used < $1.value.used }.prefix(over).map(\.key)
        for k in oldest { entries[k] = nil }
    }

    static func isFresh(_ e: Entry, now: Date) -> Bool {
        let age = now.timeIntervalSince(e.at)
        return age >= 0 && age < (e.url == nil ? noPosterTTL : posterTTL)
    }

    // MARK: Disk

    private struct File: Codable {
        var version: Int
        var entries: [String: Entry]
    }

    /// JSON for the disk file (review: callable on a copy off the main thread). Aged entries are left out.
    public func encoded(now: Date = Date()) -> Data? {
        let live = entries.filter { Self.isFresh($0.value, now: now) }
        return try? JSONEncoder().encode(File(version: Self.version, entries: live))
    }

    /// The current state is being written (the copy carries it).
    public mutating func markClean() { dirty = false }

    /// Reads a disk file: aged entries dropped, over the limit the least recently used go. nil = unreadable or an
    /// older version (the app then removes the file).
    public static func decode(_ data: Data, limit: Int = defaultLimit, now: Date = Date()) -> PosterURLMap? {
        guard let f = try? JSONDecoder().decode(File.self, from: data), f.version == version else { return nil }
        var m = PosterURLMap(limit: limit)
        m.entries = f.entries.filter { isFresh($0.value, now: now) }
        m.clock = m.entries.values.map(\.used).max() ?? 0
        m.evict()
        return m
    }

    /// Entries read from disk join what this launch already learned (this launch wins, it is newer).
    /// The older entries count as used before every entry of this launch.
    public mutating func merge(_ older: PosterURLMap) {
        let shift = older.clock
        for k in entries.keys { entries[k]?.used += shift }
        for (k, e) in older.entries where entries[k] == nil { entries[k] = e }
        clock += shift
        if entries.count > limit { evict() }
    }
}
