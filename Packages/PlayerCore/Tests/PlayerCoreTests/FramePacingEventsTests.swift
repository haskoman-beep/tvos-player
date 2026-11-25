import Foundation
import Testing
@testable import PlayerCore

// Build 4 follow-up 2 (P3): the `ruckler` line names the render-side events of its window (backdrop swaps, card
// expansions, poster pictures, badge passes, stored sources, prefetch starts) and which of them lay near the missed
// frames, so one device test shows what the stutter coincides with.

private let frame = 1.0 / 64   // binary-exact nominal frame (15.625 ms)

/// Smooth frames from `start` (exclusive) for `count` frames; returns the last timestamp.
@discardableResult
private func smooth(_ p: inout FramePacing, from start: TimeInterval, count: Int) -> TimeInterval {
    var t = start
    for _ in 0..<count {
        t += frame
        _ = p.frame(at: t, nominal: frame)
    }
    return t
}

@Test func framePacingCountsEventsOnlyWhileMeasuring() {
    var p = FramePacing(window: 5, keepAlive: 2)
    p.event(.backdrop, at: 0.5)                           // not measuring: not counted
    _ = p.activity(at: 1)
    _ = p.frame(at: 1, nominal: frame)
    p.event(.poster, at: 1.1)
    p.event(.poster, at: 1.2)
    p.event(.badges, at: 1.3)
    smooth(&p, from: 1, count: 64)
    let r = p.stop()
    #expect(r?.events.count(.poster) == 2)
    #expect(r?.events.count(.badges) == 1)
    #expect(r?.events.count(.backdrop) == 0)
    #expect(r?.events.missedAlone == 0)
    // The event also names itself as the window's last note.
    #expect(r?.note == "Plaketten gesetzt")
}

@Test func framePacingAttributesMissedFramesToRecentEvents() {
    var p = FramePacing(window: 5, keepAlive: 2)
    _ = p.activity(at: 0)
    _ = p.frame(at: 0, nominal: frame)
    var t = smooth(&p, from: 0, count: 10)
    // Backdrop crossfade starts; a stall 0.5 s later still lies within its span (0.6 s crossfade).
    p.event(.backdrop, at: t)
    t = smooth(&p, from: t, count: 32)                    // 0.5 s
    t += 0.060
    _ = p.frame(at: t, nominal: frame)                    // missed: near the backdrop
    // A poster arrives during the next stall: near the poster (and still near the backdrop).
    p.event(.poster, at: t + 0.010)
    t += 0.050
    _ = p.frame(at: t, nominal: frame)
    // Two seconds later nothing happened: a stall without any event.
    t = smooth(&p, from: t, count: 128)
    t += 0.050
    _ = p.frame(at: t, nominal: frame)
    let r = p.stop()
    #expect(r?.missed == 3)
    #expect(r?.events.near(.backdrop) == 2)
    #expect(r?.events.near(.poster) == 1)
    #expect(r?.events.near(.badges) == 0)
    #expect(r?.events.missedAlone == 1)
}

@Test func framePacingEventSpanEndsAfterItsEffect() {
    var p = FramePacing(window: 5, keepAlive: 2)
    _ = p.activity(at: 0)
    _ = p.frame(at: 0, nominal: frame)
    p.event(.badges, at: 0)
    var t = smooth(&p, from: 0, count: 32)                // 0.5 s: past the 0.3 s span of a badge pass
    t += 0.050
    _ = p.frame(at: t, nominal: frame)
    let r = p.stop()
    #expect(r?.missed == 1)
    #expect(r?.events.near(.badges) == 0)
    #expect(r?.events.missedAlone == 1)
    #expect(FramePacing.Event.backdrop.span > FramePacing.Event.poster.span)   // crossfade 0.6 s vs fade 0.2 s
}

@Test func framePacingEventNearWindowEndStillCountsInTheNextWindow() {
    var p = FramePacing(window: 1, keepAlive: 2)
    _ = p.activity(at: 0)
    _ = p.frame(at: 0, nominal: frame)
    var t = smooth(&p, from: 0, count: 60)
    p.event(.sources, at: t)                              // counted in the first window
    t = smooth(&p, from: t, count: 5)                     // the window closes after 1 s
    t += 0.050
    let tick = p.frame(at: t, nominal: frame)             // missed in the second window, 0.1 s after the event
    #expect(tick.report == nil)
    let r = p.stop()
    #expect(r?.events.count(.sources) == 0)               // counts are per window
    #expect(r?.events.near(.sources) == 1)                // nearness is not
}

@Test func framePacingEventCountsResetPerWindow() {
    var p = FramePacing(window: 1, keepAlive: 2)
    _ = p.activity(at: 0)
    _ = p.frame(at: 0, nominal: frame)
    p.event(.expand, at: 0.1)
    var reports: [FramePacing.Report] = []
    var t = 0.0
    for _ in 0..<70 {
        t += frame
        if let r = p.frame(at: t, nominal: frame).report { reports.append(r) }
    }
    #expect(reports.count == 1)
    #expect(reports.first?.events.count(.expand) == 1)
    let last = p.stop()
    #expect(last?.events.count(.expand) == 0)
    #expect(last?.note == nil)
}

@Test func framePacingTextNamesEventsAndMisses() {
    var e = FramePacing.EventTally()
    e.counted(.backdrop); e.counted(.poster); e.counted(.poster); e.counted(.sources)
    e.missed(near: [.backdrop, .poster])
    e.missed(near: [.backdrop])
    e.missed(near: [])
    let r = FramePacing.Report(frames: 296, missed: 3, dropped: 5, longestMs: 48, hz: 60, tenths: 50,
                               note: "Quellen abgelegt", events: e)
    #expect(FramePacing.text(r) == "Startseite 5,0 s: 296 Bilder (60 Hz) · 3 verpasst · ≈5 Bilder fehlen · längstes 48 ms"
            + " · Ereignisse: Hintergrund 1, Poster 2, Quellen 1 · verpasst bei: Hintergrund 2, Poster 1, ohne 1"
            + " · zuletzt: Quellen abgelegt")
    // No events, no misses: the line stays as before.
    let quiet = FramePacing.Report(frames: 120, missed: 0, dropped: 0, longestMs: 17, hz: 60, tenths: 21, note: nil)
    #expect(FramePacing.text(quiet) == "Startseite 2,1 s: 120 Bilder (60 Hz) · 0 verpasst · ≈0 Bilder fehlen · längstes 17 ms")
    // Misses without any event.
    var alone = FramePacing.EventTally()
    alone.missed(near: [])
    alone.missed(near: [])
    let r2 = FramePacing.Report(frames: 200, missed: 2, dropped: 2, longestMs: 40, hz: 60, tenths: 34, note: nil, events: alone)
    #expect(FramePacing.text(r2) == "Startseite 3,4 s: 200 Bilder (60 Hz) · 2 verpasst · ≈2 Bilder fehlen · längstes 40 ms"
            + " · verpasst bei: ohne 2")
}

@Test func framePacingEventLabelsAreFixed() {
    #expect(FramePacing.Event.allCases.map(\.label)
            == ["Hintergrund", "Aufklappen", "Poster", "Plaketten", "Quellen", "Vorladen"])
    #expect(FramePacing.Event.sources.note == "Quellen abgelegt")
    #expect(FramePacing.Event.poster.note == "Poster angekommen")
}
