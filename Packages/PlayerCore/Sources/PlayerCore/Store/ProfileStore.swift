import Foundation

public struct StoredProfiles: Codable, Sendable, Equatable {
    public static let currentSchema = 1
    public var schemaVersion: Int
    public var profiles: [Profile]
    public var activeProfileID: UUID?

    public init(schemaVersion: Int = StoredProfiles.currentSchema, profiles: [Profile], activeProfileID: UUID? = nil) {
        self.schemaVersion = schemaVersion; self.profiles = profiles; self.activeProfileID = activeProfileID
    }

    public static func makeDefault() -> StoredProfiles {
        let p = Profile.makeDefault()
        return StoredProfiles(profiles: [p], activeProfileID: p.id)
    }

    public var active: Profile? { profiles.first { $0.id == activeProfileID } ?? profiles.first }

    enum CodingKeys: String, CodingKey { case schemaVersion, profiles, activeProfileID }

    /// Task 1.2: profiles are decoded one by one; an unreadable profile (e.g. without `id`) is skipped and named in the
    /// `DecodeReport` (`profiles[1]`). Encoding stays synthesized, the format is unchanged.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let r = DecodeReportBox.of(decoder)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        profiles = try c.decode([FailableDecodable<Profile>].self, forKey: .profiles).compactMap(\.value)
        activeProfileID = c.decodeLenient(UUID?.self, forKey: .activeProfileID, default: nil, report: r)
    }
}

public enum StoreError: Error, Equatable { case newerSchema(Int), empty, candidateMissing }

/// Task 1.3: result of loading the profiles at start.
public enum ProfileLoad: Sendable {
    /// Read (lenient); a non-empty report means something was ignored and the original bytes are in `.bak`.
    case loaded(StoredProfiles, DecodeReport)
    /// Nothing stored yet: a new default profile.
    case fresh(StoredProfiles)
    /// Stored profiles exist but cannot be read. Nothing may be saved until the user picks a way out.
    case unreadable(reason: String, candidates: [RecoveryCandidate])

    /// Task 2.2, final review I1: whether the Keychain should fill gaps instead of following the profiles. True when
    /// the file was missing (`.fresh`) or read leniently (a non-empty report: one bad value can empty `apiKeys` or
    /// drop a login, and the Keychain copy is then the only good one). A Build 1 rollback never produces a report.
    public var needsSecretRecovery: Bool {
        switch self {
        case .fresh: return true
        case .loaded(_, let report): return !report.isEmpty
        case .unreadable: return false
        }
    }
}

/// Task 1.3: a readable older version the user can load instead (`ProfileStore.restore`).
public struct RecoveryCandidate: Sendable, Identifiable, Hashable {
    /// "<blob name>#<copy index>", e.g. "profiles.json.1#0".
    public let id: String
    public let label: String
    public let profiles: Int
    public let savedAt: Date?
    public init(id: String, label: String, profiles: Int, savedAt: Date?) {
        self.id = id; self.label = label; self.profiles = profiles; self.savedAt = savedAt
    }
}

/// Alle Profile in einer JSON-Datei, atomar geschrieben.
///
/// Task 1.3: loading never leads to overwriting.
/// - An unreadable `profiles.json` stays untouched; a copy goes to its own slot `profiles.json.unreadable.bak`
///   (file only), and `loadResult()` returns `.unreadable` with the readable older versions as candidates.
/// - `profiles.json.bak` holds only readable originals: read with a non-empty `DecodeReport`, the original bytes go
///   there (unless that `.bak` holds an unreadable legacy state, or already covers every ignored path).
/// - `save` first moves the last good version to `profiles.json.1` and `.1` to `.2`, at most once per
///   `rotationInterval`. While an unreadable state set aside is newer than `.1` and younger than `freezeInterval`,
///   the generations are frozen (no rotation), so a good generation is not pushed out right after the failure.
/// - The dates of `.1`, `.2`, `.bak` and the unreadable slot lie in `profiles.json.dates` (UserDefaults entries
///   have no date).
public final class ProfileStore: @unchecked Sendable {
    public let storage: BlobStorage
    static let name = "profiles.json"
    static let generation1 = name + ".1"
    static let generation2 = name + ".2"
    static let backupName = name + ".bak"
    /// Fix round 1: own slot for unreadable states; ends in `.bak`, so TieredBlobStorage keeps it file only.
    static let unreadableName = name + ".unreadable.bak"
    static let datesName = name + ".dates"
    /// Task 1.3: at most one rotation of the generations in this time.
    public static let rotationInterval: TimeInterval = 10 * 60
    /// Fix round 1: an unreadable set-aside freezes the generations at most this long.
    public static let freezeInterval: TimeInterval = 7 * 24 * 3600

    public init(storage: BlobStorage) { self.storage = storage }
    /// Nur für Datei-Ablage (Tests).
    var fileURL: URL { (storage as! FileBlobStorage).url(Self.name) }
    var backupURL: URL { (storage as! FileBlobStorage).url(Self.backupName) }
    var unreadableURL: URL { (storage as! FileBlobStorage).url(Self.unreadableName) }
    public convenience init(directory: URL) { self.init(storage: FileBlobStorage(directory: directory)) }

    /// Task 1.2 interface, kept for callers that only want profiles: an unreadable state gives the default profile
    /// (nothing is overwritten by this call; the App uses `loadResult()`).
    public func load() -> (profiles: StoredProfiles, report: DecodeReport) {
        switch loadResult() {
        case .loaded(let s, let r): return (s, r)
        case .fresh(let s): return (s, DecodeReport())
        case .unreadable: return (.makeDefault(), DecodeReport())
        }
    }

    public func loadResult(now: Date = Date()) -> ProfileLoad {
        guard let data = storage.read(Self.name) else {
            let c = candidates()
            return c.isEmpty ? .fresh(.makeDefault())
                : .unreadable(reason: "Die Profile fehlen, es gibt aber ältere Fassungen.", candidates: c)
        }
        do {
            let (s, report) = try Self.decodeReporting(data)
            if !report.isEmpty { setAsideIgnored(data, report: report, now: now) }
            return .loaded(s, report)
        } catch {
            setAsideUnreadable(data, now: now)
            return .unreadable(reason: Self.reason(error), candidates: candidates())
        }
    }

    /// Loads a candidate from `loadResult()` into `profiles.json` (without rotating). An unreadable state there is
    /// kept in `profiles.json.unreadable.bak` first; if that fails, nothing is changed and the error is thrown.
    public func restore(_ id: String, now: Date = Date()) throws -> StoredProfiles {
        guard let hash = id.lastIndex(of: "#"), let index = Int(id[id.index(after: hash)...]) else { throw StoreError.candidateMissing }
        let list = copies(String(id[..<hash]))
        guard list.indices.contains(index), let s = try? Self.decode(list[index].data) else { throw StoreError.candidateMissing }
        try keepUnreadableAside(now: now)
        try storage.write(Self.name, list[index].data)
        return s
    }

    /// Deliberately starts again with the default profile (without rotating); the unreadable state stays in
    /// `profiles.json.unreadable.bak`.
    public func startFresh(now: Date = Date()) throws -> StoredProfiles {
        try keepUnreadableAside(now: now)
        let s = StoredProfiles.makeDefault()
        try storage.write(Self.name, try JSONEncoder().encode(s))
        return s
    }

    /// Before `profiles.json` is replaced on purpose (restore, start again, import): an unreadable state there goes to
    /// `profiles.json.unreadable.bak` (`.bak` with readable originals stays). Throws if it cannot be written.
    public func keepUnreadableAside(now: Date = Date()) throws {
        guard let cur = storage.read(Self.name), !Self.isReadable(cur), storage.read(Self.unreadableName) != cur else { return }
        try storage.write(Self.unreadableName, cur)
        var d = dates(); d["unreadable"] = now; writeDates(d)
    }

    public func save(_ s: StoredProfiles, now: Date = Date()) throws {
        let data = try JSONEncoder().encode(s)
        rotateIfDue(replacing: s, now: now)
        try storage.write(Self.name, data)
    }

    /// Full export (with all keys); the format of build 249.
    public func exportData(_ s: StoredProfiles) throws -> Data { try exportData(s, includeSecrets: true) }

    /// Task 1.4: `includeSecrets: false` leaves out `apiKeys`, `syncTokens` and the access part of addon addresses
    /// (`StoredProfiles.withoutSecrets`); same encoder, same keys.
    public func exportData(_ s: StoredProfiles, includeSecrets: Bool) throws -> Data {
        let s = includeSecrets ? s : s.withoutSecrets()
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(s)
    }

    public func importData(_ data: Data) throws -> StoredProfiles { try Self.decode(data) }
    /// Final review: the import with its report (values a newer build wrote that this one ignores), for the log line.
    public func importDataReporting(_ data: Data) throws -> (profiles: StoredProfiles, report: DecodeReport) {
        try Self.decodeReporting(data)
    }

    static func decode(_ data: Data) throws -> StoredProfiles { try decodeReporting(data).profiles }

    static func decodeReporting(_ data: Data) throws -> (profiles: StoredProfiles, report: DecodeReport) {
        let (s, report) = try JSONDecoder().decodeReporting(StoredProfiles.self, from: data)
        try validate(s)
        return (s, report)
    }

    /// Checks of every profile load and import (also `Backup.decodeReporting`).
    static func validate(_ s: StoredProfiles) throws {
        if s.schemaVersion > StoredProfiles.currentSchema { throw StoreError.newerSchema(s.schemaVersion) }
        if s.profiles.isEmpty { throw StoreError.empty }
    }

    static func isReadable(_ data: Data) -> Bool { (try? decode(data)) != nil }

    static func reason(_ error: Error) -> String {
        switch error {
        case StoreError.newerSchema(let v): "Die Profile stammen aus einer neueren Version der App (Schema \(v))."
        case StoreError.empty: "Die Profildatei enthält keine Profile."
        case is DecodingError: "Die Profildatei ist beschädigt oder unvollständig."
        default: "Die Profildatei ist nicht lesbar."
        }
    }

    // MARK: Task 1.3 internals

    /// Last good version → `.1`, `.1` → `.2`. Skipped when the stored version is not readable or equals the new one
    /// (compared decoded: dictionary order makes the bytes of equal values differ),
    /// within `rotationInterval` after the last rotation or when the clock went back before it, and while an
    /// unreadable set-aside is newer than `.1` and younger than `freezeInterval`.
    /// Failures here never block the save itself.
    func rotateIfDue(replacing new: StoredProfiles, now: Date) {
        guard let cur = storage.read(Self.name) else { return }
        var d = dates()
        let old1 = storage.read(Self.generation1)
        if old1 != nil, let d1 = d["1"] {
            if now.timeIntervalSince(d1) < Self.rotationInterval { return }   // also when the clock went back
            if let u = d["unreadable"], u > d1, now.timeIntervalSince(u) < Self.freezeInterval { return }
        }
        // Decoded only when a rotation is due (at most once per interval).
        guard let old = try? Self.decode(cur), old != new else { return }
        if let old1, old1 != cur {
            if (try? storage.write(Self.generation2, old1)) != nil { d["2"] = d["1"] }
        }
        if (try? storage.write(Self.generation1, cur)) != nil { d["1"] = now }
        writeDates(d)
    }

    /// Unreadable state → `profiles.json.unreadable.bak` (`profiles.json` itself stays untouched anyway). The date
    /// stays when the slot already holds this state (a second failed start does not extend the freeze).
    func setAsideUnreadable(_ data: Data, now: Date) {
        if storage.read(Self.unreadableName) == data { return }
        guard (try? storage.write(Self.unreadableName, data)) != nil else { return }
        var d = dates(); d["unreadable"] = now; writeDates(d)
    }

    /// Read with ignored values → original bytes to `.bak`, so the next save cannot destroy the only copy. Not over
    /// an unreadable `.bak`, and not over a `.bak` whose own report already covers every path ignored now (it is the
    /// older original that still holds values the current file has lost).
    func setAsideIgnored(_ data: Data, report: DecodeReport, now: Date) {
        if let b = storage.read(Self.backupName) {
            if b == data { return }
            guard let (_, old) = try? Self.decodeReporting(b) else { return }
            if Set(report.ignored).isSubset(of: Set(old.ignored)) { return }
        }
        guard (try? storage.write(Self.backupName, data)) != nil else { return }
        var d = dates(); d["bak"] = now; writeDates(d)
    }

    /// Readable older versions: `.1`, `.2`, `.bak`, the unreadable slot (only if this build can read it after all),
    /// then other copies of `profiles.json` (e.g. an older file).
    func candidates() -> [RecoveryCandidate] {
        let d = dates()
        let sources: [(name: String, label: String, date: Date?)] = [
            (Self.generation1, "Letzte Fassung", d["1"]), (Self.generation2, "Vorletzte Fassung", d["2"]),
            (Self.backupName, "Beiseitegelegte Fassung", d["bak"]),
            (Self.unreadableName, "Beiseitegelegter Stand", d["unreadable"]), (Self.name, "Dateikopie", nil),
        ]
        var seen: Set<Data> = []
        var out: [RecoveryCandidate] = []
        for src in sources {
            let list = copies(src.name)
            for (i, c) in list.enumerated() where !seen.contains(c.data) {
                guard let s = try? Self.decode(c.data) else { continue }
                seen.insert(c.data)
                let label = list.count > 1 || src.name == Self.name ? "\(src.label) (\(c.source))" : src.label
                out.append(RecoveryCandidate(id: "\(src.name)#\(i)", label: label, profiles: s.profiles.count,
                                             savedAt: c.modified ?? src.date))
            }
        }
        return out
    }

    func copies(_ name: String) -> [BlobCopy] {
        if let c = storage as? BlobCopies { return c.copies(name) }
        return storage.read(name).map { [BlobCopy(source: name, data: $0, modified: nil)] } ?? []
    }

    func dates() -> [String: Date] {
        storage.read(Self.datesName).flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
    }

    func writeDates(_ d: [String: Date]) { try? storage.write(Self.datesName, JSONEncoder().encode(d)) }
}
