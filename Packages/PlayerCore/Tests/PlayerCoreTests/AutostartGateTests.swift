import Testing
@testable import PlayerCore

// MARK: Task 3.4 (F-B-1, F-B-5): autostart of a source list only once per pushed route

@Test func autostartGateStartsAFreshlyPushedList() {
    #expect(AutostartGate.shouldStart(requestID: "tt1:1:1", alreadyStarted: [], isRebuild: false))
}

@Test func autostartGateBlocksTheRerunOfTheSameList() {
    // Load task runs again after the player closed, or for the next episode: never a second autostart.
    #expect(!AutostartGate.shouldStart(requestID: "tt1:1:1", alreadyStarted: [], isRebuild: true))
    #expect(!AutostartGate.shouldStart(requestID: "tt1:1:1", alreadyStarted: ["tt1:1:1"], isRebuild: true))
}

@Test func autostartGateBlocksARebuiltListWhoseAutostartWasUsed() {
    // F-B-5: the TabView was rebuilt, the list view is new (fresh state) but its route was already started.
    #expect(!AutostartGate.shouldStart(requestID: "tt1:1:1", alreadyStarted: ["tt1:1:1"], isRebuild: false))
}

@Test func autostartGateIgnoresOtherUsedAutostarts() {
    #expect(AutostartGate.shouldStart(requestID: "tt2", alreadyStarted: ["tt1:1:1", "tt3"], isRebuild: false))
}
