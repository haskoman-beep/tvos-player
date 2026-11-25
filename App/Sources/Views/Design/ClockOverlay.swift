import SwiftUI
import UIKit
import PlayerCore

/// Uhr oben rechts für die obere Leiste (Format HH:mm, aktualisiert jede Minute).
/// Build 3 device test: the clock lay fixed over the page while the top bar scrolled away (source list); it now
/// follows the bar (`followsTabBar`): moves up with it and fades out when the bar is off screen or hidden.
struct ClockView: View {
    var followsTabBar = false
    @State private var bar = TabBarFollower()

    private static let format: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            Text(Self.format.string(from: ctx.date))
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .offset(y: followsTabBar ? bar.shift : 0)
        .opacity(followsTabBar && !bar.shown ? 0 : 1)
        .animation(.easeInOut(duration: 0.2), value: bar.shown)
        .allowsHitTesting(false)
        .onAppear { if followsTabBar { bar.start() } }
        .onDisappear { bar.stop() }
        .onChange(of: followsTabBar) { _, on in if on { bar.start() } else { bar.stop() } }
    }
}

/// Reads the top tab bar's frame once per frame (30 Hz) and publishes how far it moved up from its resting place.
/// Only changes are published, so a resting bar costs one frame conversion per tick and no view update.
@MainActor @Observable final class TabBarFollower {
    /// Vertical shift of the bar against its resting place (≤ 0 while it scrolls away).
    private(set) var shift: CGFloat = 0
    /// Bar on screen and not hidden.
    private(set) var shown = true
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var restMinY: CGFloat?

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: Ticker(self), selector: #selector(Ticker.tick))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        l.add(to: .main, forMode: .common)
        link = l
        tick()
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    fileprivate func tick() {
        let s = HomeTopEdgeWatch.tabBarState()
        guard s.found else { return }
        let visible = !s.hidden && !s.controllerHidden && s.alpha > 0.01 && s.maxY > 1
        let minY = CGFloat(s.minY)
        // Resting place: the lowest top edge seen while the bar is fully visible.
        if visible, minY > (restMinY ?? -.infinity) { restMinY = minY }
        let newShift = min(0, minY - (restMinY ?? minY))
        if abs(newShift - shift) >= 0.5 { shift = newShift }
        if visible != shown { shown = visible }
    }

    /// CADisplayLink retains its target; the ticker holds the follower weakly so `stop()` alone ends it.
    private final class Ticker: NSObject {
        weak var owner: TabBarFollower?
        init(_ owner: TabBarFollower) { self.owner = owner }
        @objc func tick() { MainActor.assumeIsolated { owner?.tick() } }
    }
}
