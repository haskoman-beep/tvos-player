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

@Test func expiredTokensAreDropped() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var s = StoredProfiles.makeDefault()
    s.profiles[0].syncTokens = ["trakt": SyncToken(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(-1)),
                                "simkl": SyncToken(accessToken: "b"),
                                "other": SyncToken(accessToken: "c", expiresAt: now.addingTimeInterval(3600))]
    let (out, dropped) = s.droppingExpiredTokens(now: now)
    #expect(dropped == 1)
    #expect(Set(out.profiles[0].syncTokens.keys) == ["simkl", "other"])
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
