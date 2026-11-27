import Foundation
import Testing
@testable import PlayerCore

// Phase 0a.1, part 2: a configuration object this build cannot read at all (a newer build's shape, a wrong type)
// is kept as raw JSON. The app works with a stand-in (the default); the raw value is never written over.

private let pid = "6F9619FF-8B86-D011-B42D-00C04FC964FF"

/// A stored profile set with one profile; `fields` is spliced into the profile object.
private func storedData(_ fields: String) -> Data {
    Data(#"{"schemaVersion":\#(StoredProfiles.currentSchema),"profiles":[{"id":"\#(pid)","name":"A",\#(fields)}],"activeProfileID":"\#(pid)"}"#.utf8)
}

/// A JSON text (any value, also a bare string or number) as `JSONValue`.
private func rawValue(_ json: String) throws -> JSONValue {
    let list = try JSONDecoder().decode([JSONValue].self, from: Data("[\(json)]".utf8))
    return try #require(list.first)
}

private func sortedEncode<T: Encodable>(_ value: T) throws -> Data {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys]
    return try e.encode(value)
}

/// The first profile object of stored profiles data.
private func profileObject(_ data: Data) throws -> [String: JSONValue] {
    guard case .object(let top) = try JSONDecoder().decode(JSONValue.self, from: data),
          case .array(let list)? = top["profiles"], case .object(let profile)? = list.first else { throw StoreError.empty }
    return profile
}

private func layout(_ value: JSONValue?) throws -> HomeLayout {
    try JSONDecoder().decode(HomeLayout.self, from: JSONEncoder().encode(try #require(value)))
}

private let unreadableHomes = [
    #""kaputt""#,                                         // string
    "7",                                                  // number
    #"[{"rows":[]}]"#,                                    // array
    #"{"rows":"keine"}"#,                                 // object, `rows` of the wrong type
    #"{"sections":[{"kind":"hero","items":3}],"v":2}"#,   // object in a future shape (no `rows`)
]

@Test(arguments: unreadableHomes)
func unreadableHomeIsKeptInPlaceAndReported(raw: String) throws {
    let expected = try rawValue(raw)
    let (s, report) = try JSONDecoder().decodeReporting(StoredProfiles.self, from: storedData(#""home":\#(raw)"#))
    let p = try #require(s.profiles.first)
    #expect(p.home == HomeLayout())
    #expect(p.hasUnreadableHome)
    #expect(p.keptUnreadable == ["home": expected])
    #expect(report.ignored.contains("profiles[0].home"))
    // encode → decode → encode: the raw value is written back under `home`, bytes stay identical.
    let first = try sortedEncode(s)
    let obj = try profileObject(first)
    #expect(obj["home"] == expected)
    #expect(obj["keptUnreadable"] == nil)
    let (again, report2) = try JSONDecoder().decodeReporting(StoredProfiles.self, from: first)
    #expect(again == s)
    #expect(report2.ignored.contains("profiles[0].home"))
    #expect(try sortedEncode(again) == first)
}

@Test func editingTheStandInHomeKeepsTheRawValue() throws {
    let raw = #"{"sections":[{"kind":"hero"}]}"#
    let expected = try rawValue(raw)
    var s = try ProfileStore.decode(storedData(#""home":\#(raw)"#))
    s.profiles[0].home.rows = [HomeRow(content: .list(.watchlist))]
    let data = try sortedEncode(s)
    let obj = try profileObject(data)
    // The working layout under `home`, the raw value next to it.
    #expect(try layout(obj["home"]).rows.count == 1)
    #expect(obj["keptUnreadable"] == .object(["home": expected]))
    let (back, report) = try JSONDecoder().decodeReporting(StoredProfiles.self, from: data)
    #expect(back == s)
    #expect(back.profiles[0].home.rows.count == 1 && back.profiles[0].hasUnreadableHome)
    #expect(report.ignored.contains("profiles[0].home"))   // still reported: the `.bak` logic stays stable
    #expect(try sortedEncode(back) == data)
    // Emptied again: the raw value goes back in place.
    var reset = back
    reset.profiles[0].home = HomeLayout()
    let r = try profileObject(sortedEncode(reset))
    #expect(r["home"] == expected && r["keptUnreadable"] == nil)
}

@Test func rawValueInPlaceWinsOverAnOlderSiblingCopy() throws {
    let data = storedData(#""home":"neu","keptUnreadable":{"home":"alt"}"#)
    let (s, report) = try JSONDecoder().decodeReporting(StoredProfiles.self, from: data)
    #expect(s.profiles[0].keptUnreadable == ["home": .string("neu")])
    #expect(report.ignored.contains("profiles[0].home"))
    #expect(report.ignored.contains("profiles[0].keptUnreadable.home"))
}

@Test func readableHomeWritesNoNewKeys() throws {
    var p = Profile.makeDefault()
    p.home.rows.append(HomeRow(content: .collection(id: "c1")))
    let data = try sortedEncode(StoredProfiles(profiles: [p], activeProfileID: p.id))
    let obj = try profileObject(data)
    #expect(obj["keptUnreadable"] == nil)
    let (back, report) = try JSONDecoder().decodeReporting(StoredProfiles.self, from: data)
    #expect(report.isEmpty)
    #expect(back.profiles[0].keptUnreadable.isEmpty && !back.profiles[0].hasUnreadableHome)
    #expect(try sortedEncode(back) == data)
}

@Test func emptyHomeObjectsStayReadable() throws {
    for home in ["{}", #"{"rows":null}"#, "null"] {
        let (s, report) = try JSONDecoder().decodeReporting(StoredProfiles.self, from: storedData(#""home":\#(home)"#))
        #expect(s.profiles[0].home == HomeLayout() && !s.profiles[0].hasUnreadableHome)
        #expect(!report.ignored.contains("profiles[0].home"))
    }
}

@Test func profileStoreLoadSaveLoadKeepsUnreadableHome() throws {
    let raw = #"{"sections":[{"kind":"hero"}]}"#
    let expected = try rawValue(raw)
    let store = ProfileStore(directory: tempDir())
    try storedData(#""home":\#(raw)"#).write(to: store.fileURL)
    guard case .loaded(let s, let report) = store.loadResult() else { throw StoreError.empty }
    #expect(report.ignored.contains("profiles[0].home"))
    try store.save(s)
    #expect(try profileObject(Data(contentsOf: store.fileURL))["home"] == expected)
    guard case .loaded(var s2, _) = store.loadResult() else { throw StoreError.empty }
    #expect(s2 == s)
    // The user edits the stand-in and saves; the next load has both.
    s2.profiles[0].home.rows = [HomeRow(content: .list(.continueWatching))]
    try store.save(s2)
    guard case .loaded(let s3, let report3) = store.loadResult() else { throw StoreError.empty }
    #expect(s3.profiles[0].home.rows.count == 1)
    #expect(s3.profiles[0].keptUnreadable["home"] == expected)
    #expect(report3.ignored.contains("profiles[0].home"))
}

@Test func plainExportKeepsUnreadableHomeButNoSecrets() throws {
    let raw = #"{"sections":[]}"#
    let expected = try rawValue(raw)
    let s = try ProfileStore.decode(storedData(#""apiKeys":{"tmdb":"geheim"},"home":\#(raw)"#))
    let store = ProfileStore(directory: tempDir())
    let data = try store.exportData(s, includeSecrets: false)
    #expect(!String(decoding: data, as: UTF8.self).contains("geheim"))
    let back = try store.importData(data)
    #expect(back.profiles[0].apiKeys.isEmpty)
    #expect(back.profiles[0].keptUnreadable["home"] == expected)
}

// MARK: Other configuration objects of the profile, same mechanism

private let otherProfileObjects = [
    "audioPriority", "appearance", "diskCache", "sources", "player", "hiddenRows", "subtitleStyle", "skip", "look",
    "detailExtras",
]

@Test(arguments: otherProfileObjects)
func unreadableProfileObjectIsKeptInPlace(key: String) throws {
    let data = storedData(#""\#(key)":"aus der Zukunft""#)
    let (s, report) = try JSONDecoder().decodeReporting(StoredProfiles.self, from: data)
    #expect(s.profiles[0].keptUnreadable == [key: .string("aus der Zukunft")])
    #expect(report.ignored.contains("profiles[0].\(key)"))
    let first = try sortedEncode(s)
    let obj = try profileObject(first)
    #expect(obj[key] == .string("aus der Zukunft"))
    #expect(obj["keptUnreadable"] == nil)
    #expect(try sortedEncode(try JSONDecoder().decode(StoredProfiles.self, from: first)) == first)
}

@Test func editedPlayerSettingsMoveTheRawValueAside() throws {
    var s = try ProfileStore.decode(storedData(#""player":[{"rememberTracks":"neu"}]"#))
    let raw = try #require(s.profiles[0].keptUnreadable["player"])
    s.profiles[0].player.rememberTracks.toggle()
    let obj = try profileObject(sortedEncode(s))
    #expect(obj["keptUnreadable"] == .object(["player": raw]))
    let back = try ProfileStore.decode(sortedEncode(s))
    #expect(back.profiles[0].player == s.profiles[0].player && back.profiles[0].keptUnreadable["player"] == raw)
}

// MARK: Collections: unreadable folders

@Test func unreadableFolderSurvivesLoadAndSave() throws {
    let coll = #"{"id":"c1","title":"Filme","folders":[{"id":"f1","title":"A","sources":[]},{"id":"f2","sources":"neu"}]}"#
    let (s, report) = try JSONDecoder().decodeReporting(StoredProfiles.self, from: storedData(#""collections":[\#(coll)]"#))
    let c = try #require(s.profiles[0].collections.first)
    let broken = try rawValue(#"{"id":"f2","sources":"neu"}"#)
    #expect(c.folders.map(\.id) == ["f1"])
    #expect(c.unknownFolders == [broken])
    #expect(report.ignored.contains { $0.contains("folders[1]") })
    let first = try sortedEncode(s)
    let again = try JSONDecoder().decode(StoredProfiles.self, from: first)
    #expect(again == s)
    #expect(try sortedEncode(again) == first)
}

@Test func collectionWithFoldersOfTheWrongTypeIsKeptWhole() throws {
    let coll = #"{"id":"c1","title":"Filme","folders":{"neu":true}}"#
    let expected = try rawValue(coll)
    let s = try ProfileStore.decode(storedData(#""collections":[\#(coll)]"#))
    #expect(s.profiles[0].collections.isEmpty)
    #expect(s.profiles[0].unknownCollections == [expected])
    let obj = try profileObject(sortedEncode(s))
    #expect(obj["collections"] == .array([expected]))
}

@Test func readableCollectionEncodesAsBefore() throws {
    let c = MediaCollection(id: "c1", title: "Filme", folders: [Folder(id: "f1", title: "A", sources: [])])
    let text = String(decoding: try sortedEncode(c), as: UTF8.self)
    #expect(text == #"{"folders":[{"id":"f1","sources":[],"title":"A"}],"id":"c1","title":"Filme"}"#)
    #expect(try JSONDecoder().decode(MediaCollection.self, from: Data(#"{"id":"c1","title":"Filme"}"#.utf8)).folders.isEmpty)
}

// MARK: Device settings

@Test func unreadableDeviceSettingIsKeptInPlace() throws {
    let json = #"{"audioShaping":7,"displayMode":{"keepModeBetweenEpisodes":false},"remoteLogEnabled":false}"#
    let (d, report) = try JSONDecoder().decodeReporting(DeviceSettings.self, from: Data(json.utf8))
    #expect(d.audioShaping == AudioShapingSettings() && !d.displayMode.keepModeBetweenEpisodes)
    #expect(d.keptUnreadable == ["audioShaping": .int(7)])
    #expect(report.ignored.contains("audioShaping"))
    let first = try sortedEncode(d)
    guard case .object(let obj) = try JSONDecoder().decode(JSONValue.self, from: first) else { throw StoreError.empty }
    #expect(obj["audioShaping"] == .int(7) && obj["keptUnreadable"] == nil)
    let again = try JSONDecoder().decode(DeviceSettings.self, from: first)
    #expect(again == d)
    #expect(try sortedEncode(again) == first)
    // Edited: the setting is written, the raw value goes aside and survives the next read.
    var edited = again
    edited.audioShaping.nightMode = true
    let back = try JSONDecoder().decode(DeviceSettings.self, from: sortedEncode(edited))
    #expect(back.audioShaping.nightMode && back.keptUnreadable == ["audioShaping": .int(7)])
}

@Test func readableDeviceSettingsWriteNoNewKeys() throws {
    let text = String(decoding: try sortedEncode(DeviceSettings()), as: UTF8.self)
    #expect(!text.contains("keptUnreadable") && !text.contains("remoteLogReceiver"))
}

@Test func unreadableDeviceBlockIsCopiedAsideBeforeDefaults() throws {
    let storage = FileBlobStorage(directory: tempDir())
    try storage.write(DeviceSettingsStore.name, Data("kaputt".utf8))
    let store = DeviceSettingsStore(storage: storage, isMigrated: { true }, markMigrated: {})
    let r = store.loadOrMigrate()
    #expect(r.outcome == .blockUnreadable && r.settings == DeviceSettings())
    #expect(storage.read(DeviceSettingsStore.unreadableName) == Data("kaputt".utf8))
    // The defaults written over the block do not touch the copy.
    #expect(store.loadOrMigrate().outcome == .loaded)
    #expect(storage.read(DeviceSettingsStore.unreadableName) == Data("kaputt".utf8))
}
