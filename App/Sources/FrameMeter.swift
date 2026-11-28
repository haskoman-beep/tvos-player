import Foundation
import QuartzCore
import PlayerCore

/// Build 4 follow-up S1: frame meter of the home page. The hitch watchdog only sees the main thread stopping for
/// 250 ms; the stutter of the Build 4 device test (fast right presses while posters arrive) lies at 30–100 ms.
/// While the home page is visible and focus moves, a display link counts frames; every 5 s with activity one
/// `ruckler` line goes out (frames, missed frames, dropped frames, longest frame, P3: events of the window and the missed
/// frames near them, last note; rules in `FramePacing`). Silent when
/// nothing moves, off during playback and with Settings › System › Diagnose › „Ruckler protokollieren“ off.
@MainActor
enum FrameMeter {
    private static var pacing = FramePacing()
    private static var link: CADisplayLink?
    private static var isHomeVisible = false

    /// Home page appeared / disappeared (`HomeView`). Leaving ends the window with its line.
    static func homeVisible(_ visible: Bool) {
        isHomeVisible = visible
        if !visible { stop() }
    }

    /// Focus moved to another card of a home row. Starts the display link when it is not running.
    static func focusMoved() {
        guard isHomeVisible, !StreamPrefetcher.shared.playerActive, MainThreadWatchdog.isEnabled else { return }
        guard pacing.activity(at: CACurrentMediaTime()) else { return }
        start()
    }

    /// Short event note for the next line (e.g. „Poster angekommen“, „Quellen abgelegt“); kept only while measuring.
    static func note(_ s: String) {
        guard link != nil else { return }
        pacing.note(s)
    }

    /// Build 4 follow-up 2 (P3): a render-side event (backdrop swap, card expansion, poster picture, badge pass, stored
    /// sources, prefetch start). Counted in the next `ruckler` line and named as its note while measuring; its time
    /// says whether the next missed frames lie near it (rules in `FramePacing`).
    static func event(_ kind: FramePacing.Event) {
        pacing.event(kind, at: CACurrentMediaTime())
    }

    /// Playback starts (`StreamPrefetcher.playerAppeared`): no measuring under the player.
    static func playbackStarted() { stop() }

    private static func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: Ticker(), selector: #selector(Ticker.tick(_:)))
        l.add(to: .main, forMode: .common)   // native rate: the UI's own frame pace
        link = l
    }

    private static func stop() {
        if let r = pacing.stop() { RemoteLog.info("ruckler", FramePacing.text(r)) }
        link?.invalidate()
        link = nil
    }

    fileprivate static func tick(timestamp: CFTimeInterval, target: CFTimeInterval) {
        let t = pacing.frame(at: timestamp, nominal: target - timestamp)
        if let r = t.report { RemoteLog.info("ruckler", FramePacing.text(r)) }
        if !t.keepRunning {
            link?.invalidate()
            link = nil
        }
    }

    /// CADisplayLink retains its target; the stateless ticker forwards the two timestamps (no allocation per frame).
    private final class Ticker: NSObject {
        @objc func tick(_ link: CADisplayLink) {
            let ts = link.timestamp, target = link.targetTimestamp
            MainActor.assumeIsolated { FrameMeter.tick(timestamp: ts, target: target) }
        }
    }
}

/// p0a1 panel: the same frame count while focus moves in the open track panel (playback runs below it; with frame
/// rate matching the TV may run at 24 Hz, then every focus animation shows only 24 pictures per second). One
/// `ruckler` line „Spur-Panel …“ per 5 s window with focus moves, a last one when the panel closes. Off with
/// „Ruckler protokollieren“ off. Shows the UI frame rate under the panel and whether focus steps miss frames.
@MainActor
enum PanelFrameMeter {
    private static var pacing = FramePacing()
    private static var link: CADisplayLink?

    /// The user moved focus in the panel. Starts the display link when it is not running.
    static func focusMoved() {
        guard MainThreadWatchdog.isEnabled else { return }
        guard pacing.activity(at: CACurrentMediaTime()) else { return }
        guard link == nil else { return }
        let l = CADisplayLink(target: Ticker(), selector: #selector(Ticker.tick(_:)))
        l.add(to: .main, forMode: .common)   // native rate: the UI's own frame pace (24 Hz in a matched 24p mode)
        link = l
    }

    /// The panel closed: the partial window's line.
    static func stop() {
        if let r = pacing.stop() { RemoteLog.info("ruckler", FramePacing.text(r, place: "Spur-Panel")) }
        link?.invalidate()
        link = nil
    }

    fileprivate static func tick(timestamp: CFTimeInterval, target: CFTimeInterval) {
        let t = pacing.frame(at: timestamp, nominal: target - timestamp)
        if let r = t.report { RemoteLog.info("ruckler", FramePacing.text(r, place: "Spur-Panel")) }
        if !t.keepRunning {
            link?.invalidate()
            link = nil
        }
    }

    private final class Ticker: NSObject {
        @objc func tick(_ link: CADisplayLink) {
            let ts = link.timestamp, target = link.targetTimestamp
            MainActor.assumeIsolated { PanelFrameMeter.tick(timestamp: ts, target: target) }
        }
    }
}
