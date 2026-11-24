import Testing
@testable import PlayerCore

/// Task 4.1a (F-A-1): a navigation that waited for an answer only happens while the visible page is unchanged.
@Suite struct NavigationGuardTests {
    @Test func samePageMayPush() {
        let s = NavigationStamp(tab: .home, depth: 0)
        #expect(NavigationGuard.mayPush(startedAt: s, now: NavigationStamp(tab: .home, depth: 0)))
    }

    @Test func pushedPageOrOtherTabDiscardsTheLateJump() {
        let s = NavigationStamp(tab: .home, depth: 0)
        #expect(!NavigationGuard.mayPush(startedAt: s, now: NavigationStamp(tab: .home, depth: 1)))
        #expect(!NavigationGuard.mayPush(startedAt: s, now: NavigationStamp(tab: .library, depth: 0)))
        // Back and forth while waiting: the visit counter tells the pages apart.
        #expect(!NavigationGuard.mayPush(startedAt: s, now: NavigationStamp(tab: .home, depth: 0, visit: 1)))
    }
}
