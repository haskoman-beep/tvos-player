import Foundation
import Testing
@testable import PlayerCore

// Task 2.4. All data here and in `Fixtures/backup-v2.json` is synthetic.

private func backupFixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func kitRow(_ id: String) -> HomeRow { HomeRow(content: .collection(id: id)) }

@Test func backupReadsVersion1() throws {
    let b = try Backup.decode(try backupFixture("build249-profiles.json"))
    #expect(b.backupVersion == 1)
    #expect(!b.profiles.profiles.isEmpty)
    #expect(b.progress.isEmpty && b.fusionKits.isEmpty && b.collectionLinks.isEmpty && b.device == nil)
    #expect(b.profiles == (try ProfileStore.decode(try backupFixture("build249-profiles.json"))))
}

@Test func backupVersion2RoundTrip() throws {
    let s = StoredProfiles.makeDefault()
    let id = try #require(s.activeProfileID)
    var book = ProgressBook()
    let item = MetaPreview(id: "tt1", type: "movie", name: "Film")
    book.entries["tt1"] = WatchProgress(id: "tt1", item: item, position: 100, duration: 1000,
                                        updated: Date(timeIntervalSince1970: 1_800_000_000))
    let kit = try JSONEncoder().encode(FusionKitSettings(enabled: true, selected: ["fusion.a.b"]))
    let b = Backup(profiles: s, progress: [id: book], fusionKits: [id: kit], collectionLinks: [id: Data("[]".utf8)],
                   device: DeviceSettings())
    let back = try Backup.decode(try b.encoded())
    #expect(back == b)
    #expect(back.backupVersion == 2)
}

@Test func backupVersion2StaysReadableAsProfiles() throws {
    // Build 1 / build 249 import path: the file is decoded as `StoredProfiles`.
    let data = try backupFixture("backup-v2.json")
    let old = try ProfileStore(directory: FileManager.default.temporaryDirectory).importData(data)
    let b = try Backup.decode(data)
    #expect(old == b.profiles)
    #expect(b.backupVersion == 2)
    #expect(b.progress.count == 1 && b.fusionKits.count == 1 && b.collectionLinks.count == 1 && b.device != nil)
    // A version 2 file written now is read by the same old path.
    #expect((try JSONDecoder().decode(StoredProfiles.self, from: try b.encoded())) == b.profiles)
}

@Test func backupBadPartIsSkippedNotFatal() throws {
    let s = StoredProfiles.makeDefault()
    var json = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(s)) as? [String: Any])
    json["backupVersion"] = 2
    json["progress"] = ["kein-uuid": ["schemaVersion": 1, "entries": [:]], UUID().uuidString: "kaputt"]
    json["device"] = "kaputt"
    let (b, report) = try Backup.decodeReporting(try JSONSerialization.data(withJSONObject: json))
    #expect(b.profiles == s)
    #expect(b.progress.isEmpty && b.device == nil)
    #expect(!report.isEmpty)
}

@Test func kitRowsStayWithoutSettings() {
    let layout = HomeLayout(rows: [kitRow("fusion.a.b"), HomeRow(content: .list(.watchlist))])
    #expect(FusionKitSync.apply(settings: nil, layout: layout) == layout)
    // Loaded with a selection: this rule leaves the rows to the full sync.
    let chosen = FusionKitSettings(enabled: true, selected: ["fusion.a.b"])
    #expect(FusionKitSync.apply(settings: chosen, layout: layout) == layout)
}

@Test func kitRowsGoWithExplicitlyEmptySelection() {
    let own = HomeRow(content: .list(.watchlist))
    let layout = HomeLayout(rows: [kitRow("fusion.a.b"), own])
    #expect(FusionKitSync.apply(settings: FusionKitSettings(enabled: true, selected: []), layout: layout).rows == [own])
    #expect(FusionKitSync.apply(settings: FusionKitSettings(enabled: false, selected: ["fusion.a.b"]), layout: layout).rows == [own])
}

/// Final review I2 (ruling): only an expired login without a refresh token is dropped.
@Test func expiredTokensAreDropped() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var s = StoredProfiles.makeDefault()
    s.profiles[0].syncTokens = ["trakt": SyncToken(accessToken: "a", expiresAt: now.addingTimeInterval(-1)),
                                "simkl": SyncToken(accessToken: "b"),
                                "other": SyncToken(accessToken: "c", expiresAt: now.addingTimeInterval(3600))]
    let (out, dropped) = s.droppingExpiredTokens(now: now)
    #expect(dropped == 1)
    #expect(Set(out.profiles[0].syncTokens.keys) == ["simkl", "other"])
}

/// Final review I2: an expired login with a refresh token stays; `AppModel.token(_:)` renews it on first use.
@Test func expiredRefreshableTokenIsKept() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var s = StoredProfiles.makeDefault()
    let t = SyncToken(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(-86_400 * 120))
    s.profiles[0].syncTokens = ["trakt": t]
    let (out, dropped) = s.droppingExpiredTokens(now: now)
    #expect(dropped == 0)
    #expect(out.profiles[0].syncTokens["trakt"] == t)
}

@Test func deletingProfileRemovesAllItsBlocks() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("backup-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let files = FileBlobStorage(directory: dir)
    let mem = MemoryKeyValueBlobs()
    let storage = TieredBlobStorage(defaults: mem, directories: [files])
    let gone = UUID(), kept = UUID()
    let mine = ["progress-\(gone.uuidString).json", "progress-\(gone.uuidString).json.bak", "catalog-\(gone.uuidString).json",
                "linkpack-\(gone.uuidString)-x1.json", "\(TieredBlobStorage.fileOnlyPrefix)media-\(gone.uuidString)-x2.json"]
    let others = ["progress-\(kept.uuidString).json", "profiles.json", "device-settings.json"]
    for n in mine + others { try storage.write(n, Data("{}".utf8)) }
    let removed = ProfileBlocks.remove(profile: gone, from: storage)
    #expect(Set(removed) == Set(mine))
    for n in mine { #expect(storage.read(n) == nil) }
    for n in others { #expect(storage.read(n) != nil) }
}

@Test func plainBackupHoldsNoSecretURLs() throws {
    let secret = "GEHEIM0123456789abcdefXYZ"
    var s = StoredProfiles.makeDefault()
    let id = try #require(s.activeProfileID)
    s.profiles[0].apiKeys = ["tmdb": secret]
    var book = ProgressBook()
    let item = MetaPreview(id: "tt1", type: "movie", name: "Film", poster: "https://img.example.org/p.jpg?apikey=\(secret)",
                           background: "https://img.example.org/b.jpg", logo: "https://u:\(secret)@img.example.org/l.png")
    book.entries["tt1"] = WatchProgress(id: "tt1", item: item, position: 1, duration: 10, updated: Date(timeIntervalSince1970: 0))
    let kit = FusionKitSettings(enabled: true, selected: ["fusion.mine.a", "fusion.pub.b"], sources: [
        FusionKitSource(id: "mine", title: "Mein Kit", url: "https://kits.example.org/\(secret)/kit.json", custom: true),
        FusionKitSource(id: "pub", title: "Kit", url: "https://kits.example.org/kit.json", custom: true)])
    let links: [[String: Any]] = [["id": "a", "url": "https://lists.example.org/x?token=\(secret)", "format": "f", "summary": "s", "at": 0],
                                  ["id": "b", "url": "https://lists.example.org/list.json", "format": "f", "summary": "s", "at": 0],
                                  ["id": "c", "format": "f", "summary": "code", "at": 0]]
    let full = Backup(profiles: s, progress: [id: book], fusionKits: [id: try JSONEncoder().encode(kit)],
                      collectionLinks: [id: try JSONSerialization.data(withJSONObject: links)],
                      device: DeviceSettings(remoteLogEnabled: true, remoteLogReceiver: "Empfaenger"))
    // Sealed backup keeps everything.
    #expect(String(decoding: try full.encoded(), as: UTF8.self).contains(secret))

    let plainData = try full.withoutSecrets().encoded()
    let text = String(decoding: plainData, as: UTF8.self)
    #expect(!text.contains(secret))
    let plain = try Backup.decode(plainData)
    for d in Array(plain.fusionKits.values) + Array(plain.collectionLinks.values) { #expect(!String(decoding: d, as: UTF8.self).contains(secret)) }
    let e = try #require(plain.progress[id]?.entries["tt1"])
    #expect(e.item.poster == nil && e.item.logo == nil && e.item.background == "https://img.example.org/b.jpg")
    let kitData = try #require(plain.fusionKits[id])
    let k = try JSONDecoder().decode(FusionKitSettings.self, from: kitData)
    #expect(k.sources.map(\.id) == ["pub"] && k.selected == ["fusion.pub.b"])
    let linkData = try #require(plain.collectionLinks[id])
    let l = try #require(try JSONSerialization.jsonObject(with: linkData) as? [[String: Any]])
    #expect(l.compactMap { $0["id"] as? String } == ["b", "c"])
    #expect(plain.device?.remoteLogReceiver == nil && plain.device?.remoteLogEnabled == false)
}

@Test func restoreRemovesOnlyProfilesNotInTheBackup() {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    #expect(ProfileBlocks.removedByRestore(before: [a, b, c, a], after: [b, d]) == [a, c])
    #expect(ProfileBlocks.removedByRestore(before: [a, b], after: [b, a]).isEmpty)
}

// MARK: Task 3.9: a restore without keys keeps the keys of this TV

private func keyedProfile(_ name: String) -> Profile {
    var p = Profile.makeDefault(name: name)
    p.apiKeys = ["tmdb": "k-tmdb-\(name)", LogSignature.secretKey: "log-\(name)"]
    p.syncTokens = ["trakt": SyncToken(accessToken: "a-\(name)", refreshToken: "r-\(name)")]
    return p
}

/// Same profile ID: keys, logins and the remote-log secret of this TV stay. A new ID gets none.
@Test func keylessRestoreKeepsKeysOfSameProfileID() throws {
    let here = keyedProfile("A")
    let current = [here, keyedProfile("Weg")]
    var restoredA = here; restoredA.name = "A aus Sicherung"
    let newcomer = Profile.makeDefault(name: "Neu")
    let full = StoredProfiles(profiles: [restoredA, newcomer], activeProfileID: restoredA.id)
    let plain = Backup(profiles: full).withoutSecrets().profiles
    #expect(!plain.carriesSecrets)

    let (out, kept) = plain.keepingSecrets(from: current)
    #expect(kept == 1)
    #expect(out.profiles[0].name == "A aus Sicherung")   // the rest comes from the backup
    #expect(out.profiles[0].apiKeys == here.apiKeys)
    #expect(out.profiles[0].apiKeys[LogSignature.secretKey] == "log-A")
    #expect(out.profiles[0].syncTokens == here.syncTokens)
    #expect(out.profiles[1].apiKeys.isEmpty && out.profiles[1].syncTokens.isEmpty)
    #expect(out.profiles.count == 2 && out.activeProfileID == restoredA.id)
}

/// Gaps of the current profile are filled from the Keychain copy, but only for IDs that exist on this TV.
@Test func keylessRestoreFillsFromStoreForKnownIDsOnly() {
    let store = MemorySecretStore()
    var here = Profile.makeDefault(name: "A")
    here.apiKeys = ["tmdb": "k-tmdb"]
    let stranger = Profile.makeDefault(name: "Fremd")
    try? store.set("k-torbox", name: SecretNames.apiKey("torbox"), profile: here.id)
    try? store.set("k-fremd", name: SecretNames.apiKey("tmdb"), profile: stranger.id)
    let plain = StoredProfiles(profiles: [Profile(id: here.id, name: "A"), Profile(id: stranger.id, name: "Fremd")])
    let (out, kept) = plain.keepingSecrets(from: [here], store: store)
    #expect(kept == 1)
    #expect(out.profiles[0].apiKeys == ["tmdb": "k-tmdb", "torbox": "k-torbox"])
    #expect(out.profiles[1].apiKeys.isEmpty)   // not on this TV: nothing from the Keychain either
}

/// A backup that carries keys (sealed) is restored as it is: its own values win, nothing is added.
@Test func backupWithKeysKeepsItsOwnValues() {
    let here = keyedProfile("A")
    var fromBackup = here
    fromBackup.apiKeys = ["tmdb": "k-aus-sicherung"]
    fromBackup.syncTokens = [:]
    let sealed = StoredProfiles(profiles: [fromBackup], activeProfileID: here.id)
    #expect(sealed.carriesSecrets)
    let (out, kept) = sealed.keepingSecrets(from: [here], store: MemorySecretStore())
    #expect(kept == 0)
    #expect(out == sealed)
    // A login alone also counts as carrying secrets; an empty key value does not.
    var tokenOnly = Profile.makeDefault(); tokenOnly.syncTokens = ["simkl": SyncToken(accessToken: "s")]
    #expect(StoredProfiles(profiles: [tokenOnly]).carriesSecrets)
    var emptyKey = Profile.makeDefault(); emptyKey.apiKeys = ["tmdb": ""]
    #expect(!StoredProfiles(profiles: [emptyKey]).carriesSecrets)
}

/// Nuvio T2: the session is only in the secret store. Neither `profiles.json` nor any backup (plain or with keys)
/// holds it, and a restore without keys does not pull it into a profile.
@Test func backupsNeverHoldTheNuvioSession() throws {
    let store = MemorySecretStore()
    try NuvioSessionStore(store: store).save(nuvioTestSession())
    var s = StoredProfiles.makeDefault()
    s.profiles[0].apiKeys = ["tmdb": "k-tmdb"]
    s.profiles[0].syncTokens = ["trakt": SyncToken(accessToken: "a-trakt", refreshToken: "r-trakt")]
    SecretMigration.copyIntoStore(profiles: s.profiles, store: store)
    let full = Backup(profiles: s)
    let restored = full.withoutSecrets().profiles.keepingSecrets(from: s.profiles, store: store).profiles
    let texts = [try JSONEncoder().encode(s), try full.encoded(), try full.withoutSecrets().encoded(),
                 try JSONEncoder().encode(restored)].map { String(decoding: $0, as: UTF8.self) }
    for t in texts {
        #expect(!t.lowercased().contains("nuvio"))
        #expect(!t.contains("AT1-nuvio-access"))
        #expect(!t.contains("RT1-nuvio-refresh"))
    }
}
