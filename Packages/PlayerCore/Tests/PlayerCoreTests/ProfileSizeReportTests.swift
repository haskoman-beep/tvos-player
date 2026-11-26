import Foundation
import Testing
@testable import PlayerCore

// Build 5 device test 1: profiles.json shrank 24.0 → 19.4 KB in the session where the user changed card shape,
// ratings style, detail layout and the poster quality badges. These changes must leave every other part of the
// profile byte-identical (no data loss); the report names the parts that shrank in the next device log.

private func sizeFixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Test func sessionTwoSettingsChangesKeepEveryOtherSection() throws {
    for name in ["build4-profiles-look.json", "build249-profiles.json"] {
        let stored = try ProfileStore.decode(try sizeFixture(name))
        for original in stored.profiles {
            var p = original
            let before = ProfileSizeReport.sections(p)
            p.setLook("cardShape", to: "poster")
            p.setLook("ratingStyle", to: "symbole")
            p.appearance.titles.posterBadges = .topTrailing
            p.appearance.titles.posterBadges = .bottom
            p.appearance.titles.posterBadges = .off
            p.setLook("layout", to: "links")
            // Saved and loaded again, as the next app start does.
            let back = try JSONDecoder().decode(Profile.self, from: try JSONEncoder().encode(p))
            let after = ProfileSizeReport.sections(back)
            for key in before.keys where !["look", "appearance", "player", "detailExtras"].contains(key) {
                #expect(before[key] == after[key], "\(name) \(original.name): \(key) changed")
            }
            #expect(back.addons == original.addons)
            #expect(back.collections == original.collections)
            #expect(back.home == original.home)
            #expect(ProfileSizeReport.shrinkLine(name: p.name, before: before, after: after) == nil)
        }
    }
}

@Test func shrinkLineNamesOnlyKeysThatLostBytes() {
    let before = ["addons": 12_000, "collections": 3_000, "look": 100, "home": 2_000]
    let after = ["addons": 7_400, "collections": 3_000, "look": 900, "home": 1_900]
    let line = ProfileSizeReport.shrinkLine(name: "Ich", before: before, after: after)
    #expect(line == "Profil Ich kleiner geworden (−3,8 KB): addons 11,7 KB → 7,2 KB")
    #expect(ProfileSizeReport.shrinkLine(name: "Ich", before: after, after: after) == nil)
    let gone = ProfileSizeReport.shrinkLine(name: "B", before: ["collections": 2048], after: [:])
    #expect(gone == "Profil B kleiner geworden (−2,0 KB): collections 2,0 KB → fehlt")
}

@Test func sectionsSumToRoughlyTheProfileAndSummaryIsLargestFirst() throws {
    let stored = try ProfileStore.decode(try sizeFixture("build249-profiles.json"))
    let p = try #require(stored.profiles.first)
    let s = ProfileSizeReport.sections(p)
    let whole = try JSONEncoder().encode(p).count
    #expect(s.values.reduce(0, +) <= whole)
    #expect(s.values.reduce(0, +) > whole / 2)
    let first = ProfileSizeReport.summary(s, top: 1)
    let biggest = try #require(s.max { $0.value < $1.value })
    #expect(first.hasPrefix(biggest.key + " "))
}
