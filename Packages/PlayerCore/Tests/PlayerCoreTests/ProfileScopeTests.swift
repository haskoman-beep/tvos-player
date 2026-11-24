import Foundation
import Testing
@testable import PlayerCore

// Task 3.1: profile epoch. Simulated flow: a task starts in profile A, the user switches to B, the result of A
// arrives late. It is discarded, or (token renewal) written into A by ID, never into B.

private let a = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
private let b = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

@Test func scopeClockAdvanceDiscardsLateResultOfOldProfile() {
    var clock = ScopeClock(profile: a)
    let started = clock.current          // task starts in A and remembers its scope
    clock.advance(to: b)                 // the user picks B while the request runs
    #expect(clock.current.profile == b)
    #expect(!clock.isCurrent(started))   // A's late result is discarded
    #expect(clock.isCurrent(clock.current))
}

@Test func scopeClockBumpKeepsProfileButEndsEpoch() {
    var clock = ScopeClock(profile: a)
    let started = clock.current
    clock.bump()                         // language, addon set or backup changed in the same profile
    #expect(clock.current.profile == a)
    #expect(clock.current.epoch == started.epoch + 1)
    #expect(!clock.isCurrent(started))
}

@Test func scopeClockBackToSameProfileStillEndsOldEpoch() {
    var clock = ScopeClock(profile: a)
    let started = clock.current
    clock.advance(to: b)
    clock.advance(to: a)                 // A → B → A: the epoch decides, not the profile ID
    #expect(clock.current.profile == a)
    #expect(!clock.isCurrent(started))
    #expect(Set([started, clock.current]).count == 2)
}

@Test func scopedCacheDiscardsStoreFromOldScopeAndForgetsOnRead() {
    var clock = ScopeClock(profile: a)
    var cache = ScopedCache<String, String>(limit: 10)
    let inA = clock.current
    let r1 = cache.store("A-Text", for: "tt1", from: inA, current: clock.current)
    #expect(r1)
    let r2 = cache.value(for: "tt1", in: clock.current)
    #expect(r2 == "A-Text")
    let late = clock.current             // a second request starts in A …
    clock.advance(to: b)
    let lateStored = cache.store("A-spät", for: "tt2", from: late, current: clock.current)
    #expect(!lateStored)                 // … and is discarded
    let inB = cache.value(for: "tt1", in: clock.current)
    #expect(inB == nil)                  // B never sees A's entries
    #expect(cache.count == 0)
}

@Test func scopedCacheDropsOldestOverLimit() {
    let clock = ScopeClock(profile: a)
    var cache = ScopedCache<String, Int>(limit: 2)
    for (i, k) in ["x", "y", "z"].enumerated() { cache.store(i, for: k, from: clock.current, current: clock.current) }
    #expect(cache.count == 2)
    let r3 = cache.value(for: "x", in: clock.current)
    #expect(r3 == nil)
    let r4 = cache.value(for: "z", in: clock.current)
    #expect(r4 == 2)
    cache.store(9, for: "y", from: clock.current, current: clock.current)   // replacing does not evict
    #expect(cache.count == 2)
    let r5 = cache.value(for: "z", in: clock.current)
    #expect(r5 == 2)
}

@Test func textCacheKeySeparatesLanguages() {
    var clock = ScopeClock(profile: a)
    var cache = ScopedCache<TextCacheKey, String>(limit: 10)
    cache.store("Deutsch", for: TextCacheKey(imdb: "tt1", language: "de-DE"), from: clock.current, current: clock.current)
    let r6 = cache.value(for: TextCacheKey(imdb: "tt1", language: "en-US"), in: clock.current)
    #expect(r6 == nil)
    #expect(TextCacheKey(imdb: "tt1", language: "de-DE", season: 1) != TextCacheKey(imdb: "tt1", language: "de-DE"))
    clock.bump()   // language switch
    let r7 = cache.value(for: TextCacheKey(imdb: "tt1", language: "de-DE"), in: clock.current)
    #expect(r7 == nil)
}

private func profiles(tokenA: SyncToken?, tokenB: SyncToken?) -> [Profile] {
    var pa = Profile(id: a, name: "A"), pb = Profile(id: b, name: "B")
    pa.syncTokens["trakt"] = tokenA
    pb.syncTokens["trakt"] = tokenB
    return [pa, pb]
}

@Test func tokenRenewalLandsInStartingProfileAfterSwitch() {
    let oldA = SyncToken(accessToken: "a1", refreshToken: "ra1")
    let ownB = SyncToken(accessToken: "b1", refreshToken: "rb1")
    var clock = ScopeClock(profile: a)
    let scope = clock.current            // renewal starts for A
    clock.advance(to: b)                 // user picks B while /oauth/token runs
    var list = profiles(tokenA: oldA, tokenB: ownB)
    let newA = SyncToken(accessToken: "a2", refreshToken: "ra2")
    let r8 = SyncTokenWriteBack.apply(newA, replacing: oldA, service: "trakt", profile: scope.profile, in: &list)
    #expect(r8)
    #expect(list[0].syncTokens["trakt"] == newA)   // rotated token kept in A although B is active
    #expect(list[1].syncTokens["trakt"] == ownB)   // B keeps its own login
}

@Test func tokenRenewalNotWrittenAfterLogoutOrReplacement() {
    let oldA = SyncToken(accessToken: "a1", refreshToken: "ra1")
    let newA = SyncToken(accessToken: "a2", refreshToken: "ra2")
    var loggedOut = profiles(tokenA: nil, tokenB: nil)   // „Abmelden“ while the renewal ran
    let r9 = SyncTokenWriteBack.apply(newA, replacing: oldA, service: "trakt", profile: a, in: &loggedOut)
    #expect(!r9)
    #expect(loggedOut[0].syncTokens["trakt"] == nil)
    let fresh = SyncToken(accessToken: "a9")
    var relogged = profiles(tokenA: fresh, tokenB: nil)  // new login meanwhile
    let r10 = SyncTokenWriteBack.apply(newA, replacing: oldA, service: "trakt", profile: a, in: &relogged)
    #expect(!r10)
    #expect(relogged[0].syncTokens["trakt"] == fresh)
    var gone = [Profile(id: b, name: "B")]               // profile deleted or not in a restored backup
    let r11 = SyncTokenWriteBack.apply(newA, replacing: oldA, service: "trakt", profile: a, in: &gone)
    #expect(!r11)
}

@Test func tokenRenewalSlotsArePerProfile() {
    // The running renewal is bound to its profile: B starts its own and never receives A's token.
    var slots = TaskSlots<SyncToken?>()
    let taskA = Task<SyncToken?, Never> { SyncToken(accessToken: "a2") }
    _ = slots.begin(a.uuidString, taskA)
    #expect(slots[a.uuidString] != nil)
    #expect(slots[b.uuidString] == nil)
}
