import Foundation

/// Task 2.4 (A-B-1): a complete backup – profiles plus progress, kit settings, collection links and device settings.
///
/// Format: the keys of `StoredProfiles` (`schemaVersion`, `profiles`, `activeProfileID`) stay at the top level, the
/// new parts are additional keys. So build 249/250 and Build 1, which decode the file as `StoredProfiles` and ignore
/// unknown keys, still restore the profiles of a version 2 backup. Version 1 is a plain `StoredProfiles`.
/// Dictionaries are keyed by `uuidString` (JSON object keys); kit settings and links are the stored bytes (base64).
public struct Backup: Codable, Sendable, Equatable {
    public static let currentVersion = 2
    public var backupVersion: Int
    public var profiles: StoredProfiles
    public var progress: [UUID: ProgressBook]
    /// `FusionKitSettings` JSON as stored per profile.
    public var fusionKits: [UUID: Data]
    /// Collection link list as stored per profile.
    public var collectionLinks: [UUID: Data]
    public var device: DeviceSettings?

    public init(backupVersion: Int = Backup.currentVersion, profiles: StoredProfiles, progress: [UUID: ProgressBook] = [:],
                fusionKits: [UUID: Data] = [:], collectionLinks: [UUID: Data] = [:], device: DeviceSettings? = nil) {
        self.backupVersion = backupVersion; self.profiles = profiles; self.progress = progress
        self.fusionKits = fusionKits; self.collectionLinks = collectionLinks; self.device = device
    }

    enum CodingKeys: String, CodingKey { case backupVersion, progress, fusionKits, collectionLinks, device }

    public func encode(to encoder: Encoder) throws {
        try profiles.encode(to: encoder)   // same top-level object (StoredProfiles keys)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(backupVersion, forKey: .backupVersion)
        try c.encode(Self.stringKeyed(progress), forKey: .progress)
        try c.encode(Self.stringKeyed(fusionKits.mapValues { $0.base64EncodedString() }), forKey: .fusionKits)
        try c.encode(Self.stringKeyed(collectionLinks.mapValues { $0.base64EncodedString() }), forKey: .collectionLinks)
        try c.encodeIfPresent(device, forKey: .device)
    }

    /// Lenient: a bad entry in one of the new parts is skipped (named in the report), never the whole backup.
    public init(from decoder: Decoder) throws {
        profiles = try StoredProfiles(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let r = DecodeReportBox.of(decoder)
        backupVersion = (try? c.decodeIfPresent(Int.self, forKey: .backupVersion)) ?? 1
        progress = Self.uuidKeyed(c, .progress, ProgressBook.self, report: r)
        fusionKits = Self.base64(Self.uuidKeyed(c, .fusionKits, String.self, report: r), c, .fusionKits, report: r)
        collectionLinks = Self.base64(Self.uuidKeyed(c, .collectionLinks, String.self, report: r), c, .collectionLinks, report: r)
        device = c.decodeLenient(DeviceSettings?.self, forKey: .device, default: nil, report: r)
    }

    /// Reads a version 2 backup or an old `StoredProfiles` (version 1: the other parts stay empty). Same checks as
    /// the profile import (newer schema, no profiles → throws).
    public static func decode(_ data: Data) throws -> Backup { try decodeReporting(data).backup }

    public static func decodeReporting(_ data: Data) throws -> (backup: Backup, report: DecodeReport) {
        let (b, report) = try JSONDecoder().decodeReporting(Backup.self, from: data)
        try ProfileStore.validate(b.profiles)
        return (b, report)
    }

    /// Pretty, sorted keys (like `ProfileStore.exportData`).
    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }

    /// Only the parts of profiles that are still in the backup.
    public var profileIDs: Set<UUID> { Set(profiles.profiles.map(\.id)) }

    static func stringKeyed<V>(_ d: [UUID: V]) -> [String: V] {
        Dictionary(d.map { ($0.key.uuidString, $0.value) }, uniquingKeysWith: { a, _ in a })
    }

    /// Stored bytes travel as base64 strings; a value that is no base64 is skipped and noted.
    static func base64(_ d: [UUID: String], _ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys,
                       report: DecodeReportBox) -> [UUID: Data] {
        var out: [UUID: Data] = [:]
        for (id, s) in d {
            if let data = Data(base64Encoded: s) { out[id] = data } else { report.note(c.codingPath + [key, EntryKey(id.uuidString)]) }
        }
        return out
    }

    static func uuidKeyed<V: Decodable>(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys, _: V.Type,
                                        report: DecodeReportBox) -> [UUID: V] {
        guard let raw = try? c.decodeIfPresent([String: FailableDecodable<V>].self, forKey: key) else {
            if c.contains(key) { report.note(c.codingPath + [key]) }
            return [:]
        }
        var out: [UUID: V] = [:]
        for (k, v) in raw {
            guard let value = v.value else { continue }   // FailableDecodable already noted the path
            guard let id = UUID(uuidString: k) else { report.note(c.codingPath + [key, EntryKey(k)]); continue }
            out[id] = value
        }
        return out
    }
}

private struct EntryKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension StoredProfiles {
    /// Task 2.4 (S-9): sync logins whose `expiresAt` lies in the past are removed (after restoring an old backup).
    /// Tokens without an expiry date stay. Final review I2 (ruling, deviates from the plan text): an expired login
    /// with a refresh token stays too, because `AppModel.token(_:)` renews it on first use.
    public func droppingExpiredTokens(now: Date = Date()) -> (profiles: StoredProfiles, dropped: Int) {
        var s = self
        var dropped = 0
        for i in s.profiles.indices {
            for (k, t) in s.profiles[i].syncTokens {
                if t.refreshToken == nil, let e = t.expiresAt, e <= now { s.profiles[i].syncTokens[k] = nil; dropped += 1 }
            }
        }
        return (s, dropped)
    }
}

extension StoredProfiles {
    /// Task 3.9: whether any profile holds a non-empty API key or a login. The plain export (`withoutSecrets`) never
    /// does; a sealed backup normally does.
    public var carriesSecrets: Bool {
        profiles.contains { p in !p.syncTokens.isEmpty || p.apiKeys.values.contains { !$0.isEmpty } }
    }

    /// Task 3.9 (Build 2 final review I4, user decision 24.11.): a restore without keys on the same TV keeps the keys,
    /// logins and the remote-log secret of every profile whose ID already exists here (`current`); gaps of the current
    /// profile are filled from `store` (Keychain copy) for those IDs only. A profile with a new ID gets none. A backup
    /// that carries secrets is returned unchanged: its own values win. Never replaces a value the backup has.
    /// Returns the number of profiles that kept at least one value.
    public func keepingSecrets(from current: [Profile], store: SecretStore? = nil) -> (profiles: StoredProfiles, kept: Int) {
        guard !carriesSecrets else { return (self, 0) }
        let here = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var s = self
        var kept = 0
        for i in s.profiles.indices {
            guard let old = here[s.profiles[i].id] else { continue }
            var p = s.profiles[i]
            var n = 0
            for (k, v) in old.apiKeys where !v.isEmpty && (p.apiKeys[k] ?? "").isEmpty { p.apiKeys[k] = v; n += 1 }
            for (k, t) in old.syncTokens where p.syncTokens[k] == nil { p.syncTokens[k] = t; n += 1 }
            if let store {
                var one = [p]
                n += SecretMigration.fillMissing(&one, store: store)
                p = one[0]
            }
            // Phase 0a: the plain export cut the access part out of addon addresses. On the TV that still holds the
            // configured address, it comes back (every local configuration of that addon, in the local order).
            var addons: [InstalledAddon] = []
            var seen = Set<String>()
            for a in p.addons {
                let mine = old.addons.filter { AddonAccess.publicManifestURL($0.manifestURL) == a.manifestURL }
                for x in mine.isEmpty ? [a] : mine where seen.insert(x.manifestURL).inserted { addons.append(x) }
            }
            if addons.map(\.manifestURL) != p.addons.map(\.manifestURL) { p.addons = addons; n += 1 }
            if n > 0 { s.profiles[i] = p; kept += 1 }
        }
        return (s, kept)
    }
}

/// Task 2.4 (S-12): the stored blocks of one profile, named `<kind>-<profile uuid>.json` or
/// `<kind>-<profile uuid>-<id>.json` (plus `.bak` copies).
public enum ProfileBlocks {
    public static func belongs(_ name: String, to profile: UUID) -> Bool {
        var n = name
        if n.hasSuffix(".bak") { n.removeLast(4) }
        guard n.hasSuffix(".json") else { return false }
        n.removeLast(5)
        let id = profile.uuidString
        return n.hasSuffix("-" + id) || n.contains("-" + id + "-")
    }

    /// Removes every block of the profile the storage can list; returns the removed names.
    @discardableResult
    public static func remove(profile: UUID, from storage: BlobStorage) -> [String] {
        guard let l = storage as? BlobNames else { return [] }
        let names = l.blobNames().filter { belongs($0, to: profile) }
        for n in names { storage.remove(n) }
        return names
    }
}

/// A storage that can list its block names (for deleting a profile's blocks).
public protocol BlobNames {
    func blobNames() -> [String]
}

extension FileBlobStorage: BlobNames {
    public func blobNames() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }
}

extension TieredBlobStorage: BlobNames {
    public func blobNames() -> [String] {
        let keys = defaults.keys(withPrefix: Self.prefix).map { String($0.dropFirst(Self.prefix.count)) }
        return Array(Set(keys + directories.flatMap { $0.blobNames() })).sorted()
    }
}

// MARK: Fix round 1: plain export without secrets

extension AddonAccess {
    /// A user or addon URL that may go into the plain export unchanged: the Task 1.4 rule
    /// (`publicManifestURL`) leaves it as it is. Anything with user info, query, fragment or a configuration-like path
    /// segment is not safe.
    public static func isPublic(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && publicManifestURL(t) == t
    }
}

extension Backup {
    /// Fix round 1: the parts of the plain export (`GET /export`) without secrets. Profiles go through
    /// `StoredProfiles.withoutSecrets` (Task 1.4); progress images whose address is not public are left out (the meta
    /// comes back from the addon), addon addresses of the last sources are scrubbed like the addon list (an entry
    /// without a readable host is left out); custom kit sources and collection links whose address is not public are
    /// left out (a kit source with its rows). The remote log receiver is not exported. The sealed backup keeps all.
    public func withoutSecrets() -> Backup {
        var b = self
        b.profiles = profiles.withoutSecrets()
        b.progress = progress.mapValues(Self.scrubbed)
        b.fusionKits = fusionKits.compactMapValues(Self.scrubbedKit)
        b.collectionLinks = collectionLinks.compactMapValues(Self.scrubbedLinks)
        b.device = device.map { DeviceSettings(audioShaping: $0.audioShaping, displayMode: $0.displayMode) }
        return b
    }

    static func publicOrNil(_ s: String?) -> String? { s.flatMap { AddonAccess.isPublic($0) ? $0 : nil } }

    static func scrubbed(_ book: ProgressBook) -> ProgressBook {
        var b = book
        for (k, var e) in b.entries {
            e.item.poster = publicOrNil(e.item.poster)
            e.item.background = publicOrNil(e.item.background)
            e.item.logo = publicOrNil(e.item.logo)
            b.entries[k] = e
        }
        if let src = b.sources {
            b.sources = src.compactMapValues { s in
                guard s.addon.contains("://") else { return s }
                var s = s
                s.addon = AddonAccess.publicManifestURL(s.addon)
                return s.addon.isEmpty ? nil : s
            }
        }
        return b
    }

    /// Kit settings bytes → same settings without custom sources whose URL is not public; unreadable bytes are left out.
    static func scrubbedKit(_ data: Data) -> Data? {
        guard var k = try? JSONDecoder().decode(FusionKitSettings.self, from: data) else { return nil }
        for s in k.sources where s.custom && !AddonAccess.isPublic(s.url) { k.removeSource(s.id) }
        return try? JSONEncoder().encode(k)
    }

    /// Link list bytes (array of objects with an optional `url`) → entries with a public or no URL (pasted code);
    /// unreadable bytes are left out. Other keys of an entry stay as they are.
    static func scrubbedLinks(_ data: Data) -> Data? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }
        let kept = list.filter { e in
            guard let o = e as? [String: Any] else { return false }
            guard let u = o["url"] else { return true }
            return (u as? String).map(AddonAccess.isPublic) ?? false
        }
        return try? JSONSerialization.data(withJSONObject: kept, options: [.sortedKeys])
    }
}

extension ProfileBlocks {
    /// Fix round 2 (S-9): profiles a restore removes (in the old set, not in the restored one), in the old order.
    public static func removedByRestore(before: [UUID], after: [UUID]) -> [UUID] {
        let kept = Set(after)
        var seen = Set<UUID>()
        return before.filter { !kept.contains($0) && seen.insert($0).inserted }
    }
}

// MARK: Phase 0a: a restore on the same TV keeps what the backup could not carry

extension Backup {
    /// Phase 0a (finding 3): the plain export leaves out or shortens what is not public (pictures of progress
    /// entries, addon addresses of the last sources, custom kit sources, collection links). Restored on the TV that
    /// still holds the full values, those come back from `progress`, `fusionKits` and `collectionLinks` (the local
    /// state, by profile ID). Everything the backup does carry wins. A backup with secrets is returned unchanged.
    public func keepingLocalDetail(progress localBooks: [UUID: ProgressBook], fusionKits localKits: [UUID: Data],
                                   collectionLinks localLinks: [UUID: Data]) -> Backup {
        guard !profiles.carriesSecrets else { return self }
        var b = self
        for (id, book) in progress { if let l = localBooks[id] { b.progress[id] = Self.fillingDetail(book, from: l) } }
        for (id, k) in fusionKits { if let l = localKits[id] { b.fusionKits[id] = Self.fillingKit(k, from: l) } }
        for (id, x) in collectionLinks { if let l = localLinks[id] { b.collectionLinks[id] = Self.fillingLinks(x, from: l) } }
        return b
    }

    static func fillingDetail(_ book: ProgressBook, from local: ProgressBook) -> ProgressBook {
        var b = book
        for (k, var e) in b.entries {
            guard let l = local.entries[k] else { continue }
            if e.item.poster == nil, publicOrNil(l.item.poster) == nil { e.item.poster = l.item.poster }
            if e.item.background == nil, publicOrNil(l.item.background) == nil { e.item.background = l.item.background }
            if e.item.logo == nil, publicOrNil(l.item.logo) == nil { e.item.logo = l.item.logo }
            b.entries[k] = e
        }
        // A last source comes back when the backup holds its scrubbed form, or none because it could not be scrubbed.
        let scrubbedLocal = scrubbed(local).sources ?? [:]
        for (k, l) in local.sources ?? [:] where b.entries.keys.contains(where: { $0 == k || $0.hasPrefix(k + ":") }) || b.sources?[k] != nil {
            let inBackup = b.sources?[k]
            guard inBackup == scrubbedLocal[k], inBackup != l else { continue }
            b.sources = (b.sources ?? [:]).merging([k: l]) { _, new in new }
        }
        return b
    }

    /// Kit settings of the backup plus the local custom sources the export had to leave out (with their chosen and
    /// waiting rows). Unreadable bytes on either side: the backup as it is.
    static func fillingKit(_ data: Data, from local: Data) -> Data {
        let d = JSONDecoder()
        guard var k = try? d.decode(FusionKitSettings.self, from: data),
              let l = try? d.decode(FusionKitSettings.self, from: local) else { return data }
        if let s = scrubbedKit(local), (try? d.decode(FusionKitSettings.self, from: s)) == k { return local }
        var changed = false
        for s in l.sources where s.custom && !AddonAccess.isPublic(s.url) && !k.sources.contains(where: { $0.id == s.id }) {
            k.sources.append(s)
            for r in l.selected where FusionImport.sourceKey(ofID: r) == s.id && !k.selected.contains(r) { k.selected.append(r) }
            k.parked += l.parked.filter { $0.kitID.flatMap(FusionImport.sourceKey(ofID:)) == s.id && !k.parked.contains($0) }
            changed = true
        }
        return changed ? (try? JSONEncoder().encode(k)) ?? data : data
    }

    /// Links of the backup plus the local ones the export had to leave out (address not public), in the local order
    /// behind them. Unreadable bytes on either side: the backup as it is.
    static func fillingLinks(_ data: Data, from local: Data) -> Data {
        func list(_ d: Data) -> [NSDictionary]? { (try? JSONSerialization.jsonObject(with: d) as? [Any])?.compactMap { $0 as? NSDictionary } }
        guard let inBackup = list(data), let mine = list(local) else { return data }
        if let s = scrubbedLinks(local), list(s) == inBackup { return local }
        let extra = mine.filter { e in
            guard let u = e["url"] as? String, !AddonAccess.isPublic(u) else { return false }
            return !inBackup.contains(e)
        }
        guard !extra.isEmpty else { return data }
        return (try? JSONSerialization.data(withJSONObject: inBackup + extra, options: [.sortedKeys])) ?? data
    }
}

extension Profile {
    /// Phase 0a: a profile as a fresh install creates it and nobody touched (no addon, key, login, collection or
    /// own start page row, default name).
    public var isUntouchedDefault: Bool {
        let d = Profile.makeDefault()
        return name == d.name && addons.isEmpty && collections.isEmpty && apiKeys.isEmpty && syncTokens.isEmpty
            && unknownAddons.isEmpty && unknownCollections.isEmpty && unknownApiKeys.isEmpty && unknownSyncTokens.isEmpty
            && home.rows.map(\.content) == d.home.rows.map(\.content)
    }
}

extension StoredProfiles {
    /// Phase 0a (finding 4): a restore replaces the profiles the backup contains and keeps every other profile of
    /// this TV (created after the backup, or unreadable in it) behind them, so no local profile and none of its data
    /// is deleted by a restore. Only an untouched default profile without data (`hasData`) gives way. Unreadable
    /// local profiles (`unknownProfiles`) stay as well; a raw backup entry with the ID of a kept profile is left out.
    public func keepingLocalProfiles(from here: StoredProfiles, hasData: (UUID) -> Bool) -> StoredProfiles {
        var s = self
        let restored = Set(profiles.map(\.id))
        let kept = here.profiles.filter { !restored.contains($0.id) && !($0.isUntouchedDefault && !hasData($0.id)) }
        s.profiles += kept
        let keptIDs = Set(kept.map { $0.id.uuidString.lowercased() })
        s.unknownProfiles.removeAll { raw in
            guard case .object(let o) = raw, case .string(let id)? = o["id"] else { return false }
            return keptIDs.contains(id.lowercased())
        }
        s.unknownProfiles += here.unknownProfiles.filter { !s.unknownProfiles.contains($0) }
        return s
    }
}
