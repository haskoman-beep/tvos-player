import Foundation

// Nuvio account sync, T6: latest-wins push buffer (plan section 1.8). Progress is state, not history: only the
// newest value per progress key matters, so one entry per key and a newer one replaces the older. The buffer lives
// in the per-profile state blob, survives offline time and goes out at the next trigger; there is no timer.

public struct NuvioOutbox: Codable, Equatable, Sendable {
    /// While playing, at most one push per this many seconds (`force` skips it: pause, stop, before a pull).
    public static let interval: TimeInterval = 60
    public static let maxEntries = 200
    public static let maxAge: TimeInterval = 30 * 86400

    /// Why the entry is queued. `watched`: the app marked the title watched (80 % rule of Trakt/Simkl, or by hand);
    /// it is sent as position = duration so the account records it as complete (addendum A8).
    public enum Kind: String, Codable, Sendable { case progress, watched }

    public struct Entry: Codable, Equatable, Sendable {
        public var push: NuvioProgressPush
        public var kind: Kind
        /// When the app queued it (for `maxAge` and the overflow order).
        public var notedAt: Date

        public init(push: NuvioProgressPush, kind: Kind, notedAt: Date) {
            self.push = push; self.kind = kind; self.notedAt = notedAt
        }

        enum CodingKeys: String, CodingKey { case push, kind, notedAt }

        /// An unknown kind (newer build) reads as `progress`; a missing or broken date reads as the reference date
        /// (2001), so the next `prune` drops the entry.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            push = try c.decode(NuvioProgressPush.self, forKey: .push)
            kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .progress
            notedAt = (try? c.decodeIfPresent(Date.self, forKey: .notedAt)) ?? Date(timeIntervalSinceReferenceDate: 0)
        }
    }

    /// Progress key → newest entry.
    public private(set) var entries: [String: Entry] = [:]
    /// Last send attempt, successful or not (throttle).
    public private(set) var lastAttemptAt: Date?

    public init() {}

    enum CodingKeys: String, CodingKey { case entries, lastAttemptAt }

    /// One unreadable entry is dropped, the rest stays; a missing or broken field gives its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = ((try? c.decodeIfPresent([String: Lossy<Entry>].self, forKey: .entries)) ?? [:]).compactMapValues(\.value)
        lastAttemptAt = (try? c.decodeIfPresent(Date.self, forKey: .lastAttemptAt)) ?? nil
    }

    public var keys: Set<String> { Set(entries.keys) }
    public var isEmpty: Bool { entries.isEmpty }

    /// The progress key of a push (computed locally, never sent).
    public static func key(_ p: NuvioProgressPush) -> String {
        NuvioMapping.progressKey(contentID: p.contentID, season: p.season, episode: p.episode)
    }

    /// Queues a push under its progress key. A note with an older `lastWatched` than the queued one is ignored; an
    /// equal or newer one replaces it. Beyond `maxEntries` the oldest notes go.
    public mutating func note(_ push: NuvioProgressPush, kind: Kind = .progress, now: Date) {
        var p = push
        if kind == .watched { p.position = p.duration }
        let k = Self.key(p)
        if let old = entries[k], old.push.lastWatched > p.lastWatched { return }
        entries[k] = Entry(push: p, kind: kind, notedAt: now)
        trim()
    }

    /// Something to send, and either `force` or the last attempt is at least `interval` ago (or in the future: a clock
    /// that went back never blocks sending).
    public func isDue(now: Date, force: Bool) -> Bool {
        guard !entries.isEmpty else { return false }
        guard !force, let last = lastAttemptAt else { return true }
        let gap = now.timeIntervalSince(last)
        return gap < 0 || gap >= Self.interval
    }

    /// Everything to send in one `p_entries` array, oldest `lastWatched` first, at most `maxEntries`.
    public func batch() -> [(key: String, entry: NuvioProgressPush)] {
        entries.sorted { a, b in
            a.value.push.lastWatched != b.value.push.lastWatched ? a.value.push.lastWatched < b.value.push.lastWatched : a.key < b.key
        }.prefix(Self.maxEntries).map { (key: $0.key, entry: $0.value.push) }
    }

    /// The account took `sent` (204). An entry replaced while the request was in flight stays.
    public mutating func confirm(_ sent: [(key: String, entry: NuvioProgressPush)], now: Date) {
        for s in sent where entries[s.key]?.push == s.entry { entries[s.key] = nil }
        lastAttemptAt = now
    }

    /// A send failed (offline, 429, 5xx …): everything stays, the throttle starts again.
    public mutating func failed(now: Date) { lastAttemptAt = now }

    /// Drops entries queued more than `maxAge` ago and the oldest beyond `maxEntries`.
    public mutating func prune(now: Date) {
        entries = entries.filter { now.timeIntervalSince($0.value.notedAt) <= Self.maxAge }
        trim()
    }

    /// Drops every entry of these content ids (all episodes of a series). Returns how many went.
    @discardableResult
    public mutating func remove(contentIDs: Set<String>) -> Int {
        let before = entries.count
        entries = entries.filter { !contentIDs.contains($0.value.push.contentID) }
        return before - entries.count
    }

    /// Sign-out or account change.
    public mutating func removeAll() { entries = [:] }

    private mutating func trim() {
        guard entries.count > Self.maxEntries else { return }
        let gone = entries.sorted { a, b in
            a.value.notedAt != b.value.notedAt ? a.value.notedAt < b.value.notedAt : a.key < b.key
        }.prefix(entries.count - Self.maxEntries).map(\.key)
        for k in gone { entries[k] = nil }
    }
}
