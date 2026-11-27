import Foundation
import Testing
@testable import PlayerCore

// Phase 0a, finding 2: entries this build cannot read must survive load → save. Before, they were skipped while
// loading and the next save wrote the shrunken state for good.

/// One stored profile set as editable JSON.
private func storedJSON() throws -> [String: Any] {
    var p = Profile.makeDefault()
    p.apiKeys = ["tmdb": "k1"]
    let data = try JSONEncoder().encode(StoredProfiles(profiles: [p], activeProfileID: p.id))
    return try JSONSerialization.jsonObject(with: data) as! [String: Any]
}

/// Load as the app does, save again, and hand back the saved JSON.
private func roundTrip(_ json: [String: Any]) throws -> (loaded: StoredProfiles, saved: [String: Any]) {
    let store = ProfileStore(directory: tempDir())
    try JSONSerialization.data(withJSONObject: json).write(to: store.fileURL)
    guard case .loaded(let s, _) = store.loadResult() else { throw StoreError.empty }
    try store.save(s)
    return (s, try JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as! [String: Any])
}

private func firstProfile(_ json: [String: Any]) -> [String: Any] { (json["profiles"] as! [[String: Any]])[0] }

private func with(_ json: [String: Any], _ change: (inout [String: Any]) -> Void) -> [String: Any] {
    var json = json
    var list = json["profiles"] as! [[String: Any]]
    change(&list[0])
    json["profiles"] = list
    return json
}

@Test func unreadableProfileSurvivesLoadAndSave() throws {
    var json = try storedJSON()
    var list = json["profiles"] as! [[String: Any]]
    list.append(["name": "Ohne ID", "apiKeys": ["tmdb": "k2"]])
    json["profiles"] = list
    let (loaded, saved) = try roundTrip(json)
    #expect(loaded.profiles.count == 1)
    let after = saved["profiles"] as! [[String: Any]]
    #expect(after.count == 2)
    #expect(after.last?["name"] as? String == "Ohne ID")
}

@Test func unreadableAddonSurvivesLoadAndSave() throws {
    let json = with(try storedJSON()) { $0["addons"] = [["zukunft": 1]] }
    let (loaded, saved) = try roundTrip(json)
    #expect(loaded.profiles[0].addons.isEmpty)
    #expect((firstProfile(saved)["addons"] as? [[String: Int]]) == [["zukunft": 1]])
}

@Test func unreadableCollectionSurvivesLoadAndSave() throws {
    let json = with(try storedJSON()) { $0["collections"] = [["zukunft": 1]] }
    let (loaded, saved) = try roundTrip(json)
    #expect(loaded.profiles[0].collections.isEmpty)
    #expect((firstProfile(saved)["collections"] as? [[String: Int]]) == [["zukunft": 1]])
}

@Test func oneUnreadableApiKeyDoesNotEmptyTheOthers() throws {
    let json = with(try storedJSON()) { $0["apiKeys"] = ["tmdb": "k1", "neu": ["wert": 1]] }
    let (loaded, saved) = try roundTrip(json)
    #expect(loaded.profiles[0].apiKeys == ["tmdb": "k1"])
    let keys = firstProfile(saved)["apiKeys"] as! [String: Any]
    #expect(keys["tmdb"] as? String == "k1")
    #expect(keys["neu"] as? [String: Int] == ["wert": 1])
}

@Test func unreadableSyncTokenSurvivesLoadAndSave() throws {
    let json = with(try storedJSON()) { $0["syncTokens"] = ["trakt": ["zukunft": 1]] }
    let (loaded, saved) = try roundTrip(json)
    #expect(loaded.profiles[0].syncTokens.isEmpty)
    #expect((firstProfile(saved)["syncTokens"] as? [String: [String: Int]]) == ["trakt": ["zukunft": 1]])
}

@Test func aKeyEnteredAgainReplacesItsUnreadableLeftover() throws {
    let json = with(try storedJSON()) { $0["apiKeys"] = ["tmdb": ["wert": 1]] }
    let store = ProfileStore(directory: tempDir())
    try JSONSerialization.data(withJSONObject: json).write(to: store.fileURL)
    guard case .loaded(var s, _) = store.loadResult() else { Issue.record("expected .loaded"); return }
    s.profiles[0].apiKeys["tmdb"] = "neu"
    try store.save(s)
    let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as! [String: Any]
    #expect((firstProfile(saved)["apiKeys"] as? [String: String]) == ["tmdb": "neu"])
}

@Test func exportWithoutSecretsLeavesOutUnreadLeftovers() throws {
    // Raw leftovers cannot be scrubbed (their structure is unknown), so the export without secrets drops them.
    var json = with(try storedJSON()) {
        $0["addons"] = [["manifestURL": 5, "token": "geheim"]]
        $0["collections"] = [["link": "https://x/geheim"]]
        $0["apiKeys"] = ["neu": ["wert": "geheim"]]
        $0["syncTokens"] = ["trakt": ["zukunft": "geheim"]]
    }
    var list = json["profiles"] as! [[String: Any]]
    list.append(["name": "Ohne ID", "apiKeys": ["tmdb": "geheim"]])
    json["profiles"] = list
    let store = ProfileStore(directory: tempDir())
    let s = try store.importData(JSONSerialization.data(withJSONObject: json))
    let out = String(decoding: try store.exportData(s, includeSecrets: false), as: UTF8.self)
    #expect(!out.contains("geheim"))
}
