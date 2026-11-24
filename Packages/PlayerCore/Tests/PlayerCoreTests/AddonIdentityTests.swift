import Foundation
import Testing
@testable import PlayerCore

// Task 3.6 (A-A-9, A-A-13, A-A-16). All addresses and names are synthetic.

private func idFixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func sourceAddon(_ url: String, _ name: String, id: String = "org.example.sources") -> InstalledAddon {
    InstalledAddon(manifestURL: url, manifest: AddonManifest(id: id, name: name, version: "1",
                                                             resources: [AddonResource(name: "stream")],
                                                             types: ["movie"], idPrefixes: ["tt"]))
}

/// How builds 249/250, Build 1 and Build 2 decode an addon (synthesized Codable, no identity keys).
private struct OldInstalledAddon: Codable, Equatable { var manifestURL: String; var manifest: AddonManifest }
private struct OldProfileAddons: Decodable { var addons: [OldInstalledAddon] }

@Test func addonIdentityIsDerivedFromTheAddress() {
    let a = sourceAddon("https://one.example/cfg-a/manifest.json", "Quellen")
    let b = sourceAddon("https://one.example/cfg-b/manifest.json", "Quellen")
    #expect(a.instanceID != b.instanceID)
    #expect(a.manifestID == "org.example.sources" && b.manifestID == a.manifestID)
    // The same installation link in another spelling is the same instance.
    #expect(sourceAddon("  https://one.example/cfg-a/manifest.json ", "Quellen").instanceID == a.instanceID)
    #expect(sourceAddon("https://one.example/cfg-a/manifest.json?v=1", "Quellen").instanceID != a.instanceID)
    // The ID is a hash: the address (with its access part) never appears in it.
    #expect(a.instanceID.hasPrefix("addon-") && !a.instanceID.contains("example") && !a.instanceID.contains("cfg"))
    // Derived values follow the address (e.g. `withoutSecrets` rewrites it).
    var c = a
    c.manifestURL = b.manifestURL
    #expect(c.instanceID == b.instanceID)
}

@Test func storedProfilesOfOlderBuildsGetDerivedAddonIdentity() throws {
    let build249 = try ProfileStore.decode(try idFixture("build249-profiles.json"))
    let build1 = try ProfileStore.decode(try idFixture("main-profiles-v1.json"))
    let build2 = try Backup.decode(try idFixture("backup-v2.json")).profiles
    for s in [build249, build1, build2] {
        let addons = s.profiles.flatMap(\.addons)
        #expect(!addons.isEmpty)
        for a in addons {
            #expect(a.instanceID == AddonIdentity.instanceID(manifestURL: a.manifestURL))
            #expect(a.manifestID == a.manifest.id)
        }
    }
    // Unchanged identity adds nothing: the build 249 file is written back byte for byte.
    let data = try idFixture("build249-profiles.json")
    #expect(try ProfileStore(directory: FileManager.default.temporaryDirectory).exportData(build249) == data)
}

@Test func olderBuildsReadAddonsWithExplicitIdentity() throws {
    var a = sourceAddon("https://one.example/cfg-a/manifest.json", "Quellen")
    a.instanceID = "instance-kept-after-relink"
    a.manifestID = "org.example.renamed"
    let plain = sourceAddon("https://two.example/manifest.json", "Zweite")
    let profile = Profile(name: "Test", addons: [a, plain])
    let data = try JSONEncoder().encode(profile)

    // Older builds: they read the addons and ignore the new keys.
    let old = try JSONDecoder().decode(OldProfileAddons.self, from: data)
    #expect(old.addons == [OldInstalledAddon(manifestURL: a.manifestURL, manifest: a.manifest),
                           OldInstalledAddon(manifestURL: plain.manifestURL, manifest: plain.manifest)])
    // Only an explicit identity is written.
    let raw = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let list = try #require(raw["addons"] as? [[String: Any]])
    #expect(list[0]["instanceID"] as? String == "instance-kept-after-relink")
    #expect(list[0]["manifestID"] as? String == "org.example.renamed")
    #expect(list[1]["instanceID"] == nil && list[1]["manifestID"] == nil)
    // This build reads it back unchanged; an unreadable identity value falls back to the derived one.
    #expect(try JSONDecoder().decode(Profile.self, from: data) == profile)
    let broken = #"{"manifestURL":"https://two.example/manifest.json","instanceID":42,"manifest":{"id":"x","name":"X","resources":[],"types":[]}}"#
    let b = try JSONDecoder().decode(InstalledAddon.self, from: Data(broken.utf8))
    #expect(b.instanceID == AddonIdentity.instanceID(manifestURL: "https://two.example/manifest.json"))
}

@Test func twoInstallationsWithOneNameStayApart() {
    let first = sourceAddon("https://one.example/cfg-a/manifest.json", "Quellen")
    let second = sourceAddon("https://one.example/cfg-b/manifest.json", "Quellen")
    let other = sourceAddon("https://two.example/manifest.json", "Andere", id: "org.example.other")
    let installed = [first, other, second]
    let labels = AddonIdentity.labels(installed)
    #expect(labels[first.instanceID] == "Quellen" && labels[second.instanceID] == "Quellen (2)" && labels[other.instanceID] == "Andere")

    // Second instance timed out, first answered: the result is partial, not complete.
    let failed = AddonIdentity.unanswered(asked: [first, second], answered: [first], in: installed)
    #expect(failed == ["Quellen (2)"])
    let s1 = StreamItem(name: "[TB⚡] Quellen", url: "https://example.invalid/1")
    let s2 = StreamItem(name: "[TB⚡] Quellen", url: "https://example.invalid/2")
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let previous = (at: t0, list: [(addon: "Quellen", stream: s1), (addon: "Quellen (2)", stream: s2)])
    let outcome = StreamCacheUpdate.apply(fresh: [(addon: "Quellen", stream: s1)], answered: ["Quellen"], failed: failed,
                                          previous: previous, previousFetchedAt: [:], now: t0.addingTimeInterval(30))
    guard case let .store(_, list, _) = outcome else { Issue.record("expected a stored list"); return }
    #expect(list.map(\.addon) == ["Quellen", "Quellen (2)"])   // the silent instance keeps its entry

    // The remembered source of the second instance is looked up at the second instance.
    #expect(AddonIdentity.addon(labeled: "Quellen (2)", in: installed)?.instanceID == second.instanceID)
    #expect(AddonIdentity.addon(labeled: "Quellen", in: installed)?.instanceID == first.instanceID)
    // The search status names them apart, too.
    let p = AddonSearchProgress(addons: [(index: 0, addon: first), (index: 2, addon: second)], installed: installed)
    #expect(p.statuses.map(\.name) == ["Quellen", "Quellen (2)"])
    #expect(p.label(of: second) == "Quellen (2)")
}

@Test func extraValuesAreEncodedLikeStremio() throws {
    let a = sourceAddon("https://one.example/cfg-a/manifest.json", "Quellen")
    let url = try AddonClient().resourceURL(a, "catalog", type: "movie", id: "top",
                                             extra: ["genre": "Sci-Fi & Fantasy", "search": "a=b+c,d/e"])
    #expect(url.absoluteString == "https://one.example/cfg-a/catalog/movie/top/genre=Sci-Fi%20%26%20Fantasy&search=a%3Db%2Bc%2Cd%2Fe.json")
    let plain = try AddonClient().resourceURL(a, "catalog", type: "movie", id: "top", extra: ["skip": "100"])
    #expect(plain.absoluteString.hasSuffix("/catalog/movie/top/skip=100.json"))
}

@Test func addonStatusCountsOnlyPlayableEntries() {
    let a = sourceAddon("https://one.example/manifest.json", "P2P")
    var p = AddonSearchProgress(addons: [(index: 0, addon: a)])
    let hashOnly = [StreamItem(name: "P2P 1080p", infoHash: "0123456789abcdef0123456789abcdef01234567"),
                    StreamItem(name: "P2P 720p", infoHash: "89abcdef0123456789abcdef0123456789abcdef")]
    p.finish(index: 0, addon: a, outcome: .streams(hashOnly), milliseconds: 120)
    #expect(p.statuses[0].state == .ok(count: 0))
    #expect(p.statuses[0].unplayable == 2)
    #expect(p.logText == "P2P=0 (+2 nicht abspielbar) (120 ms)")
}
