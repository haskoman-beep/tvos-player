import Testing
@testable import PlayerCore

// MARK: Row focus tracker (Build 6 redraw: cards report their own focus, the row body no longer reads it)

@Test func trackerOldFalseFirstKeepsTheNilGap() {
    var t = RowFocusTracker<String>()
    #expect(t.card("a", focused: true) == [.route(old: nil, new: "a"), .inside(true)])
    #expect(t.card("a", focused: false) == [.route(old: "a", new: nil), .inside(false)])
    #expect(t.card("b", focused: true) == [.route(old: nil, new: "b"), .inside(true)])
    #expect(t.card == "b")
}

@Test func trackerNewTrueFirstSynthesizesTheGapAndIgnoresTheLateFalse() {
    var t = RowFocusTracker<String>()
    _ = t.card("a", focused: true)
    // The new card reports first: the old route still passes through nil (cancelRest relies on it), no leave.
    #expect(t.card("b", focused: true) == [.route(old: "a", new: nil), .route(old: nil, new: "b")])
    // The old card's late "false" must not clear the new route.
    #expect(t.card("a", focused: false) == [])
    #expect(t.card == "b")
    #expect(t.inside)
}

@Test func trackerRepeatedReportsAreSilent() {
    var t = RowFocusTracker<String>()
    _ = t.card("a", focused: true)
    #expect(t.card("a", focused: true) == [])
    #expect(t.card("x", focused: false) == [])   // a card built unfocused (initial report)
}

@Test func trackerPlaceholderToCardHandOverStaysInside() {
    var t = RowFocusTracker<String>()
    #expect(t.placeholder(2, focused: true) == [.inside(true)])
    #expect(t.card("c", focused: true) == [.route(old: nil, new: "c")])
    #expect(t.placeholder(2, focused: false) == [])
    #expect(t.placeholder == nil)
    #expect(t.inside)
    // A late "false" of another placeholder does not clear the current one.
    _ = t.placeholder(0, focused: true)
    #expect(t.placeholder(1, focused: false) == [])
    #expect(t.placeholder == 0)
}

@Test func trackerPlaceholderMovesBetweenSlots() {
    var t = RowFocusTracker<String>()
    _ = t.placeholder(0, focused: true)
    #expect(t.placeholder(1, focused: true) == [])
    #expect(t.placeholder(0, focused: false) == [])
    #expect(t.placeholder(1, focused: false) == [.inside(false)])
}

@Test func trackerReappearClearsByTheProbesOwnFalseAndReseeds() {
    // Re-review L3: no reset on disappear; the probe reports false when it leaves and its focus again when it appears.
    var t = RowFocusTracker<String>()
    _ = t.card("a", focused: true)
    #expect(t.card("a", focused: false) == [.route(old: "a", new: nil), .inside(false)])
    #expect(t.card("a", focused: true) == [.route(old: nil, new: "a"), .inside(true)])
    #expect(t.card == "a")
}

@Test func trackerStatusTileHasItsOwnSlot() {
    // Re-review L4: placeholders → status tile (focus state value 0 for both). Either report order stays inside.
    let status = RowFocusTracker<String>.statusSlot
    var t = RowFocusTracker<String>()
    _ = t.placeholder(0, focused: true)
    #expect(t.placeholder(status, focused: true) == [])
    #expect(t.placeholder(0, focused: false) == [])
    #expect(t.inside)
    #expect(t.focusStateSlot == 0)   // the status tile's `.focused` value
    var u = RowFocusTracker<String>()
    _ = u.placeholder(0, focused: true)
    #expect(u.placeholder(0, focused: false) == [.inside(false)])
    #expect(u.placeholder(status, focused: true) == [.inside(true)])
    #expect(u.focusStateSlot == 0)
}

@Test func trackerFocusStateSlotOfPlaceholders() {
    var t = RowFocusTracker<String>()
    #expect(t.focusStateSlot == nil)
    _ = t.placeholder(3, focused: true)
    #expect(t.focusStateSlot == 3)
}

// MARK: Third review M1: placeholder latch for the hand-over

@Test func trackerFocusedPlaceholderLeavingTheScreenStaysPending() {
    var t = RowFocusTracker<String>()
    _ = t.placeholder(2, focused: true)
    // The loaded row removes the placeholders: not inside any more, but the slot waits for the hand-over.
    #expect(t.placeholderGone(2) == [.inside(false)])
    #expect(!t.inside)
    #expect(t.pendingSlot == 2)
    #expect(t.takePending() == 2)
    #expect(t.pendingSlot == nil)
}

@Test func trackerUnfocusedPlaceholderLeavingIsNoLatch() {
    var t = RowFocusTracker<String>()
    _ = t.placeholder(1, focused: true)
    #expect(t.placeholderGone(0) == [])
    #expect(t.pendingSlot == nil)
    // Focus left by the user (onChange false, not a disappear): nothing pending, the hand-over is skipped.
    _ = t.placeholder(1, focused: false)
    #expect(t.pendingSlot == nil)
}

@Test func trackerAnyTrueReportClearsThePending() {
    var t = RowFocusTracker<String>()
    _ = t.placeholder(0, focused: true)
    _ = t.placeholderGone(0)
    #expect(t.card("c", focused: true) == [.route(old: nil, new: "c"), .inside(true)])
    #expect(t.pendingSlot == nil)
    t.expectPlaceholder(0)
    #expect(t.pendingSlot == 0)
    _ = t.placeholder(0, focused: true)
    #expect(t.pendingSlot == nil)
}

@Test func trackerProgrammaticWriteIsPendingUntilItLands() {
    // Retry tile: `focusPlaceholder(0)`; a fast failure must still hand over to the status tile.
    var t = RowFocusTracker<String>()
    _ = t.placeholder(RowFocusTracker<String>.statusSlot, focused: true)
    t.expectPlaceholder(0)
    _ = t.placeholderGone(RowFocusTracker<String>.statusSlot)
    #expect(t.pendingSlot == 0)   // status tile slot maps to focus state value 0
    t.clearPending()
    #expect(t.pendingSlot == nil)
}
