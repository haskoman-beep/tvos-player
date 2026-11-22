import SwiftUI
import UIKit
import PlayerCore

/// Wave F-j: keeps the top tab bar reachable from the topmost element of the home page and logs why it was not.
/// The views report focus per part (button row, first row, empty-page button); while the top edge holds focus
/// the tab bar is requested (`HomeTabBarRequest`) and the page is scrolled exactly to the top.
/// Only `barRequest` is observed, so focus moves elsewhere never re-render the home page.
@MainActor @Observable final class HomeTopEdgeWatch {
    /// ID of the whole scroll content (scroll target "very top").
    static let topID = "home.top"

    private(set) var barRequest: HomeTopRules.BarRequest = .automatic

    @ObservationIgnored private var focus = HomeTopFocus(edge: .heroButtons)
    @ObservationIgnored private var tracker = TopEdgeTracker()
    @ObservationIgnored private var navigation: NavigationStyle = .sidebar
    /// Distance from the very top of the vertical home scroll view (points).
    @ObservationIgnored private var offset: Double = 0
    @ObservationIgnored private var throttle = LogThrottle(interval: 1)
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var settle: Task<Void, Never>?
    /// The first arrival per appearance is always logged, later ones only when something is off.
    @ObservationIgnored private var loggedArrival = false
    /// Set by the scroll view (ScrollViewReader): scrolls to `topID`.
    @ObservationIgnored var scrollToTop: (() -> Void)?

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    func configure(edge: HomeTopEdge, navigation: NavigationStyle) {
        focus.edge = edge
        self.navigation = navigation
        refresh()
    }

    func report(_ part: HomeTopFocus.Part, _ isFocused: Bool) {
        focus.set(part, isFocused)
        refresh()
    }

    func setOffset(_ value: Double) { offset = value }

    // MARK: Focus state

    private func refresh() {
        let top = focus.atTop
        let request = HomeTopRules.barRequest(atTop: top, navigation: navigation)
        if barRequest != request { barRequest = request }
        guard tracker.set(top, now: Self.now) else { return }
        settle?.cancel()
        settle = nil
        guard top else { return }
        // After the focus scroll settled: snap to the very top and log the state of the bar.
        settle = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(HomeTopRules.settleMilliseconds))
            guard !Task.isCancelled else { return }
            self?.settled()
        }
    }

    private func settled() {
        guard tracker.atTop else { return }
        let before = offset
        let scroll = HomeTopRules.shouldScrollToTop(atTop: true, offset: before, navigation: navigation)
        if scroll, let scrollToTop {
            withAnimation(.easeOut(duration: 0.2)) { scrollToTop() }
        }
        let bar = Self.tabBarState()
        guard !loggedArrival || scroll || (navigation == .top && !bar.onScreen),
              throttle.allow("arrived", now: Self.now) else { return }
        loggedArrival = true
        RemoteLog.info("nav", TabBarReachLog.arrived(edge: focus.edge, offset: before, scrolledToTop: scroll && scrollToTop != nil,
                                                     bar: bar, request: barRequest, navigation: navigation))
    }

    // MARK: Focus system (only while the home page is visible)

    func start() {
        guard observers.isEmpty else { return }
        loggedArrival = false
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIFocusSystem.movementDidFailNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { self?.focusEvent(note, failed: true) }
        })
        observers.append(center.addObserver(forName: UIFocusSystem.didUpdateNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { self?.focusEvent(note, failed: false) }
        })
    }

    func stop() {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
        settle?.cancel()
        settle = nil
    }

    private func focusEvent(_ note: Notification, failed: Bool) {
        guard let context = note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext,
              context.focusHeading.contains(.up) else { return }
        let now = Self.now
        let atTop = tracker.wasAtTop(now: now)
        // Up moves inside the content (away from the top) produce no line.
        guard atTop || failed else { return }
        let outcome: TabBarReachLog.UpOutcome
        if failed {
            outcome = .failed
        } else if let next = context.nextFocusedItem, Self.isInTabBar(next) {
            outcome = .reachedBar
        } else {
            outcome = .stayedInContent(context.nextFocusedItem.map(Self.describe) ?? "nichts")
        }
        guard let line = TabBarReachLog.up(outcome, atTop: atTop, edge: focus.edge, bar: Self.tabBarState(),
                                           offset: offset, navigation: navigation),
              throttle.allow("up \(outcome)", now: now) else { return }
        RemoteLog.info("nav", line)
    }

    // MARK: UIKit lookup (read only)

    /// Type and screen position of the element that took the move (SwiftUI host names can be long).
    private static func describe(_ item: UIFocusItem) -> String {
        let name = String(String(describing: type(of: item)).prefix(60))
        guard let view = item as? UIView, view.window != nil else { return name }
        let f = view.convert(view.bounds, to: nil)
        return "\(name), y \(Int(f.minY.rounded()))"
    }

    private static func isInTabBar(_ item: UIFocusItem) -> Bool {
        var env: UIFocusEnvironment? = item
        var steps = 0
        while let e = env, steps < 64 {
            if e is UITabBar { return true }
            env = e.parentFocusEnvironment
            steps += 1
        }
        return false
    }

    private static func tabBarState() -> TabBarState {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return .notFound }
        let controller = tabBarController(from: window.rootViewController, depth: 0)
        guard let bar = controller?.tabBar ?? findTabBar(in: window) else { return .notFound }
        let frame = bar.convert(bar.bounds, to: window)
        return TabBarState(found: true, hidden: bar.isHidden || bar.window == nil,
                           controllerHidden: controller?.isTabBarHidden ?? false, alpha: Double(bar.alpha),
                           minY: Double(frame.minY), maxY: Double(frame.maxY),
                           windowHeight: Double(window.bounds.height))
    }

    private static func tabBarController(from vc: UIViewController?, depth: Int) -> UITabBarController? {
        guard let vc, depth < 12 else { return nil }
        if let t = vc as? UITabBarController { return t }
        for child in vc.children {
            if let t = tabBarController(from: child, depth: depth + 1) { return t }
        }
        return nil
    }

    private static func findTabBar(in root: UIView) -> UITabBar? {
        var queue: [UIView] = [root]
        var i = 0
        while i < queue.count, i < 4000 {
            let v = queue[i]
            if let bar = v as? UITabBar { return bar }
            queue.append(contentsOf: v.subviews)
            i += 1
        }
        return nil
    }
}

/// Zero-size carrier of the tab bar request: only this view re-renders when the top edge gains or loses focus.
struct HomeTabBarRequest: View {
    let watch: HomeTopEdgeWatch

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .toolbar(watch.barRequest == .visible ? .visible : .automatic, for: .tabBar)
    }
}
