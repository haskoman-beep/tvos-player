import Foundation
import Testing
@testable import PlayerCore

// Task 4.2: going back from Build 4 to Build 3 must keep everything. `Fixtures/build4-profiles-look.json` is
// `build249-profiles.json` (same keys as Build 3) plus a `look` per profile, one of them from a future build.
// The same test body was run green once on the Build 3 code (commit 8159e35, before `look` existed): the Build 3
// model ignores the key. Here it runs against the current model and checks the other fields stay untouched.

private func compatFixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

/// Encoded profiles without the `look` key, keys sorted, for a byte comparison.
private func withoutLook(_ stored: StoredProfiles) throws -> [Data] {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    return try stored.profiles.map { p in
        var obj = try #require(try JSONSerialization.jsonObject(with: enc.encode(p)) as? [String: Any])
        obj["look"] = nil
        return try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    }
}

@Test func lookKeyDoesNotDisturbOtherProfileFields() throws {
    let (withLook, report) = try ProfileStore.decodeReporting(try compatFixture("build4-profiles-look.json"))
    let plain = try ProfileStore.decode(try compatFixture("build249-profiles.json"))
    #expect(withLook.profiles.count == 2)
    #expect(try withoutLook(withLook) == withoutLook(plain))
    // Nothing outside `look` was left out (the future look values may be noted under `look`).
    #expect(report.ignored.allSatisfy { $0.contains(".look") })
}
