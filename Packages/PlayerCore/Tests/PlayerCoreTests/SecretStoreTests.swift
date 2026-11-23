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
