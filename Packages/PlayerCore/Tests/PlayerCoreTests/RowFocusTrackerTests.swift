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

@Test func trackerResetForgetsWithoutEvents() {
    var t = RowFocusTracker<String>()
    _ = t.card("a", focused: true)
    t.reset()
    #expect(t.card == nil)
    #expect(!t.inside)
    // After the reset the next focus is an enter again.
    #expect(t.card("a", focused: true) == [.route(old: nil, new: "a"), .inside(true)])
}
