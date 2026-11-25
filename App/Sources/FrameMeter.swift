import Foundation
import QuartzCore
import PlayerCore

/// Build 4 follow-up S1: frame meter of the home page. The hitch watchdog only sees the main thread stopping for
/// 250 ms; the stutter of the Build 4 device test (fast right presses while posters arrive) lies at 30–100 ms.
/// While the home page is visible and focus moves, a display link counts frames; every 5 s with activity one
/// `ruckler` line goes out (frames, missed frames, longest frame, last note; rules in `FramePacing`). Silent when
/// nothing moves, off during playback and with Settings › System › Diagnose › „Ruckler protokollieren“ off.
@MainActor
enum FrameMeter {
    private static var pacing = FramePacing()
    private static var link: CADisplayLink?
    private static var homeVisible = false

    /// Home page appeared / disappeared (`HomeView`). Leaving ends the window with its line.
    static func homeVisible(_ visible: Bool) {
        homeVisible = visible
        if !visible { stop() }
    }

    /// Focus moved to another card of a home row. Starts the display link when it is not running.
    static func focusMoved() {
        guard homeVisible, !StreamPrefetcher.shared.playerActive, MainThreadWatchdog.isEnabled else { return }
        guard pacing.activity(at: CACurrentMediaTime()) else { return }
        start()
    }

    /// Short event note for the next line (e.g. „Poster angekommen“, „Quellen abgelegt“); kept only while measuring.
    static func note(_ s: String) {
        guard link != nil else { return }
        pacing.note(s)
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
