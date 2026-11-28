import Foundation
import Testing
@testable import PlayerCore

// Build 4 follow-up S1: frame meter on the home page (30–100 ms stutters stay under the 250 ms hitch threshold).

private let hz60 = 1.0 / 64   // binary-exact nominal frame (15.625 ms), shown as 64 Hz

/// Feeds `count` frames of `step` seconds starting after `start`; returns the reports and the last timestamp.
private func feed(_ p: inout FramePacing, from start: TimeInterval, count: Int, step: TimeInterval,
                  nominal: TimeInterval = hz60) -> (reports: [FramePacing.Report], stops: Int, end: TimeInterval) {
    var reports: [FramePacing.Report] = [], stops = 0, t = start
    for _ in 0..<count {
        t += step
        let tick = p.frame(at: t, nominal: nominal)
        if let r = tick.report { reports.append(r) }
        if !tick.keepRunning { stops += 1 }
    }
    return (reports, stops, t)
}

@Test func framePacingStartsOnlyOnActivity() {
    var p = FramePacing()
    #expect(!p.isRunning)
    let idle = p.frame(at: 1, nominal: hz60)
    #expect(idle.report == nil && !idle.keepRunning)   // a stray frame while stopped does nothing
    let started = p.activity(at: 10)
    #expect(started)                                    // first move: caller starts the display link
    #expect(p.isRunning)
    let again = p.activity(at: 10.5)
    #expect(!again)                                     // already running: nothing to start
}

@Test func framePacingReportsOneWindowAndStopsWhenIdle() {
    var p = FramePacing(window: 5, keepAlive: 2)
    _ = p.activity(at: 0)
    _ = p.frame(at: 0, nominal: hz60)                   // baseline, not a frame
    // 100 smooth frames, two long ones (40 ms and 80 ms), then smooth frames until the window closes after 5 s.
    var r = feed(&p, from: 0, count: 100, step: hz60)
    _ = p.frame(at: r.end + 0.040, nominal: hz60)
    _ = p.frame(at: r.end + 0.120, nominal: hz60)
    r = feed(&p, from: r.end + 0.120, count: 212, step: hz60)   // up to 4.995 s
    #expect(r.reports.isEmpty)
    r = feed(&p, from: r.end, count: 1, step: hz60)              // 5.011 s: the window closes
    var alone = FramePacing.EventTally()                         // P3: both misses lie near no event
    alone.missed(near: [])
    alone.missed(near: [])
    #expect(r.reports == [FramePacing.Report(frames: 315, missed: 2, dropped: 6, longestMs: 80, hz: 64, tenths: 50, note: nil,
                                             events: alone)])
    #expect(r.stops == 1)                               // last activity 5 s ago (> keepAlive): the link stops
    let stray = p.frame(at: r.end + hz60, nominal: hz60)
    #expect(stray.report == nil && !stray.keepRunning)
    #expect(!p.isRunning)
}

@Test func framePacingContinuesWhileFocusMoves() {
    var p = FramePacing(window: 5, keepAlive: 2)
    _ = p.activity(at: 0)
    _ = p.frame(at: 0, nominal: hz60)
    var r = feed(&p, from: 0, count: 256, step: hz60)   // 4 s
    _ = p.activity(at: r.end)                           // focus moved at 4 s
    r = feed(&p, from: r.end, count: 64, step: hz60)    // window closes at 5 s
    #expect(r.reports.count == 1 && r.stops == 0)       // moved 1 s before the end: one more window
    #expect(p.isRunning)
    r = feed(&p, from: r.end, count: 320, step: hz60)   // second window without moves
    #expect(r.reports.count == 1 && r.stops == 1)       // its line still comes (posters arriving after the move)
    #expect(r.reports.first?.frames == 320 && r.reports.first?.missed == 0)
}

@Test func framePacingMissedNeedsMoreThanOneAndAHalfFrames() {
    var p = FramePacing(window: 5, keepAlive: 2)
    _ = p.activity(at: 0)
    _ = p.frame(at: 0, nominal: hz60)
    _ = p.frame(at: hz60 * 1.5, nominal: hz60)          // exactly 1.5×: not missed
    _ = p.frame(at: hz60 * 1.5 + hz60 * 1.75, nominal: hz60)   // 1.75×: missed
    let last = p.stop()
    #expect(last?.frames == 2 && last?.missed == 1 && last?.dropped == 1 && last?.longestMs == 27)
}

@Test func framePacingPauseLongerThanASecondClosesTheWindow() {
    // Review M1: a pause (app in the background, a hang the hitch watchdog logs) is not a frame and does not stretch
    // the window: the window closes at its last counted frame.
    var p = FramePacing(window: 5, keepAlive: 2)
    _ = p.activity(at: 0)
    _ = p.frame(at: 0, nominal: hz60)
    _ = p.frame(at: hz60, nominal: hz60)
    let paused = p.frame(at: hz60 + 1.5, nominal: hz60)  // focus moved 1.5 s ago: measuring goes on
    #expect(paused == FramePacing.Tick(report: FramePacing.Report(frames: 1, missed: 0, dropped: 0, longestMs: 16, hz: 64, tenths: 0,
                                                                  note: nil), keepRunning: true))
    _ = p.frame(at: hz60 * 2 + 1.5, nominal: hz60)      // new window from the frame after the pause
    let last = p.stop()
    #expect(last == FramePacing.Report(frames: 1, missed: 0, dropped: 0, longestMs: 16, hz: 64, tenths: 0, note: nil))
}

@Test func framePacingLongPauseEndsMeasuringWithoutStretchedWindow() {
    var p = FramePacing(window: 5, keepAlive: 2)
    _ = p.activity(at: 0)
    _ = p.frame(at: 0, nominal: hz60)
    let r = feed(&p, from: 0, count: 64, step: hz60)    // 1 s
    let resumed = p.frame(at: r.end + 600, nominal: hz60)   // back after 10 min, no focus move since
    #expect(resumed.report == FramePacing.Report(frames: 64, missed: 0, dropped: 0, longestMs: 16, hz: 64, tenths: 10, note: nil))
    #expect(!resumed.keepRunning && !p.isRunning)
    let none = p.stop()
    #expect(none == nil)
    // A pause right after the baseline has nothing to report.
    _ = p.activity(at: 1000)
    _ = p.frame(at: 1000, nominal: hz60)
    let early = p.frame(at: 1001.5, nominal: hz60)
    #expect(early == FramePacing.Tick(report: nil, keepRunning: true))
}

@Test func framePacingStopFlushesPartialWindowAndKeepsLastNote() {
    var p = FramePacing(window: 5, keepAlive: 2)
    p.note("vorher")                                    // not running: dropped
    let none = p.stop()
    #expect(none == nil)                                // nothing measured: no line
    _ = p.activity(at: 0)
    _ = p.frame(at: 0, nominal: hz60)
    p.note("Poster angekommen")
    let r = feed(&p, from: 0, count: 128, step: hz60)   // 2 s
    #expect(r.reports.isEmpty)
    p.note("Quellen abgelegt")
    let last = p.stop()
    #expect(last == FramePacing.Report(frames: 128, missed: 0, dropped: 0, longestMs: 16, hz: 64, tenths: 20, note: "Quellen abgelegt"))
    #expect(!p.isRunning)
    let twice = p.stop()
    #expect(twice == nil)
    // A new start begins with fresh counters and no note.
    _ = p.activity(at: 100)
    _ = p.frame(at: 100, nominal: hz60)
    _ = p.frame(at: 100 + hz60, nominal: hz60)
    let fresh = p.stop()
    #expect(fresh == FramePacing.Report(frames: 1, missed: 0, dropped: 0, longestMs: 16, hz: 64, tenths: 0, note: nil))
}

@Test func framePacingNoteResetsPerWindow() {
    var p = FramePacing(window: 5, keepAlive: 2)
    _ = p.activity(at: 0)
    _ = p.frame(at: 0, nominal: hz60)
    p.note("Poster angekommen")
    var r = feed(&p, from: 0, count: 256, step: hz60)
    _ = p.activity(at: r.end)
    r = feed(&p, from: r.end, count: 64, step: hz60)
    #expect(r.reports.first?.note == "Poster angekommen")
    r = feed(&p, from: r.end, count: 320, step: hz60)
    #expect(r.reports.first?.note == nil)
}

@Test func framePacingFallsBackToSixtyHertzWithoutNominal() {
    var p = FramePacing(window: 5, keepAlive: 2)
    _ = p.activity(at: 0)
    _ = p.frame(at: 0, nominal: 0)
    _ = p.frame(at: 0.020, nominal: 0)                  // 20 ms against 16.7 ms: below 1.5×
    _ = p.frame(at: 0.050, nominal: -1)                 // 30 ms: missed
    let last = p.stop()
    #expect(last?.hz == 60 && last?.missed == 1 && last?.dropped == 1 && last?.longestMs == 30)
}

@Test func framePacingText() {
    let r = FramePacing.Report(frames: 296, missed: 3, dropped: 7, longestMs: 48, hz: 60, tenths: 50, note: "Poster angekommen")
    #expect(FramePacing.text(r)
            == "Startseite 5,0 s: 296 Bilder (60 Hz) · 3 verpasst · ≈7 Bilder fehlen · längstes 48 ms · zuletzt: Poster angekommen")
    let quiet = FramePacing.Report(frames: 120, missed: 0, dropped: 0, longestMs: 17, hz: 60, tenths: 21, note: nil)
    #expect(FramePacing.text(quiet) == "Startseite 2,1 s: 120 Bilder (60 Hz) · 0 verpasst · ≈0 Bilder fehlen · längstes 17 ms")
    let empty = FramePacing.Report(frames: 120, missed: 0, dropped: 0, longestMs: 17, hz: 60, tenths: 21, note: "")
    #expect(FramePacing.text(empty) == FramePacing.text(quiet))
    let panel = FramePacing.Report(frames: 118, missed: 2, dropped: 3, longestMs: 125, hz: 24, tenths: 50, note: nil)
    #expect(FramePacing.text(panel, place: "Spur-Panel")
            == "Spur-Panel 5,0 s: 118 Bilder (24 Hz) · 2 verpasst · ≈3 Bilder fehlen · längstes 125 ms")
}

@Test func framePacingSumsDroppedFrames() {
    // Review M2: an 80 ms stall drops about four frames, a 26 ms one about one; both are one missed interval.
    var p = FramePacing(window: 5, keepAlive: 2)
    _ = p.activity(at: 0)
    _ = p.frame(at: 0, nominal: hz60)
    var t = 0.0
    for gap in [hz60, 0.080, hz60, hz60 * 1.6, hz60 * 2.4, hz60 * 3] {   // 5.12x, 1.6x, 2.4x, 3x the nominal frame
        t += gap
        _ = p.frame(at: t, nominal: hz60)
    }
    let last = p.stop()
    #expect(last?.frames == 6 && last?.missed == 4)
    #expect(last?.dropped == 4 + 1 + 1 + 2)                // rounded frames per interval minus the one shown, at least 1
}
