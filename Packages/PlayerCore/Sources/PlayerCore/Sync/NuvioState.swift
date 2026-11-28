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

    /// The row belongs to a series (an episode).
    public var isSeries: Bool {
        if let r = row { return NuvioSync.isSeries(type: r.contentType, season: r.season, episode: r.episode) }
        if let w = watched { return NuvioSync.isSeries(type: w.contentType, season: w.season, episode: w.episode) }
        return false
    }
}

/// How the account names a title the app keeps under another local id (review 2, finding 1): TMDB numbers films and
/// series separately, so the kind is part of the link.
public struct NuvioIDLink: Codable, Hashable, Sendable {
    /// Local item id (`tt…`).
    public var local: String
    /// `content_id` as the account has it (`tmdb:N`).
    public var remote: String
    public var series: Bool

    public init(local: String, remote: String, series: Bool) {
        self.local = local; self.remote = remote; self.series = series
    }
}

/// A `tmdb:N` title merged under its provisional local id `tmdb:N` that waits for its IMDb id (review 2, finding 2).
public struct NuvioPendingID: Codable, Hashable, Sendable {
    public var number: Int
    public var series: Bool
    /// Newest `last_watched` (epoch ms) seen for the title: newest titles are resolved first.
    public var lastWatched: Int
    /// Lookups that answered "no IMDb id"; at `NuvioState.maxIDAttempts` the title keeps `tmdb:N`.
    public var attempts: Int

    public init(number: Int, series: Bool, lastWatched: Int, attempts: Int = 0) {
        self.number = number; self.series = series; self.lastWatched = lastWatched; self.attempts = attempts
    }

    public var provisionalID: String { "tmdb:\(number)" }
}

/// Where a bootstrap that needs more than one pass goes on (review 2, finding 6): the cursors captured before its
/// first snapshot and the next history page.
public struct NuvioBootstrapResume: Codable, Equatable, Sendable {
    public var progressCursor: Int
    public var watchedCursor: Int
    public var nextWatchedPage: Int

    public init(progressCursor: Int, watchedCursor: Int, nextWatchedPage: Int) {
        self.progressCursor = progressCursor; self.watchedCursor = watchedCursor; self.nextWatchedPage = nextWatchedPage
    }
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

/// `description`, `debugDescription` and the mirror show counts and the profile index only: no account user id,
/// no profile id, no content ids (review 2, finding 17).
public struct NuvioState: Codable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    /// Staged rows kept; beyond it the oldest go and are counted in `skipped` (never silently, finding 6). One lookup
    /// names every row of a title, so this is rows, not titles.
    public static let maxStaged = 3000
    /// "No IMDb id" answers before a `tmdb:N` title stops being looked up.
    public static let maxIDAttempts = 3
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
    /// Local item id ↔ `content_id` as the account has it (per kind), so a push uses the same key as the pulled row.
    public var remoteIDs: [NuvioIDLink] = []
    /// `tmdb:N` titles waiting for their IMDb id.
    public var pendingIDs: [NuvioPendingID] = []
    /// A bootstrap that goes on in the next pass (history beyond one pass, finding 6).
    public var bootstrapResume: NuvioBootstrapResume?
    /// Bumped by every reset and profile change; `NuvioSyncChanges.apply` replays nothing onto another generation
    /// (finding 10).
    public var generation = 0
    public var outbox = NuvioOutbox()
    public var staged: [NuvioStaged] = []
    /// Pulled rows the app could not address (other id schemes, whole-series rows), shown as a number.
    public var skipped = 0
    public var tombstones: [NuvioTombstone] = []

    public init() {}

    enum CodingKeys: String, CodingKey {
        case userID, profileIndex, profileID, progressCursor, watchedCursor, bootstrapDone, lastPullAt, remoteIDs
        case pendingIDs, bootstrapResume, generation, outbox, staged, skipped, tombstones
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
        remoteIDs = (field(.remoteIDs, [Lossy<NuvioIDLink>].self) ?? []).compactMap(\.value)
        pendingIDs = (field(.pendingIDs, [Lossy<NuvioPendingID>].self) ?? []).compactMap(\.value)
        bootstrapResume = field(.bootstrapResume, NuvioBootstrapResume.self)
        generation = field(.generation, Int.self) ?? 0
        outbox = field(.outbox, NuvioOutbox.self) ?? NuvioOutbox()
        staged = (field(.staged, [Lossy<NuvioStaged>].self) ?? []).compactMap(\.value)
        skipped = field(.skipped, Int.self) ?? 0
        tombstones = (field(.tombstones, [Lossy<NuvioTombstone>].self) ?? []).compactMap(\.value)
    }

    // MARK: Resets

    /// Another account signed in: nothing of the old account stays (profile choice, cursors, ids, outbox, staged
    /// rows, counter). Tombstones stay: they are local decisions of this profile, not account data.
    public mutating func resetForAccount(_ userID: String) {
        let keep = (tombstones, generation + 1)
        self = NuvioState()
        self.userID = userID
        (tombstones, generation) = keep
    }

    /// The book was replaced (restore): pull from scratch, keep the profile choice and the outbox.
    public mutating func resetCursors() {
        progressCursor = nil
        watchedCursor = nil
        bootstrapDone = false
        lastPullAt = nil
        bootstrapResume = nil
        generation += 1
    }

    /// The user picked an account profile. The same profile (index and id) changes nothing; another one starts
    /// over, so nothing meant for the old profile is pushed into the new one.
    public mutating func choose(_ profile: NuvioProfile) {
        let id = profile.id.isEmpty ? nil : profile.id
        if profileIndex == profile.profileIndex, profileID == id { return }
        let keep = (userID, tombstones, generation + 1)
        self = NuvioState()
        (userID, tombstones, generation) = keep
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
    /// (`lastWatched`) go; they are added to `skipped` and their number is returned (finding 6).
    @discardableResult
    public mutating func stage(_ s: NuvioStaged) -> Int {
        if let i = staged.firstIndex(where: { $0.id == s.id }) {
            if staged[i].lastWatched > s.lastWatched { return 0 }
            staged.remove(at: i)
        }
        staged.append(s)
        guard staged.count > Self.maxStaged else { return 0 }
        staged.sort { $0.lastWatched != $1.lastWatched ? $0.lastWatched > $1.lastWatched : $0.id < $1.id }
        let n = staged.count - Self.maxStaged
        staged.removeLast(n)
        skipped += n
        return n
    }

    /// The row was merged (or given up).
    public mutating func unstage(_ s: NuvioStaged) { staged.removeAll { $0.id == s.id } }

    // MARK: Ids (findings 1, 2)

    /// `content_id` of a local item id for a push (the local id itself when no link is known).
    public func remoteID(local: String, series: Bool) -> String {
        remoteIDs.first { $0.local == local && $0.series == series }?.remote ?? local
    }

    /// Local item id of a `content_id` of this kind, when a link is known. Several: the smallest (deterministic).
    public func localID(remote: String, series: Bool) -> String? {
        remoteIDs.filter { $0.remote == remote && $0.series == series }.map(\.local).min()
    }

    /// Adds or replaces the link of `(remote, series)`.
    public mutating func link(_ l: NuvioIDLink) {
        remoteIDs.removeAll { ($0.remote == l.remote && $0.series == l.series) || ($0.local == l.local && $0.series == l.series) }
        remoteIDs.append(l)
    }

    /// Notes a provisional `tmdb:N` title (newest `lastWatched` kept, attempts kept).
    public mutating func notePending(_ p: NuvioPendingID) {
        if let i = pendingIDs.firstIndex(where: { $0.number == p.number && $0.series == p.series }) {
            pendingIDs[i].lastWatched = max(pendingIDs[i].lastWatched, p.lastWatched)
        } else {
            pendingIDs.append(NuvioPendingID(number: p.number, series: p.series, lastWatched: p.lastWatched))
        }
    }

    // MARK: Tombstones (A4)

    /// Records a local removal; it replaces an older tombstone of the title. Pending pushes of the title go too
    /// (they would put back what the user just removed). Beyond `maxTombstones` the oldest go.
    public mutating func tombstone(itemID: String, kind: NuvioTombstone.Kind, at: Date) {
        tombstones.removeAll { $0.itemID == itemID }
        tombstones.append(NuvioTombstone(itemID: itemID, kind: kind, at: at))
        outbox.remove(contentIDs: Set([itemID] + remoteIDs.filter { $0.local == itemID }.map(\.remote)))
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
            // Both ids of a title (finding 2): a row under `tmdb:N` meets a tombstone under its linked `tt…`.
            let series = e.season != nil || ContentKind.isEpisodic(type: e.item.type)
            let other = localID(remote: e.item.id, series: series)
            guard let t = byItem[e.item.id] ?? byItem[e.id] ?? other.flatMap({ byItem[$0] }) else { return true }
            if e.updated > t.at { cleared.insert(t.itemID); return true }
            return t.kind == .removedFromContinue && Self.isFinished(e)
        }
        if !cleared.isEmpty { tombstones.removeAll { cleared.contains($0.itemID) } }
        return out
    }

    /// True when the tombstone of `itemID` blocks a local entry with this time and state (used when entries move to
    /// another id, finding 2).
    func blocks(itemID: String, updated: Date, finished: Bool) -> Bool {
        guard let t = tombstones.filter({ $0.itemID == itemID }).max(by: { $0.at < $1.at }) else { return false }
        if updated > t.at { return false }
        return !(t.kind == .removedFromContinue && finished)
    }

    /// Drops tombstones older than `tombstoneMaxAge` and prunes the outbox.
    public mutating func prune(now: Date) {
        tombstones.removeAll { now.timeIntervalSince($0.at) > Self.tombstoneMaxAge }
        outbox.prune(now: now)
    }

    static func isFinished(_ e: NuvioProgressEntry) -> Bool {
        e.watched || ProgressBook.nuvioFinished(position: e.position, duration: e.duration)
    }
}

extension NuvioState {
    public var description: String {
        "NuvioState(profileIndex: \(profileIndex.map(String.init) ?? "nil"), bootstrapDone: \(bootstrapDone), "
            + "outbox: \(outbox.entries.count), staged: \(staged.count), skipped: \(skipped), "
            + "tombstones: \(tombstones.count), pendingIDs: \(pendingIDs.count))"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["profileIndex": profileIndex as Any, "bootstrapDone": bootstrapDone,
                                "outbox": outbox.entries.count, "staged": staged.count, "skipped": skipped,
                                "tombstones": tombstones.count], displayStyle: .struct)
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
