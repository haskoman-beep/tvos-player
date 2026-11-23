import Foundation

/// Task 2.2 (SEC-14, E-15): place for API keys and sync logins outside `profiles.json` (the app uses the Keychain,
/// tests `MemorySecretStore`). Entries are per profile and name; an empty or nil value deletes the entry.
public protocol SecretStore: Sendable {
    func get(_ name: String, profile: UUID) -> String?
    func set(_ value: String?, name: String, profile: UUID) throws
    func removeAll(profile: UUID) throws
}

/// Thread-safe in-memory store for tests and as a stand-in.
public final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: [String: String]] = [:]

    public init() {}

    public func get(_ name: String, profile: UUID) -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[profile]?[name]
    }

    public func set(_ value: String?, name: String, profile: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        if let value, !value.isEmpty { values[profile, default: [:]][name] = value } else { values[profile]?[name] = nil }
    }

    public func removeAll(profile: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        values[profile] = nil
    }

    /// Number of entries of a profile (tests).
    public func count(profile: UUID) -> Int {
        lock.lock(); defer { lock.unlock() }
        return values[profile]?.count ?? 0
    }
}

/// Entry names in the store: `key.<apiKeys name>` and `token.<service>` (the token as JSON).
public enum SecretNames {
    public static func apiKey(_ k: String) -> String { "key." + k }
    public static func token(_ s: String) -> String { "token." + s }
}

/// What the store holds per profile: entry name → value. Used to find changed and removed entries on save.
public typealias SecretSnapshot = [UUID: [String: String]]

/// Task 2.2, stage 1 (double bookkeeping): profiles keep their secrets (format unchanged, Build 1 reads them);
/// the store gets a copy. Read rule: store, else profile. Write rule: both.
public enum SecretMigration {
    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return e }()

    static func encode(_ t: SyncToken) -> String? { (try? encoder.encode(t)).map { String(decoding: $0, as: UTF8.self) } }
    static func decode(_ s: String) -> SyncToken? { try? JSONDecoder().decode(SyncToken.self, from: Data(s.utf8)) }

    /// The secrets of a profile as store entries (empty keys left out).
    public static func entries(of p: Profile) -> [String: String] {
        var e: [String: String] = [:]
        for (k, v) in p.apiKeys where !v.isEmpty { e[SecretNames.apiKey(k)] = v }
        for (s, t) in p.syncTokens { if let j = encode(t) { e[SecretNames.token(s)] = j } }
        return e
    }

    public static func snapshot(_ profiles: [Profile]) -> SecretSnapshot {
        Dictionary(profiles.map { ($0.id, entries(of: $0)) }, uniquingKeysWith: { a, _ in a })
    }

    /// Read rule for a key: store, else profile.
    public static func apiKey(_ k: String, profile p: Profile, store: SecretStore) -> String? {
        store.get(SecretNames.apiKey(k), profile: p.id) ?? p.apiKeys[k]
    }

    /// Read rule for a login: store, else profile. When both hold one, the one that expires later wins (a rollback
    /// to Build 1 rotates the Trakt token in the profile only; the store would hold a used refresh token then).
    public static func token(_ s: String, profile p: Profile, store: SecretStore) -> SyncToken? {
        let kept = store.get(SecretNames.token(s), profile: p.id).flatMap(decode)
        guard let kept else { return p.syncTokens[s] }
        guard let own = p.syncTokens[s] else { return kept }
        let a = kept.expiresAt ?? .distantPast, b = own.expiresAt ?? .distantPast
        return b > a ? own : kept
    }

    /// Runs at every start: copies every profile secret the store lacks or holds older (tokens). Repeatable; returns the
    /// number of entries written. Errors of single entries are skipped (the profile still holds the value).
    @discardableResult
    public static func copyIntoStore(profiles: [Profile], store: SecretStore) -> Int {
        var n = 0
        for p in profiles {
            for (name, value) in entries(of: p) {
                let cur = store.get(name, profile: p.id)
                if cur == value { continue }
                if cur != nil {
                    // Store wins for keys; for a token only when it does not expire earlier than the profile's.
                    guard name.hasPrefix("token.") else { continue }
                    let s = String(name.dropFirst("token.".count))
                    if token(s, profile: p, store: store) != p.syncTokens[s] { continue }
                }
                if (try? store.set(value, name: name, profile: p.id)) != nil { n += 1 }
            }
        }
        return n
    }

    /// Key names looked up in the store even when the profile lacks them (a restored older profile version).
    public static let knownKeys = ["tmdb", "mdblist", "trakt_id", "trakt_secret", "simkl_id", "torbox",
                                   LogSignature.secretKey, AtvloadlyAddress.key]
    public static let knownTokens = ["trakt", "simkl"]

    /// Applies the read rule to the loaded profiles so all readers of `apiKeys` / `syncTokens` see it; returns the
    /// number of values taken from the store.
    @discardableResult
    public static func overlay(_ profiles: inout [Profile], store: SecretStore) -> Int {
        var n = 0
        for i in profiles.indices {
            let p = profiles[i]
            for k in Set(p.apiKeys.keys).union(knownKeys) {
                if let v = store.get(SecretNames.apiKey(k), profile: p.id), v != p.apiKeys[k] { profiles[i].apiKeys[k] = v; n += 1 }
            }
            for s in Set(p.syncTokens.keys).union(knownTokens) {
                if let t = token(s, profile: p, store: store), t != p.syncTokens[s] { profiles[i].syncTokens[s] = t; n += 1 }
            }
        }
        return n
    }

    /// Write rule after a save: writes changed entries, deletes removed ones and the entries of removed profiles.
    /// Returns the new snapshot; on an error the caller keeps the old one (the next save tries again).
    public static func mirror(from old: SecretSnapshot, to profiles: [Profile], store: SecretStore) throws -> SecretSnapshot {
        let new = snapshot(profiles)
        for (id, entries) in new {
            let before = old[id] ?? [:]
            for (name, value) in entries where before[name] != value {
                try store.set(value, name: name, profile: id)
            }
            for name in before.keys where entries[name] == nil { try store.set(nil, name: name, profile: id) }
        }
        for id in old.keys where new[id] == nil { try store.removeAll(profile: id) }
        return new
    }
}
