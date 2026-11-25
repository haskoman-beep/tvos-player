import SwiftUI
import UIKit
import PlayerCore

/// Task 5.6 (D-28): the clock of the look (`global.clock`) at the top right of every tab page: right 80, top 56
/// from the screen edge, `meta` role 27 pt × typeScale, weight 500, white 75 %, digits of equal width. It lies
/// over the tab view, so the player (a full-screen cover) hides it. With the top bar it follows the bar
/// (Build 3 device test: it moves up with the bar and fades out when the bar is off screen or hidden).
/// In the sidebar it leaves pushed pages (`overPushedPage`); the top bar hides there and the clock with it.
struct ClockOverlay: View {
    var overPushedPage = false
    @Environment(\.theme) private var theme
    @State private var frameLogged = false

    var body: some View {
        let chrome = theme.chrome
        if chrome.showsClock, !(chrome.navigation == .seitenleiste && overPushedPage) {
            ClockView(followsTabBar: chrome.navigation == .oben, style: .look(size: chrome.clockFontSize))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { r in
                    // Once per run (review I2): the device shows whether it sits at right 80 / top 56.
                    guard !frameLogged, r.width > 0 else { return }
                    frameLogged = true
                    RemoteLog.info("nav", "Uhr-Rahmen x \(Int(r.minX))–\(Int(r.maxX)), y \(Int(r.minY))–\(Int(r.maxY))")
                }
                .padding(.top, LookChrome.clockTop)
                .padding(.trailing, LookChrome.clockTrailing)
                // Fill the screen first, then leave the safe area: the paddings count from the screen edge.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .ignoresSafeArea()
                .onAppear { RemoteLog.info("nav", "Uhr an (\(chrome.navigation.rawValue))") }
                .onDisappear { RemoteLog.info("nav", "Uhr aus") }
        }
    }
}

/// Time text, HH:mm on the 24-hour clock in the locale's form (`LookChrome.clockText`), refreshed at every full
/// minute. Used by `ClockOverlay` and the pause card of the player.
struct ClockView: View {
    enum Style: Equatable {
        /// Pause card: today's look (title3, semibold, secondary).
        case pauseCard
        /// Look clock: `meta` size from `LookChrome`, weight 500, white 75 %.
        case look(size: CGFloat)
    }

    var followsTabBar = false
    var style: Style = .pauseCard
    @State private var bar = TabBarFollower()
    @Environment(\.theme) private var theme

    /// One formatter; the autoupdating time zone follows a change in the system settings at the next minute.
    private static let format = LookChrome.clockFormatter(locale: .autoupdatingCurrent, timeZone: .autoupdatingCurrent)

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            styled(Text(Self.format.string(from: ctx.date)))
        }
        .offset(y: followsTabBar ? bar.shift : 0)
        .opacity(followsTabBar && !bar.shown ? 0 : 1)
        .animation(theme.motion.fade > 0 ? Animation.easeInOut(duration: 0.2) : nil, value: bar.shown)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { if followsTabBar { bar.start() } }
        .onDisappear { bar.stop() }
        .onChange(of: followsTabBar) { _, on in if on { bar.start() } else { bar.stop() } }
    }

    @ViewBuilder private func styled(_ text: Text) -> some View {
        switch style {
        case .pauseCard:
            text.font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        case .look(let size):
            text.font(.system(size: size, weight: ThemeValues.TypeScale.weight(LookChrome.clockWeight)).monospacedDigit())
                .foregroundStyle(theme.color.primary.opacity(LookChrome.clockOpacity))
        }
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
