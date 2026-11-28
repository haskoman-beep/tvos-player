import Foundation

// Nuvio account sync, T6: per-profile, non-secret state (plan section 1.3), blob `nuvio-<profile uuid>.json`.
// `ProfileBlocks.belongs` matches the name, so the blob goes with its local profile; it is not part of `Backup`.
// No token, no e-mail address and no PIN or addon flag of the account in here: the profile list is read fresh on every
// pass (addendum A3).

/// A local "remove from continue watching" or "mark unwatched" (addendum A4). Pulled rows of the title that are not
/// newer than `at` are dropped, so a pull cannot bring back what the user removed. Nothing is deleted on the account.
public struct NuvioTombstone: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Blocks unfinished rows only; watched history still comes in (the local removal keeps history too).
        case removedFromContinue
        /// Blocks every row of the title.
        case markedUnwatched
    }

    /// Local item id of the title (`tt…` or `tmdb:N`; the series for episodes).
    public var itemID: String
    public var kind: Kind
    public var at: Date

    public init(itemID: String, kind: Kind, at: Date) {
        self.itemID = itemID; self.kind = kind; self.at = at
    }
}

/// A pulled row that waits for its title before it is merged (plan section 1.9): no tile without a title.
public struct NuvioStaged: Codable, Equatable, Sendable {
    /// Local item id the row was resolved to.
    public var itemID: String
    public var row: NuvioProgressRow?
    public var watched: NuvioWatchedItem?
    public var stagedAt: Date

    public init(itemID: String, row: NuvioProgressRow? = nil, watched: NuvioWatchedItem? = nil, stagedAt: Date) {
        self.itemID = itemID; self.row = row; self.watched = watched; self.stagedAt = stagedAt
    }

    /// Progress key of the row (a progress row and a watched item of one key are separate entries, see `id`).
    public var key: String {
        if let row { return row.progressKey }
        guard let w = watched else { return itemID }
        return NuvioMapping.progressKey(contentID: w.contentID, season: w.season, episode: w.episode)
    }

    public var id: String { (row != nil ? "p:" : "w:") + key }

    /// Epoch ms of the remote change (newest first when resolving and bounding).
    public var lastWatched: Int { row?.lastWatched ?? watched?.watchedAt ?? 0 }
}

/// Result of checking the stored profile choice against a fresh `sync_pull_profiles` list (addendum A3, D3).
public enum NuvioProfileCheck: Equatable, Sendable {
    /// Sync may run. The fresh profile (nil: an account without profile rows, index 1, plan section 7.10); read
    /// `usesPrimaryAddons` from it, never from the state.
    case ok(NuvioProfile?)
    /// No Nuvio profile chosen yet.
    case notChosen
    /// No profile at the stored index any more → stop sync, "Nuvio-Profil wählen".
    case missing
    /// The index now holds another profile (other id) → stop sync, "Nuvio-Profil wählen".
    case replaced
    /// The profile is PIN-protected now (D3) → stop sync, "Profil ist PIN-geschützt".
    case pinProtected
}

public struct NuvioState: Codable, Equatable, Sendable {
    public static let maxStaged = 300
    public static let maxTombstones = 200
    public static let tombstoneMaxAge: TimeInterval = 30 * 86400

    /// Account the state belongs to (compared at sign-in; another account resets it).
    public var userID: String?
    /// Chosen account profile (1…6) and its remote `id` (addendum A3; nil for an account without profile rows).
    public var profileIndex: Int?
    public var profileID: String?
    public var progressCursor: Int?
    public var watchedCursor: Int?
    public var bootstrapDone = false
    public var lastPullAt: Date?
    /// Local item id → `content_id` as the account has it, so a push uses the same key as the pulled row.
    public var remoteIDs: [String: String] = [:]
    public var outbox = NuvioOutbox()
    public var staged: [NuvioStaged] = []
    /// Pulled rows the app could not address (other id schemes, whole-series rows), shown as a number.
    public var skipped = 0
    public var tombstones: [NuvioTombstone] = []

    public init() {}

    enum CodingKeys: String, CodingKey {
        case userID, profileIndex, profileID, progressCursor, watchedCursor, bootstrapDone, lastPullAt, remoteIDs
        case outbox, staged, skipped, tombstones
    }

    /// Field by field: an unknown field is ignored, a missing or unreadable one takes its default, one unreadable
    /// staged row or tombstone is dropped alone.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func field<T: Decodable>(_ k: CodingKeys, _ t: T.Type) -> T? { (try? c.decodeIfPresent(T.self, forKey: k)) ?? nil }
        userID = field(.userID, String.self)
        profileIndex = field(.profileIndex, Int.self)
        profileID = field(.profileID, String.self)
        progressCursor = field(.progressCursor, Int.self)
        watchedCursor = field(.watchedCursor, Int.self)
        bootstrapDone = field(.bootstrapDone, Bool.self) ?? false
        lastPullAt = field(.lastPullAt, Date.self)
        remoteIDs = field(.remoteIDs, [String: String].self) ?? [:]
        outbox = field(.outbox, NuvioOutbox.self) ?? NuvioOutbox()
        staged = (field(.staged, [Lossy<NuvioStaged>].self) ?? []).compactMap(\.value)
        skipped = field(.skipped, Int.self) ?? 0
        tombstones = (field(.tombstones, [Lossy<NuvioTombstone>].self) ?? []).compactMap(\.value)
    }

    // MARK: Resets

    /// Another account signed in: nothing of the old account stays (profile choice, cursors, ids, outbox, staged
    /// rows, counter). Tombstones stay: they are local decisions of this profile, not account data.
    public mutating func resetForAccount(_ userID: String) {
        let keep = tombstones
        self = NuvioState()
        self.userID = userID
        tombstones = keep
    }

    /// The book was replaced (restore): pull from scratch, keep the profile choice and the outbox.
    public mutating func resetCursors() {
        progressCursor = nil
        watchedCursor = nil
        bootstrapDone = false
        lastPullAt = nil
    }

    /// The user picked an account profile. The same profile (index and id) changes nothing; another one starts
    /// over, so nothing meant for the old profile is pushed into the new one.
    public mutating func choose(_ profile: NuvioProfile) {
        let id = profile.id.isEmpty ? nil : profile.id
        if profileIndex == profile.profileIndex, profileID == id { return }
        let keep = (userID, tombstones)
        self = NuvioState()
        (userID, tombstones) = keep
        profileIndex = profile.profileIndex
        profileID = id
    }

    /// Back to "Nuvio-Profil wählen" (mismatch or PIN, A3/D3). The rest stays until another profile is chosen.
    public mutating func clearProfile() {
        profileIndex = nil
        profileID = nil
    }

    // MARK: Profile check (A3, D3)

    /// Checks the stored choice against a fresh profile list.
    public func matches(_ remote: [NuvioProfile]) -> NuvioProfileCheck {
        guard let index = profileIndex else { return .notChosen }
        guard let p = remote.first(where: { $0.profileIndex == index }) else {
            // An account without profile rows: only the guessed index 1 without an id works (plan section 7.10).
            return remote.isEmpty && index == 1 && profileID == nil ? .ok(nil) : .missing
        }
        if let id = profileID, !p.id.isEmpty, p.id != id { return .replaced }
        if p.pinEnabled { return .pinProtected }
        return .ok(p)
    }

    // MARK: Staged rows

    /// Keeps a row until its title is known. Same row again: the newer stays. Beyond `maxStaged` the oldest
    /// (`lastWatched`) go.
    public mutating func stage(_ s: NuvioStaged) {
        if let i = staged.firstIndex(where: { $0.id == s.id }) {
            if staged[i].lastWatched > s.lastWatched { return }
            staged.remove(at: i)
        }
        staged.append(s)
        guard staged.count > Self.maxStaged else { return }
        staged.sort { $0.lastWatched != $1.lastWatched ? $0.lastWatched > $1.lastWatched : $0.id < $1.id }
        staged.removeLast(staged.count - Self.maxStaged)
    }

    /// The row was merged (or given up).
    public mutating func unstage(_ s: NuvioStaged) { staged.removeAll { $0.id == s.id } }

    // MARK: Tombstones (A4)

    /// Records a local removal; it replaces an older tombstone of the title. Pending pushes of the title go too
    /// (they would put back what the user just removed). Beyond `maxTombstones` the oldest go.
    public mutating func tombstone(itemID: String, kind: NuvioTombstone.Kind, at: Date) {
        tombstones.removeAll { $0.itemID == itemID }
        tombstones.append(NuvioTombstone(itemID: itemID, kind: kind, at: at))
        outbox.remove(contentIDs: Set([itemID] + [remoteIDs[itemID]].compactMap { $0 }))
        guard tombstones.count > Self.maxTombstones else { return }
        tombstones.sort { $0.at != $1.at ? $0.at < $1.at : $0.itemID < $1.itemID }
        tombstones.removeFirst(tombstones.count - Self.maxTombstones)
    }

    /// Filters pulled entries with the tombstones (call before `ProgressBook.merge(nuvio:)`). A row not newer than
    /// its title's tombstone is dropped (a `removedFromContinue` one lets finished rows pass); a strictly newer row
    /// passes and clears the tombstone. All rows are judged against the tombstones as they were before the call.
    public mutating func filterPulled(_ pulled: [NuvioProgressEntry]) -> [NuvioProgressEntry] {
        guard !tombstones.isEmpty else { return pulled }
        let byItem = Dictionary(tombstones.map { ($0.itemID, $0) }) { a, b in a.at >= b.at ? a : b }
        var cleared = Set<String>()
        let out = pulled.filter { e in
            guard let t = byItem[e.item.id] ?? byItem[e.id] else { return true }
            if e.updated > t.at { cleared.insert(t.itemID); return true }
            return t.kind == .removedFromContinue && Self.isFinished(e)
        }
        if !cleared.isEmpty { tombstones.removeAll { cleared.contains($0.itemID) } }
        return out
    }

    /// Drops tombstones older than `tombstoneMaxAge` and prunes the outbox.
    public mutating func prune(now: Date) {
        tombstones.removeAll { now.timeIntervalSince($0.at) > Self.tombstoneMaxAge }
        outbox.prune(now: now)
    }

    static func isFinished(_ e: NuvioProgressEntry) -> Bool {
        e.watched || (e.duration.isFinite && e.duration > 0 && e.position / e.duration >= ProgressBook.finishedAt)
    }
}

/// Reads and writes `nuvio-<profile uuid>.json`.
public struct NuvioStateStore: Sendable {
    public let storage: BlobStorage
    public init(storage: BlobStorage) { self.storage = storage }

    public static func name(_ profile: UUID) -> String { "nuvio-\(profile.uuidString).json" }

    /// Missing or unreadable file: empty state (the next pass starts over; nothing secret is lost).
    public func load(_ profile: UUID) -> NuvioState {
        guard let d = storage.read(Self.name(profile)) else { return NuvioState() }
        return (try? JSONDecoder().decode(NuvioState.self, from: d)) ?? NuvioState()
    }

    /// Default date coding keeps sub-seconds, so an outbox entry compares equal after a reload.
    public func save(_ s: NuvioState, profile: UUID) throws {
        try storage.write(Self.name(profile), try JSONEncoder().encode(s))
    }

    public func remove(_ profile: UUID) { storage.remove(Self.name(profile)) }
}
