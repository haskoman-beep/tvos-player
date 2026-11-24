import Foundation

/// Task 3.1: the profile and epoch a task started in. A task that awaits and then writes profile data remembers
/// `scopes.current` before the first `await` and checks `isCurrent` afterwards; a stale result is discarded.
public struct ProfileScope: Sendable, Hashable {
    public let profile: UUID
    public let epoch: Int

    public init(profile: UUID, epoch: Int) {
        self.profile = profile; self.epoch = epoch
    }
}

/// Task 3.1: hands out the current scope. `advance(to:)` on a profile switch, `bump()` when the profile's data
/// changes underneath running tasks (language, addon set, backup import). Every call starts a new epoch, so a
/// switch A → B → A still ends the first epoch of A.
public struct ScopeClock: Sendable {
    public private(set) var current: ProfileScope

    public init(profile: UUID) { current = ProfileScope(profile: profile, epoch: 0) }

    public mutating func advance(to profile: UUID) {
        current = ProfileScope(profile: profile, epoch: current.epoch + 1)
    }

    public mutating func bump() {
        current = ProfileScope(profile: current.profile, epoch: current.epoch + 1)
    }

    public func isCurrent(_ s: ProfileScope) -> Bool { s == current }
}

/// Task 3.1 (A-A-12, A-B-2): key of the TMDB text caches; texts depend on the language, episode names also on
/// the season.
public struct TextCacheKey: Sendable, Hashable {
    public let imdb: String
    public let language: String
    public let season: Int?

    public init(imdb: String, language: String, season: Int? = nil) {
        self.imdb = imdb; self.language = language; self.season = season
    }
}

/// Task 3.1: a bounded cache whose entries belong to one scope. Reading in another scope forgets everything
/// (nothing of profile A, or of an old language or addon set, is shown in the new one); a result that started in
/// an older scope is not stored. Over `limit` the oldest stored entry goes.
public struct ScopedCache<Key: Hashable, Value> {
    public let limit: Int
    private var scope: ProfileScope?
    private var entries: [Key: Value] = [:]
    private var order: [Key] = []

    public init(limit: Int) { self.limit = max(1, limit) }

    public var count: Int { entries.count }

    /// Entry for `key`, if it was stored in `scope`; entries of an older scope are dropped here.
    public mutating func value(for key: Key, in scope: ProfileScope) -> Value? {
        adopt(scope)
        return entries[key]
    }

    /// Stores `value` if the task that produced it (`origin`) is still `current`. false = discarded.
    @discardableResult
    public mutating func store(_ value: Value, for key: Key, from origin: ProfileScope, current: ProfileScope) -> Bool {
        adopt(current)
        guard origin == current else { return false }
        if entries.updateValue(value, forKey: key) == nil {
            order.append(key)
            if order.count > limit { entries[order.removeFirst()] = nil }
        }
        return true
    }

    public mutating func removeAll() {
        entries.removeAll(); order.removeAll()
    }

    private mutating func adopt(_ s: ProfileScope) {
        guard scope != s else { return }
        scope = s
        removeAll()
    }
}

extension ScopedCache: Sendable where Key: Sendable, Value: Sendable {}

/// Task 3.1 (S-4): a renewed sync token goes into the profile the renewal started for (by ID, active or not), but
/// only while that profile still holds the token that was renewed. After „Abmelden“, a new login or a restore
/// without that profile nothing is written.
public enum SyncTokenWriteBack {
    @discardableResult
    public static func apply(_ new: SyncToken, replacing old: SyncToken, service: String, profile id: UUID,
                             in profiles: inout [Profile]) -> Bool {
        guard let i = profiles.firstIndex(where: { $0.id == id }), profiles[i].syncTokens[service] == old else { return false }
        profiles[i].syncTokens[service] = new
        return true
    }
}
