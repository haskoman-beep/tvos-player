import Foundation
import Testing
@testable import PlayerCore

// Nuvio account sync, T2. All tokens and ids here are invented.

func nuvioTestSession(expiresAt: Date? = Date(timeIntervalSince1970: 1_800_000_000)) -> NuvioSession {
    NuvioSession(accessToken: "AT1-nuvio-access", refreshToken: "RT1-nuvio-refresh", expiresAt: expiresAt,
                 userID: "00000000-0000-4000-8000-000000000001")
}

@Test func nuvioSessionRoundTripsThroughStore() throws {
    let store = MemorySecretStore()
    let sessions = NuvioSessionStore(store: store)
    #expect(sessions.load() == nil)
    let s = nuvioTestSession()
    try sessions.save(s)
    #expect(sessions.load() == s)
    #expect(store.get(NuvioSessionStore.secretName, profile: NuvioSessionStore.deviceScope) != nil)
    // Without an expiry date it round-trips as well.
    let open = nuvioTestSession(expiresAt: nil)
    try sessions.save(open)
    #expect(sessions.load() == open)
    try sessions.wipe()
    #expect(sessions.load() == nil)
    #expect(store.count(profile: NuvioSessionStore.deviceScope) == 0)
}

@Test func nuvioSessionDamagedEntryLoadsAsNil() throws {
    let store = MemorySecretStore()
    let sessions = NuvioSessionStore(store: store)
    try store.set("{kaputt", name: NuvioSessionStore.secretName, profile: NuvioSessionStore.deviceScope)
    #expect(sessions.load() == nil)
    try store.set(#"{"accessToken":"","refreshToken":"RT1","userID":"u"}"#, name: NuvioSessionStore.secretName,
                  profile: NuvioSessionStore.deviceScope)
    #expect(sessions.load() == nil)   // an unusable session is no session
    try store.set(#"{"accessToken":"AT1","refreshToken":"RT1","userID":"u","neu":1}"#, name: NuvioSessionStore.secretName,
                  profile: NuvioSessionStore.deviceScope)
    #expect(sessions.load() == NuvioSession(accessToken: "AT1", refreshToken: "RT1", expiresAt: nil, userID: "u"))
}

@Test func nuvioSessionWipeLeavesOtherEntriesOfTheScope() throws {
    let store = MemorySecretStore()
    try store.set("x", name: "other", profile: NuvioSessionStore.deviceScope)
    let sessions = NuvioSessionStore(store: store)
    try sessions.save(nuvioTestSession())
    try sessions.wipe()
    #expect(store.get("other", profile: NuvioSessionStore.deviceScope) == "x")
}

@Test func nuvioSessionRefreshWindow() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(!nuvioTestSession(expiresAt: now.addingTimeInterval(61)).needsRefresh(now: now))
    #expect(nuvioTestSession(expiresAt: now.addingTimeInterval(59)).needsRefresh(now: now))
    #expect(nuvioTestSession(expiresAt: now.addingTimeInterval(-5)).needsRefresh(now: now))
    #expect(!nuvioTestSession(expiresAt: nil).needsRefresh(now: now))
    #expect(NuvioSession.refreshLeeway == 60)
}

@Test func nuvioSessionDescriptionHidesSecrets() {
    let s = nuvioTestSession()
    var dumped = ""
    dump(s, to: &dumped)
    for text in [String(describing: s), String(reflecting: s), "\(s)", dumped, "\([s])", "\(Optional(s) as Any)"] {
        #expect(!text.contains("AT1"))
        #expect(!text.contains("RT1"))
        #expect(!text.contains("00000000-0000-4000-8000-000000000001"))
    }
}

@Test func nuvioDeviceScopeIsFixedAndNoProfile() {
    #expect(NuvioSessionStore.deviceScope == NuvioSessionStore.deviceScope)
    #expect(NuvioSessionStore.deviceScope.uuidString == "6E757669-6F00-4D00-8000-000000000001")
    #expect(!StoredProfiles.makeDefault().profiles.contains { $0.id == NuvioSessionStore.deviceScope })
    #expect(NuvioSessionStore.secretName == "nuvio.session")
}
