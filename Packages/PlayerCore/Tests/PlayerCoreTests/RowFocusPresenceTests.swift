import Foundation
import Testing
@testable import PlayerCore

// MARK: Row focus presence (Build 4 follow-up 2, device test 1: heading jitter while moving right in a row)

@Test func rowFocusEnterIsReportedOnceAndAtOnce() {
    var p = RowFocusPresence()
    #expect(p.raw(true, now: 0) == .enter)
    #expect(p.reported)
    // A second "inside" (e.g. the row appears again with the focus in it) reports nothing new.
    #expect(p.raw(true, now: 0.1) == .none)
}

@Test func rowFocusGapBetweenTwoCardsIsBridged() {
    // Device log 25.11. 21:52:11–15Z: one leave + enter per step, ~180 ms apart. The gap itself lasts a frame or two.
    var p = RowFocusPresence()
    _ = p.raw(true, now: 0)
    var steps: [RowFocusPresence.Step] = []
    for i in 0..<5 {
        let t = 0.18 * Double(i + 1)
        steps.append(p.raw(false, now: t))
        steps.append(p.raw(true, now: t + 0.017))
    }
    #expect(steps == [.scheduleLeave(serial: 1), .cancelLeave, .scheduleLeave(serial: 2), .cancelLeave,
                      .scheduleLeave(serial: 3), .cancelLeave, .scheduleLeave(serial: 4), .cancelLeave,
                      .scheduleLeave(serial: 5), .cancelLeave])
    // The delays of the bridged gaps run out later: no leave.
    for s in 1...5 { #expect(p.leaveDue(serial: s, inside: true) == nil) }
    #expect(p.reported)
    // The real leave: the delay of the last gap runs out with the focus outside.
    guard case .scheduleLeave(let s) = p.raw(false, now: 2) else { Issue.record("no leave scheduled"); return }
    let leave = p.leaveDue(serial: s, inside: false)
    #expect(leave == RowFocusPresence.Leave(bridged: 5, longestGapMs: 17))
    #expect(!p.reported)
    #expect(leave?.line(title: "In Theaters") ==
            "Reihe In Theaters verlassen · 5 Fokuslücken zwischen Karten überbrückt (längste 17 ms)")
}

@Test func rowFocusStaleDelayDoesNotEndANewerGap() {
    // false → true → false: the first delay runs out during the second gap; only the second delay may end the visit.
    var p = RowFocusPresence()
    _ = p.raw(true, now: 0)
    #expect(p.raw(false, now: 1) == .scheduleLeave(serial: 1))
    #expect(p.raw(true, now: 1.02) == .cancelLeave)
    #expect(p.raw(false, now: 1.08) == .scheduleLeave(serial: 2))
    #expect(p.leaveDue(serial: 1, inside: false) == nil)
    #expect(p.reported)
    #expect(p.leaveDue(serial: 2, inside: false) == RowFocusPresence.Leave(bridged: 1, longestGapMs: 20))
}

@Test func rowFocusLeaveWithoutGapsHasNoLine() {
    var p = RowFocusPresence()
    _ = p.raw(true, now: 0)
    #expect(p.raw(false, now: 1) == .scheduleLeave(serial: 1))
    // A second "outside" while the delay runs changes nothing.
    #expect(p.raw(false, now: 1.01) == .none)
    let leave = p.leaveDue(serial: 1, inside: false)
    #expect(leave == RowFocusPresence.Leave(bridged: 0, longestGapMs: 0))
    #expect(leave?.line(title: "Genres") == nil)
    // Next visit starts fresh.
    #expect(p.raw(true, now: 3) == .enter)
}

@Test func rowFocusOutsideBeforeAnyEnterReportsNothing() {
    var p = RowFocusPresence()
    #expect(p.raw(false, now: 0) == .none)
    #expect(p.disappear() == nil)
}

@Test func rowFocusDisappearEndsTheVisitAtOnce() {
    var p = RowFocusPresence()
    _ = p.raw(true, now: 0)
    _ = p.raw(false, now: 0.5)
    _ = p.raw(true, now: 0.51)
    guard case .scheduleLeave(let s) = p.raw(false, now: 1) else { Issue.record("no leave scheduled"); return }
    #expect(p.disappear() == RowFocusPresence.Leave(bridged: 1, longestGapMs: 10))
    // The pending delay of the visit that ended is void.
    #expect(p.leaveDue(serial: s, inside: false) == nil)
    #expect(!p.reported)
}
