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
    #expect(SecretMigration.token("trakt", profile: p, store: store) == p.syncTokens["trakt"])
}

@Test func secretReadFallsBackToProfile() throws {
    let store = MemorySecretStore()
    var p = secretProfile()
    #expect(SecretMigration.apiKey("tmdb", profile: p, store: store) == "k-tmdb")
    #expect(SecretMigration.token("trakt", profile: p, store: store)?.accessToken == "a1")
    // Keychain wins for keys: a restored older profile gets the newer key back.
    try store.set("k-neu", name: SecretNames.apiKey("tmdb"), profile: p.id)
    #expect(SecretMigration.apiKey("tmdb", profile: p, store: store) == "k-neu")
    var list = [p]
    #expect(SecretMigration.overlay(&list, store: store) == 1)
    #expect(list[0].apiKeys["tmdb"] == "k-neu")
    #expect(list[0].apiKeys[LogSignature.secretKey] == "log-secret")
    // Profile recovery: an older profile version without the remote-log secret gets it back from the store.
    try store.set("log-kc", name: SecretNames.apiKey(LogSignature.secretKey), profile: p.id)
    var older = p; older.apiKeys[LogSignature.secretKey] = nil
    var restored = [older]
    SecretMigration.overlay(&restored, store: store)
    #expect(restored[0].apiKeys[LogSignature.secretKey] == "log-kc")
    try store.set(nil, name: SecretNames.apiKey(LogSignature.secretKey), profile: p.id)
    // Tokens: the one that expires later wins (a rollback build may have rotated it in the profile only).
    let newer = SyncToken(accessToken: "a2", refreshToken: "r2", expiresAt: Date(timeIntervalSince1970: 2_000))
    p.syncTokens["trakt"] = newer
    #expect(SecretMigration.token("trakt", profile: p, store: store) == newer)
    #expect(SecretMigration.copyIntoStore(profiles: [p], store: store) == 2)   // playerlog + the newer token; tmdb stays "k-neu"
    #expect(store.get(SecretNames.apiKey("tmdb"), profile: p.id) == "k-neu")
    #expect(SecretMigration.copyIntoStore(profiles: [p], store: store) == 0)
    #expect(SecretMigration.token("trakt", profile: Profile.makeDefault(name: "x"), store: store) == nil)
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
    #expect(SecretMigration.token("trakt", profile: Profile.makeDefault(name: "y").with(id: p.id), store: store) == rotated)
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

private extension Profile {
    func with(id: UUID) -> Profile { var p = self; p.id = id; return p }
}
