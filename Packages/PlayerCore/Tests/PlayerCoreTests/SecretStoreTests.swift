import Foundation
import Testing
@testable import PlayerCore

private func secretProfile() -> Profile {
    var p = Profile.makeDefault(name: "Geheim")
    p.apiKeys = ["tmdb": "k-tmdb", LogSignature.secretKey: "log-secret", "leer": ""]
    p.syncTokens = ["trakt": SyncToken(accessToken: "a1", refreshToken: "r1", expiresAt: Date(timeIntervalSince1970: 1_000))]
    return p
}

@Test func secretCopyIsRepeatable() {
    let store = MemorySecretStore()
    let p = secretProfile()
    // tmdb, playerlog, trakt token; the empty key is not copied.
    #expect(SecretMigration.copyIntoStore(profiles: [p], store: store) == 3)
    #expect(SecretMigration.copyIntoStore(profiles: [p], store: store) == 0)
    #expect(store.get(SecretNames.apiKey("tmdb"), profile: p.id) == "k-tmdb")
    #expect(store.get(SecretNames.apiKey(LogSignature.secretKey), profile: p.id) == "log-secret")
    #expect(store.get(SecretNames.apiKey("leer"), profile: p.id) == nil)
    #expect(SecretMigration.token("trakt", profile: p.id, store: store) == p.syncTokens["trakt"])
}

/// Fix round 1: rollback to Build 1 (edits land in the profile only) and forward again: the profile wins at start.
@Test func secretRollbackAndForwardKeepsProfileValues() {
    let store = MemorySecretStore()
    var p = secretProfile()
    p.apiKeys["torbox"] = "tb-alt"
    p.syncTokens["simkl"] = SyncToken(accessToken: "simkl-alt")
    SecretMigration.copyIntoStore(profiles: [p], store: store)
    // Under "Build 1": key changed, Simkl re-login (no expiry), Trakt disconnected, TorBox key deleted.
    var b1 = p
    b1.apiKeys[LogSignature.secretKey] = "log-neu"
    b1.syncTokens["simkl"] = SyncToken(accessToken: "simkl-neu")
    b1.syncTokens["trakt"] = nil
    b1.apiKeys["torbox"] = nil
    let loaded = b1
    #expect(SecretMigration.copyIntoStore(profiles: [loaded], store: store) == 4)
    #expect(loaded == b1)   // the profile is never rewritten at start
    #expect(store.get(SecretNames.apiKey(LogSignature.secretKey), profile: p.id) == "log-neu")
    #expect(SecretMigration.token("simkl", profile: p.id, store: store)?.accessToken == "simkl-neu")
    #expect(SecretMigration.token("trakt", profile: p.id, store: store) == nil)
    #expect(store.get(SecretNames.apiKey("torbox"), profile: p.id) == nil)
    #expect(SecretMigration.copyIntoStore(profiles: [loaded], store: store) == 0)
}

/// Fix round 1: recovery (older version restored) fills what the profile lacks, never replaces what it has.
@Test func secretRecoveryFillsMissingFromStore() throws {
    let store = MemorySecretStore()
    let p = secretProfile()
    SecretMigration.copyIntoStore(profiles: [p], store: store)
    try store.set("k-kc", name: SecretNames.apiKey("tmdb"), profile: p.id)
    var older = p
    older.apiKeys[LogSignature.secretKey] = nil
    older.syncTokens = [:]
    var list = [older]
    #expect(SecretMigration.fillMissing(&list, store: store) == 2)
    #expect(list[0].apiKeys[LogSignature.secretKey] == "log-secret")
    #expect(list[0].syncTokens["trakt"] == p.syncTokens["trakt"])
    #expect(list[0].apiKeys["tmdb"] == "k-tmdb")   // the profile's own value stays
    #expect(SecretMigration.fillMissing(&list, store: store) == 0)
}

@Test func deletingProfileRemovesItsSecrets() throws {
    let store = MemorySecretStore()
    let a = secretProfile(), b = secretProfile()
    let snap = try SecretMigration.mirror(from: [:], to: [a, b], store: store)
    #expect(store.count(profile: a.id) == 3 && store.count(profile: b.id) == 3)
    _ = try SecretMigration.mirror(from: snap, to: [b], store: store)
    #expect(store.count(profile: a.id) == 0)
    #expect(store.count(profile: b.id) == 3)
    try store.set("x", name: "key.tmdb", profile: b.id)
    try store.removeAll(profile: b.id)
    #expect(store.get("key.tmdb", profile: b.id) == nil)
}

@Test func tokenRotationWritesBothPlaces() throws {
    let store = MemorySecretStore()
    var p = secretProfile()
    let snap = try SecretMigration.mirror(from: [:], to: [p], store: store)
    let rotated = SyncToken(accessToken: "a9", refreshToken: "r9", expiresAt: Date(timeIntervalSince1970: 9_000))
    p.syncTokens["trakt"] = rotated   // the profile side (AppModel.update)
    let snap2 = try SecretMigration.mirror(from: snap, to: [p], store: store)
    #expect(p.syncTokens["trakt"] == rotated)
    #expect(SecretMigration.token("trakt", profile: p.id, store: store) == rotated)
    #expect(snap2 != snap)
    // Profile format unchanged: the token stays in the profile JSON.
    let json = String(decoding: try JSONEncoder().encode(p), as: UTF8.self)
    #expect(json.contains("a9") && json.contains("syncTokens"))
}

@Test func emptySecretValueDeletes() throws {
    let store = MemorySecretStore()
    var p = secretProfile()
    let snap = try SecretMigration.mirror(from: [:], to: [p], store: store)
    p.apiKeys["tmdb"] = ""
    p.syncTokens["trakt"] = nil
    _ = try SecretMigration.mirror(from: snap, to: [p], store: store)
    #expect(store.get(SecretNames.apiKey("tmdb"), profile: p.id) == nil)
    #expect(store.get(SecretNames.token("trakt"), profile: p.id) == nil)
    try store.set("v", name: "n", profile: p.id)
    try store.set("", name: "n", profile: p.id)
    #expect(store.get("n", profile: p.id) == nil)
    try store.set("v", name: "n", profile: p.id)
    try store.set(nil, name: "n", profile: p.id)
    #expect(store.get("n", profile: p.id) == nil)
}

/// Final review I1: one unreadable value empties `apiKeys` on a lenient load. Such a load is recovery: the secrets
/// come back from the store and nothing is deleted there.
@Test func lenientLoadCountsAsSecretRecovery() throws {
    let secrets = MemorySecretStore()
    var s = StoredProfiles.makeDefault()
    s.profiles[0] = secretProfile()
    s.activeProfileID = s.profiles[0].id
    let id = s.profiles[0].id
    SecretMigration.copyIntoStore(profiles: s.profiles, store: secrets)
    // Stored file where one API key has the wrong type: the whole dictionary falls back to [:].
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
    var profiles = try #require(json["profiles"] as? [[String: Any]])
    profiles[0]["apiKeys"] = ["tmdb": 42]
    json["profiles"] = profiles
    let store = ProfileStore(directory: tempDir())
    try JSONSerialization.data(withJSONObject: json).write(to: store.fileURL)
    let load = store.loadResult()
    guard case .loaded(let loaded, let report) = load else { Issue.record("expected .loaded"); return }
    #expect(!report.isEmpty)
    #expect(loaded.profiles[0].apiKeys.isEmpty)
    #expect(load.needsSecretRecovery)
    var list = loaded.profiles
    #expect(SecretMigration.fillMissing(&list, store: secrets) == 2)
    #expect(list[0].apiKeys["tmdb"] == "k-tmdb" && list[0].apiKeys[LogSignature.secretKey] == "log-secret")
    #expect(SecretMigration.copyIntoStore(profiles: list, store: secrets) == 0)   // nothing deleted
    #expect(secrets.get(SecretNames.apiKey("tmdb"), profile: id) == "k-tmdb")
    // A clean load stays normal (the profile is authoritative); a missing file is recovery.
    var clean = s; clean.profiles[0].apiKeys = ["tmdb": "k-tmdb"]
    #expect(!ProfileLoad.loaded(clean, DecodeReport()).needsSecretRecovery)
    #expect(ProfileLoad.fresh(clean).needsSecretRecovery)
    #expect(!ProfileLoad.unreadable(reason: "x", candidates: []).needsSecretRecovery)
}

/// Task 3.9 (Build 2 re-review Minor): only a decode problem in a secret-bearing field is recovery. An unrelated bad
/// value must not bring back a key that was deleted under Build 1.
@Test func onlySecretDecodeIssuesCountAsRecovery() throws {
    let secrets = MemorySecretStore()
    var s = StoredProfiles.makeDefault()
    s.profiles[0] = secretProfile()
    s.activeProfileID = s.profiles[0].id
    SecretMigration.copyIntoStore(profiles: s.profiles, store: secrets)

    func load(_ change: (inout [String: Any]) -> Void) throws -> ProfileLoad {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
        var profiles = try #require(json["profiles"] as? [[String: Any]])
        change(&profiles[0])
        json["profiles"] = profiles
        let store = ProfileStore(directory: tempDir())
        try JSONSerialization.data(withJSONObject: json).write(to: store.fileURL)
        return store.loadResult()
    }
    // Unrelated bad value (unknown accent): report not empty, but no recovery.
    let unrelated = try load { p in
        var a = p["appearance"] as? [String: Any] ?? [:]
        a["accent"] = "neonlila"
        p["appearance"] = a
    }
    guard case .loaded(_, let r1) = unrelated else { Issue.record("expected .loaded"); return }
    #expect(!r1.isEmpty && !r1.touchesSecrets)
    #expect(!unrelated.needsSecretRecovery)
    // Bad apiKeys value → recovery.
    let keys = try load { $0["apiKeys"] = ["tmdb": 42] }
    #expect(keys.needsSecretRecovery)
    // Bad login entry → recovery.
    let token = try load { $0["syncTokens"] = ["trakt": ["accessToken": 7]] }
    guard case .loaded(_, let r3) = token else { Issue.record("expected .loaded"); return }
    #expect(r3.touchesSecrets && token.needsSecretRecovery)
    // Paths: segment match, not substring; a skipped whole profile is no secret field.
    #expect(DecodeReport(ignored: ["profiles[0].apiKeys"]).touchesSecrets)
    #expect(DecodeReport(ignored: ["home.rows[2].style", "profiles[1].syncTokens.trakt"]).touchesSecrets)
    #expect(!DecodeReport(ignored: ["profiles[1]", "profiles[0].home.rows[0].apiKeysHint"]).touchesSecrets)
    // Missing file stays recovery.
    #expect(ProfileStore(directory: tempDir()).loadResult().needsSecretRecovery)
}

/// Nuvio T2: the device-wide Nuvio session lives under its own scope; the profile secret migration never touches it,
/// also not when a profile is deleted.
@Test func secretMigrationLeavesNuvioSessionAlone() throws {
    let store = MemorySecretStore()
    let sessions = NuvioSessionStore(store: store)
    let session = nuvioTestSession()
    try sessions.save(session)
    let p = secretProfile()
    let other = Profile.makeDefault(name: "Zweites")
    SecretMigration.copyIntoStore(profiles: [p, other], store: store)
    #expect(sessions.load() == session)
    var list = [p, other]
    SecretMigration.fillMissing(&list, store: store)
    #expect(sessions.load() == session)
    #expect(!list.contains { $0.apiKeys.values.contains { $0.contains("AT1") } || !$0.syncTokens.keys.filter { $0.contains("nuvio") }.isEmpty })
    let old = SecretMigration.snapshot([p, other])
    var changed = p
    changed.apiKeys["tmdb"] = "k-neu"
    _ = try SecretMigration.mirror(from: old, to: [changed], store: store)   // `other` deleted
    #expect(sessions.load() == session)
    #expect(store.count(profile: other.id) == 0)
    _ = try SecretMigration.mirror(from: SecretMigration.snapshot([changed]), to: [], store: store)
    #expect(sessions.load() == session)
}
