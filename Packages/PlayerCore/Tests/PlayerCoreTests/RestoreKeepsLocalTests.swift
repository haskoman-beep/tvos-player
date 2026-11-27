import Foundation
import Testing
@testable import PlayerCore

// Phase 0a, findings 3 to 5: restoring the plain export (no secrets) on the TV it came from must not shorten what
// is stored there, a restore must not delete profiles the backup does not know, and deleting a profile removes its
// data only after the save went through. All data is synthetic.

private let configured = "https://addon.example.invalid/eyJrZXkiOiJnZWhlaW0iLCJ4IjoxfQ==/manifest.json"
private let publicURL = "https://addon.example.invalid/manifest.json"
private let privateArt = "https://art.example.invalid/p.jpg?token=geheim"

private func addon(_ url: String, name: String = "A") -> InstalledAddon {
    InstalledAddon(manifestURL: url, manifest: AddonManifest(id: "com.example.a", name: name, version: "1",
                                                             resources: [], types: [], catalogs: []))
}

private func lastSource(addon: String, contentID: String) throws -> LastSource {
    let json: [String: Any] = ["addon": addon, "fingerprint": "datei.mkv", "contentID": contentID, "savedAt": 0]
    return try JSONDecoder().decode(LastSource.self, from: JSONSerialization.data(withJSONObject: json))
}

private func book(poster: String?, sourceAddon: String?) throws -> ProgressBook {
    var b = ProgressBook()
    var item = MetaPreview(id: "tt1", type: "movie", name: "Film")
    item.poster = poster
    b.entries["tt1"] = WatchProgress(id: "tt1", item: item, position: 100, duration: 1000,
                                     updated: Date(timeIntervalSince1970: 1_800_000_000))
    if let sourceAddon { b.sources = ["tt1": try lastSource(addon: sourceAddon, contentID: "tt1")] }
    return b
}

// MARK: Finding 3

@Test func plainRestoreKeepsTheConfiguredAddonAddress() {
    var here = Profile.makeDefault(name: "A")
    here.addons = [addon(configured)]
    let plain = StoredProfiles(profiles: [here], activeProfileID: here.id).withoutSecrets()
    #expect(plain.profiles[0].addons.map(\.manifestURL) == [publicURL])

    let (out, kept) = plain.keepingSecrets(from: [here])
    #expect(out.profiles[0].addons.map(\.manifestURL) == [configured])
    #expect(kept == 1)
}

@Test func plainRestoreKeepsBothConfigurationsOfOneAddon() {
    // The plain export folds two configurations of one addon into one entry.
    let second = configured.replacingOccurrences(of: "eyJr", with: "eyJs")
    var here = Profile.makeDefault(name: "A")
    here.addons = [addon(configured, name: "Eins"), addon(second, name: "Zwei")]
    let plain = StoredProfiles(profiles: [here], activeProfileID: here.id).withoutSecrets()
    #expect(plain.profiles[0].addons.count == 1)

    let (out, _) = plain.keepingSecrets(from: [here])
    #expect(out.profiles[0].addons.map(\.manifestURL) == [configured, second])
}

@Test func plainRestoreKeepsEntriesThisBuildCannotRead() {
    // Review: the plain export leaves the raw leftovers out; the profile on this TV still has them.
    var here = Profile.makeDefault(name: "A")
    here.unknownAddons = [.string("addon")]
    here.unknownCollections = [.string("sammlung")]
    here.unknownApiKeys = ["k": .int(1)]
    here.unknownSyncTokens = ["t": .int(2)]
    let plain = StoredProfiles(profiles: [here], activeProfileID: here.id).withoutSecrets()
    #expect(plain.profiles[0].unknownAddons.isEmpty)
    let (out, kept) = plain.keepingSecrets(from: [here])
    #expect(out.profiles[0] == here && kept == 1)
}

@Test func plainRestoreTakesTheBackupsEntryOfAnAddonWithoutConfiguration() {
    // Review: one configured addon must not make the other addons come from this TV as well.
    var here = Profile.makeDefault(name: "A")
    here.addons = [addon(configured), addon("https://b.example.invalid/manifest.json", name: "B hier")]
    var plain = StoredProfiles(profiles: [here], activeProfileID: here.id).withoutSecrets()
    plain.profiles[0].addons[1].manifest.name = "B aus Sicherung"
    let (out, _) = plain.keepingSecrets(from: [here])
    #expect(out.profiles[0].addons.map(\.manifestURL) == [configured, "https://b.example.invalid/manifest.json"])
    #expect(out.profiles[0].addons[1].manifest.name == "B aus Sicherung")
}

@Test func plainRestoreLeavesAnAddonAloneThatIsNotConfiguredHere() {
    var here = Profile.makeDefault(name: "A")
    here.addons = [addon("https://anders.example.invalid/manifest.json")]
    var plain = StoredProfiles(profiles: [here], activeProfileID: here.id)
    plain.profiles[0].addons = [addon(publicURL)]
    let (out, _) = plain.keepingSecrets(from: [here])
    #expect(out.profiles[0].addons.map(\.manifestURL) == [publicURL])
}

@Test func plainRestoreKeepsProgressArtAndLastSource() throws {
    let s = StoredProfiles.makeDefault()
    let id = try #require(s.activeProfileID)
    let local = try book(poster: privateArt, sourceAddon: configured)
    let plain = Backup(profiles: s, progress: [id: local]).withoutSecrets()
    #expect(plain.progress[id]?.entries["tt1"]?.item.poster == nil)
    #expect(plain.progress[id]?.sources?["tt1"]?.addon == publicURL)

    let out = plain.keepingLocalDetail(progress: [id: local], fusionKits: [:], collectionLinks: [:])
    #expect(out.progress[id] == local)
}

@Test func plainRestoreTakesPositionsFromTheBackup() throws {
    let s = StoredProfiles.makeDefault()
    let id = try #require(s.activeProfileID)
    let atBackup = try book(poster: privateArt, sourceAddon: nil)
    var now = atBackup
    now.entries["tt1"]?.position = 900
    let plain = Backup(profiles: s, progress: [id: atBackup]).withoutSecrets()

    let out = plain.keepingLocalDetail(progress: [id: now], fusionKits: [:], collectionLinks: [:])
    #expect(out.progress[id]?.entries["tt1"]?.position == 100)        // the restore still restores
    #expect(out.progress[id]?.entries["tt1"]?.item.poster == privateArt)   // but does not lose the picture
}

@Test func plainRestoreKeepsALastSourceTheExportHadToLeaveOut() throws {
    // An addon address without a readable host cannot be scrubbed; the export leaves the entry out.
    let s = StoredProfiles.makeDefault()
    let id = try #require(s.activeProfileID)
    let local = try book(poster: nil, sourceAddon: "://kaputt")
    let plain = Backup(profiles: s, progress: [id: local]).withoutSecrets()
    #expect(plain.progress[id]?.sources?["tt1"] == nil)

    let out = plain.keepingLocalDetail(progress: [id: local], fusionKits: [:], collectionLinks: [:])
    #expect(out.progress[id]?.sources?["tt1"]?.addon == "://kaputt")
}

@Test func plainRestoreKeepsKitsAndLinksItOnlyScrubbed() throws {
    let s = StoredProfiles.makeDefault()
    let id = try #require(s.activeProfileID)
    let own = FusionKitSource(id: "eigen", title: "Eigen", url: "https://kit.example.invalid/k.json?token=geheim", custom: true)
    let kit = try JSONEncoder().encode(FusionKitSettings(enabled: true, selected: ["fusion.eigen.a"], sources: [own]))
    let links = try JSONSerialization.data(withJSONObject: [
        ["id": "1", "url": "https://l.example.invalid/x?token=geheim"], ["id": "2", "url": "https://l.example.invalid/y"],
    ])
    let plain = Backup(profiles: s, fusionKits: [id: kit], collectionLinks: [id: links]).withoutSecrets()
    #expect(plain.fusionKits[id] != kit && plain.collectionLinks[id] != links)

    let out = plain.keepingLocalDetail(progress: [:], fusionKits: [id: kit], collectionLinks: [id: links])
    #expect(out.fusionKits[id] == kit)
    #expect(out.collectionLinks[id] == links)
}

@Test func plainRestoreTakesKitsAndLinksThatChangedSinceTheExport() throws {
    let s = StoredProfiles.makeDefault()
    let id = try #require(s.activeProfileID)
    let atBackup = try JSONEncoder().encode(FusionKitSettings(enabled: true, selected: ["fusion.a.b"]))
    let now = try JSONEncoder().encode(FusionKitSettings(enabled: false))
    let linksAtBackup = try JSONSerialization.data(withJSONObject: [["id": "1", "url": "https://l.example.invalid/y"]])
    let plain = Backup(profiles: s, fusionKits: [id: atBackup], collectionLinks: [id: linksAtBackup]).withoutSecrets()

    let out = plain.keepingLocalDetail(progress: [:], fusionKits: [id: now], collectionLinks: [id: Data("[]".utf8)])
    #expect(out.fusionKits[id] == plain.fusionKits[id])
    #expect(out.collectionLinks[id] == plain.collectionLinks[id])
}

@Test func plainRestoreAddsBackTheCustomSourcesAndLinksItLeftOut() throws {
    // Kit settings and links changed since the export: the backup wins, the parts it could not carry come back.
    let s = StoredProfiles.makeDefault()
    let id = try #require(s.activeProfileID)
    let own = FusionKitSource(id: "eigen", title: "Eigen", url: "https://kit.example.invalid/k.json?token=geheim", custom: true)
    let open = FusionKitSource(id: "a", title: "A", url: "https://kit.example.invalid/a.json", custom: false)
    let atBackup = FusionKitSettings(enabled: true, selected: ["fusion.a.x", "fusion.eigen.y"], sources: [open, own])
    var now = atBackup
    now.selected.append("fusion.a.z")
    let privateLink: [String: String] = ["id": "1", "url": "https://l.example.invalid/x?token=geheim"]
    let linksAtBackup = [privateLink, ["id": "2", "url": "https://l.example.invalid/y"]]
    let linksNow = linksAtBackup + [["id": "3", "url": "https://l.example.invalid/z"]]
    let plain = Backup(profiles: s, fusionKits: [id: try JSONEncoder().encode(atBackup)],
                       collectionLinks: [id: try JSONSerialization.data(withJSONObject: linksAtBackup)]).withoutSecrets()

    let out = plain.keepingLocalDetail(progress: [:], fusionKits: [id: try JSONEncoder().encode(now)],
                                       collectionLinks: [id: try JSONSerialization.data(withJSONObject: linksNow)])
    let kitData = try #require(out.fusionKits[id])
    let kit = try JSONDecoder().decode(FusionKitSettings.self, from: kitData)
    #expect(kit.sources == [open, own])
    #expect(kit.selected == ["fusion.a.x", "fusion.eigen.y"])   // "fusion.a.z" was chosen after the backup
    let linkData = try #require(out.collectionLinks[id])
    let links = try #require(try JSONSerialization.jsonObject(with: linkData) as? [[String: String]])
    #expect(links == [["id": "2", "url": "https://l.example.invalid/y"], privateLink])
}

@Test func backupWithSecretsIsRestoredAsItIs() throws {
    var p = Profile.makeDefault()
    p.apiKeys = ["tmdb": "k"]
    let s = StoredProfiles(profiles: [p], activeProfileID: p.id)
    let inBackup = try book(poster: nil, sourceAddon: publicURL)
    let b = Backup(profiles: s, progress: [p.id: inBackup])
    let out = b.keepingLocalDetail(progress: [p.id: try book(poster: privateArt, sourceAddon: configured)],
                                   fusionKits: [:], collectionLinks: [:])
    #expect(out == b)
}

// MARK: Finding 4

@Test func restoreKeepsLocalProfilesTheBackupDoesNotKnow() {
    let a = Profile.makeDefault(name: "A")
    var later = Profile.makeDefault(name: "Später angelegt")
    later.apiKeys = ["tmdb": "k"]
    let here = StoredProfiles(profiles: [a, later], activeProfileID: later.id)
    let backup = StoredProfiles(profiles: [a], activeProfileID: a.id)

    let out = backup.keepingLocalProfiles(from: here) { _ in false }
    #expect(out.profiles.map(\.id) == [a.id, later.id])
    #expect(out.profiles[1] == later)
    #expect(out.activeProfileID == a.id)
}

@Test func restoreDropsAnUntouchedDefaultProfile() {
    // Fresh install: the default profile nobody used gives way to the restored ones.
    let fresh = StoredProfiles.makeDefault()
    let a = Profile.makeDefault(name: "A")
    let out = StoredProfiles(profiles: [a], activeProfileID: a.id).keepingLocalProfiles(from: fresh) { _ in false }
    #expect(out.profiles.map(\.id) == [a.id])
}

@Test func restoreKeepsADefaultProfileThatHasProgress() {
    let fresh = StoredProfiles.makeDefault()
    let a = Profile.makeDefault(name: "A")
    let out = StoredProfiles(profiles: [a], activeProfileID: a.id).keepingLocalProfiles(from: fresh) { _ in true }
    #expect(out.profiles.count == 2)
}

@Test func restoreKeepsUnreadableLocalProfiles() {
    var here = StoredProfiles.makeDefault()
    let onlyHere = JSONValue.object(["name": .string("Nur hier")])
    here.unknownProfiles = [.object(["name": .string("Ohne ID")]), onlyHere]
    let a = Profile.makeDefault(name: "A")
    var backup = StoredProfiles(profiles: [a], activeProfileID: a.id)
    backup.unknownProfiles = [.object(["name": .string("Ohne ID")]), .object(["name": .string("Auch unlesbar")])]
    let out = backup.keepingLocalProfiles(from: here) { _ in false }
    #expect(out.unknownProfiles == backup.unknownProfiles + [onlyHere])   // the shared one once, not twice
}

// MARK: Finding 5

/// Takes reads, refuses every write (a full disk).
private struct ReadOnlyStorage: BlobStorage {
    let base: FileBlobStorage
    func read(_ name: String) -> Data? { base.read(name) }
    func write(_ name: String, _ data: Data) throws { throw TieredBlobStorage.StorageFull(bytes: data.count) }
    func remove(_ name: String) { base.remove(name) }
}

@Test func deletingAProfileThrowsWhenTheSaveFailsAndKeepsItsData() throws {
    let dir = FileBlobStorage(directory: tempDir())
    let a = Profile.makeDefault(name: "A"), b = Profile.makeDefault(name: "B")
    let s = StoredProfiles(profiles: [a, b], activeProfileID: a.id)
    try ProfileStore(storage: dir).save(s)
    try dir.write("progress-\(b.id.uuidString).json", Data("buch".utf8))

    let store = ProfileStore(storage: ReadOnlyStorage(base: dir))
    #expect(throws: (any Error).self) { try store.delete(profile: b.id, from: s, blocks: dir) }
    #expect(dir.read("progress-\(b.id.uuidString).json") == Data("buch".utf8))
    let onDisk = try #require(dir.read("profiles.json"))
    #expect(try ProfileStore.decode(onDisk).profiles.count == 2)
}

@Test func deletingAProfileSavesFirstAndThenRemovesItsBlocks() throws {
    let dir = FileBlobStorage(directory: tempDir())
    let a = Profile.makeDefault(name: "A"), b = Profile.makeDefault(name: "B")
    let s = StoredProfiles(profiles: [a, b], activeProfileID: b.id)
    let store = ProfileStore(storage: dir)
    try store.save(s)
    try dir.write("progress-\(b.id.uuidString).json", Data("buch".utf8))
    try dir.write("progress-\(a.id.uuidString).json", Data("bleibt".utf8))

    let out = try store.delete(profile: b.id, from: s, blocks: dir)
    #expect(out.profiles.profiles.map(\.id) == [a.id])
    #expect(out.profiles.activeProfileID == a.id)
    #expect(out.removed == ["progress-\(b.id.uuidString).json"])
    #expect(dir.read("progress-\(a.id.uuidString).json") == Data("bleibt".utf8))
    let onDisk = try #require(dir.read("profiles.json"))
    #expect(try ProfileStore.decode(onDisk).profiles.map(\.id) == [a.id])
}

@Test func theLastProfileCannotBeDeleted() throws {
    let s = StoredProfiles.makeDefault()
    let dir = FileBlobStorage(directory: tempDir())
    #expect(throws: StoreError.self) { try ProfileStore(storage: dir).delete(profile: s.profiles[0].id, from: s, blocks: dir) }
}

// MARK: Finding 7

/// A stream without a known length reports an infinite duration. Stored once, JSON cannot encode the book any more
/// and every later save of it fails.
@Test func progressWithInfiniteDurationIsNotRecorded() throws {
    var b = ProgressBook()
    let item = MetaPreview(id: "tt1", type: "movie", name: "Film")
    b.record(id: "tt1", item: item, position: 100, duration: 1000)
    b.record(id: "tt2", item: MetaPreview(id: "tt2", type: "movie", name: "Live"), position: 100, duration: .infinity)
    b.record(id: "tt3", item: MetaPreview(id: "tt3", type: "movie", name: "Rückwärts"), position: -5, duration: 1000)
    #expect(Set(b.entries.keys) == ["tt1"])
    #expect(throws: Never.self) { try JSONEncoder().encode(b) }
}

@Test func fileProgressWithInfiniteDurationIsNotRecorded() throws {
    var b = FileProgressBook()
    b.record("torbox:1:1", position: 100, duration: 1000)
    b.record("torbox:1:2", position: 100, duration: .infinity)
    #expect(Set(b.entries.keys) == ["torbox:1:1"])
    #expect(throws: Never.self) { try JSONEncoder().encode(b) }
}
