import SwiftUI
import UIKit
import PlayerCore

/// Wave F-j: keeps the top tab bar reachable from the topmost element of the home page and logs why it was not.
/// The views report focus per part (button row, first row, empty-page button). The tab bar is requested
/// (`HomeTabBarRequest`) while the top edge or the bar holds focus or the page sits at its top position
/// (`HomeTopRules.barRequest`); after the focus scroll the page snaps to the very top if the bar is not on screen.
/// Only `barRequest` is observed (and only assigned on change), so scrolling and focus moves never re-render the
/// home page.
@MainActor @Observable final class HomeTopEdgeWatch {
    /// ID of the whole scroll content (scroll target "very top").
    static let topID = "home.top"
    /// Review N2: ID of the „Reihen & Collections“ button below the rows (scroll target of a rescued down press).
    static let actionButtonID = "home.actionButton"

    private(set) var barRequest: HomeTopRules.BarRequest = .automatic

    @ObservationIgnored private var focus = HomeTopFocus(edge: .heroButtons)
    @ObservationIgnored private var tracker = TopEdgeTracker()
    @ObservationIgnored private var navigation: NavigationStyle = .sidebar
    /// Distance from the very top of the vertical home scroll view (points).
    @ObservationIgnored private var offset: Double = 0
    /// Focus is in the tab bar (from `didUpdateNotification`, top navigation only).
    @ObservationIgnored private var inBar = false
    @ObservationIgnored private var throttle = LogThrottle(interval: 1)
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var settle: Task<Void, Never>?
    /// The first arrival per appearance is always logged, later ones only when something is off.
    @ObservationIgnored private var loggedArrival = false
    /// Set by the scroll view (ScrollViewReader): scrolls to `topID`.
    @ObservationIgnored var scrollToTop: (() -> Void)?
    /// Set by the scroll view (ScrollViewReader): scrolls a home row (heading included) to the list's top edge.
    @ObservationIgnored var scrollToRow: ((UUID) -> Void)?
    /// Review N2: set by the scroll view (ScrollViewReader): scrolls the „Reihen & Collections“ button into view.
    @ObservationIgnored var scrollToActionButton: (() -> Void)?
    /// Build 5 device test 1 (items 2, 7): an up (true) or down (false) press the focus engine dropped on the home
    /// page; `HomeView` moves the focus itself (`HomeMoveRescue`).
    /// Review W2/M1: with the row that kept the focus (from the focused element's frame, never from the row presence).
    @ObservationIgnored var onFailedMove: ((Bool, UUID) -> Void)?
    /// Review W2: successful focus updates; a rescue waits one main-queue hop and is dropped when one came in.
    @ObservationIgnored private var updateSerial = 0

    /// S5 (Build 4 follow-up): coordinate space of the list content; row frames in it only change with the layout.
    static let contentSpace = "home.list.content"
    /// S5: vertical scroll state of the list and the rows' frames in `contentSpace` (written per change, never
    /// observed: the heading checks read them, nothing re-renders).
    @ObservationIgnored private(set) var listScroll: HomeListScroll?
    @ObservationIgnored private var rowSpans: [UUID: HomeRowSpan] = [:]
    /// S5: the running heading checks of the focused row (a new row or a hand-over replaces them).
    @ObservationIgnored var headingChecks: Task<Void, Never>?

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

    func setOffset(_ value: Double) {
        offset = value
        updateRequest()
    }

    /// S5: scroll geometry of the list (offset from the very top and the largest offset).
    func setScroll(_ value: HomeListScroll) {
        listScroll = value
        if offset != value.offset { setOffset(value.offset) }
    }

    /// S5: a row's frame in `contentSpace` changed (row built by the lazy list, or its height changed).
    func setRowFrame(_ id: UUID, _ frame: CGRect) {
        rowSpans[id] = HomeRowSpan(minY: Double(frame.minY), maxY: Double(frame.maxY))
    }

    /// S5: row frame, list scroll state and the list's UIKit view for the heading check and its log line.
    func headingSample(row id: UUID) -> HeadingSnapSample {
        HeadingSnapSample(row: rowSpans[id], scroll: listScroll, list: Self.listView())
    }

    /// Build 7 device test: target of a focus scroll of the home list (`HomeFocusScroll`), raw content y of the
    /// visible rect's top. The row under the focused element goes to the list's top edge (`FocusScrollTarget.rowTop`)
    /// instead of where the focus engine centred the card; nil: leave the target as proposed (top edge focused, no
    /// focused element in the list, no row under it, or no change worth a scroll).
    func focusScrollTarget(rawY: Double, height: Double) -> Double? {
        guard !focus.atTop, let scroll = listScroll, let sv = TabBarGuard.shared.knownScrollView, sv.window != nil,
              let view = Self.focusedItem() as? UIView, view.window != nil, view.isDescendant(of: sv) else { return nil }
        let f = view.convert(view.bounds, to: sv)
        let focused = HomeRowSpan(minY: Double(f.minY), maxY: Double(f.maxY))
        guard let id = HomeMoveRescue.row(atContentY: Double(f.midY), spans: rowSpans.map { ($0.key, $0.value) }),
              let row = rowSpans[id] else { return nil }
        let proposed = rawY + scroll.insetTop
        let adjusted = FocusScrollTarget.rowTop(proposed: proposed, viewport: height - scroll.insetTop, row: row,
                                                focused: focused, maxOffset: scroll.maxOffset)
        guard abs(adjusted - proposed) > HeadingSnap.tolerance else { return nil }
        if throttle.allow("focus scroll", now: Self.now) {
            RemoteLog.info("nav", FocusScrollTarget.rowLine(proposed: proposed, adjusted: adjusted, row: row))
        }
        return adjusted - scroll.insetTop
    }

    /// S5: the home list's scroll view as UIKit sees it (read only): raw offset and its end, frame in the window,
    /// adjusted insets, and the safe area top of the page's view controller (cause 2 of the brief: differs it
    /// between launch and the return from a detail page?).
    private static func listView() -> HeadingSnapSample.ListView? {
        guard let sv = TabBarGuard.shared.knownScrollView, sv.window != nil else { return nil }
        let frame = sv.convert(sv.bounds, to: nil)
        var responder: UIResponder? = sv
        while let r = responder, !(r is UIViewController) { responder = r.next }
        let safeTop = (responder as? UIViewController)?.view.safeAreaInsets.top ?? sv.safeAreaInsets.top
        return HeadingSnapSample.ListView(
            offsetY: Double(sv.contentOffset.y),
            maxOffsetY: Double(sv.contentSize.height + sv.adjustedContentInset.bottom - sv.bounds.height),
            frameMinY: Double(frame.minY), frameMaxY: Double(frame.maxY),
            insetTop: Double(sv.adjustedContentInset.top), insetBottom: Double(sv.adjustedContentInset.bottom),
            safeTop: Double(safeTop))
    }

    // MARK: Focus state

    /// Called per scroll frame too: cheap, and assigns (re-renders the carrier) only when the request changes.
    private func updateRequest() {
        let request = HomeTopRules.barRequest(atTop: focus.atTop, inBar: inBar, offset: offset, navigation: navigation)
        if barRequest != request { barRequest = request }
    }

    private func refresh() {
        let top = focus.atTop
        updateRequest()
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
        let bar = Self.tabBarState()
        // Wave F-m: a bar stuck off screen goes to the tab-wide guard; the request and the snap cannot move it.
        if HomeTopRules.barStranded(bar, offset: before, navigation: navigation) {
            TabBarGuard.shared.check(.arrivedAtTop)
        }
        // Review F-j M1: with the bar on screen a residual offset stays (no shift of its own while the user moves on).
        let scroll = HomeTopRules.shouldScrollToTop(atTop: true, offset: before, barOnScreen: bar.onScreen,
                                                    navigation: navigation)
        if scroll, let scrollToTop {
            withAnimation(.easeOut(duration: 0.2)) { scrollToTop() }
        }
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
        // Back from another tab via the bar: the focus may still be in it.
        inBar = navigation == .top && Self.focusedItem().map(Self.isInTabBar) == true
        updateRequest()
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
        headingChecks?.cancel()
        headingChecks = nil
    }

    private func focusEvent(_ note: Notification, failed: Bool) {
        guard let context = note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext
        else { return }
        // Review F-j I1: track every focus change into and out of the bar, so the request holds while it has focus.
        let nextInBar = !failed && navigation == .top && context.nextFocusedItem.map(Self.isInTabBar) == true
        if !failed, nextInBar != inBar {
            inBar = nextInBar
            updateRequest()
        }
        if !failed { updateSerial &+= 1 }
        if failed { rescueLater(context) }
        guard context.focusHeading.contains(.up) else { return }
        // Review F-j M2: up inside the bar itself has no target; that is not a home page failure.
        if failed, context.previouslyFocusedItem.map(Self.isInTabBar) == true { return }
        let now = Self.now
        let atTop = tracker.wasAtTop(now: now)
        // Up moves inside the content (away from the top) produce no line; stop before describing the target.
        guard atTop || failed else { return }
        let outcome: TabBarReachLog.UpOutcome
        if failed {
            outcome = .failed
        } else if nextInBar {
            outcome = .reachedBar
        } else {
            outcome = .stayedInContent(context.nextFocusedItem.map(Self.describe) ?? "nichts")
        }
        // Throttle (key per case, review M3) before the UIKit lookup (review M2).
        guard TabBarReachLog.logs(outcome, atTop: atTop), throttle.allow("up \(outcome.kind)", now: now),
              let line = TabBarReachLog.up(outcome, atTop: atTop, edge: focus.edge, bar: Self.tabBarState(),
                                           offset: offset, navigation: navigation) else { return }
        RemoteLog.info("nav", line)
    }

    /// Build 5 device test 1 (items 2, 7) with review W2/M1/N3: a dropped up/down press of an element inside the
    /// home list goes to `onFailedMove` with the row under that element, one hop later and only when no focus
    /// update came in meanwhile; at most one per row, direction and second (review N3: a held direction against a row that
    /// cannot take the focus logs and rescues once a second, a rescue that moved on to the next row is not held back).
    private func rescueLater(_ context: UIFocusUpdateContext) {
        let up = context.focusHeading.contains(.up)
        guard up || context.focusHeading.contains(.down), onFailedMove != nil,
              let view = context.previouslyFocusedItem as? UIView, let sv = TabBarGuard.shared.knownScrollView,
              view.window != nil, view.isDescendant(of: sv) else { return }
        let y = Double(view.convert(view.bounds, to: sv).midY)
        guard let row = HomeMoveRescue.row(atContentY: y, spans: rowSpans.map { ($0.key, $0.value) }),
              throttle.allow("rescue \(up ? "up" : "down") \(row.uuidString)", now: Self.now) else { return }
        let serial = updateSerial
        Task { @MainActor [weak self] in
            guard let self, self.updateSerial == serial else { return }
            self.onFailedMove?(up, row)
        }
    }

    // MARK: UIKit lookup (read only)

    /// Type and screen position of the element that took the move (SwiftUI host names can be long).
    private static func describe(_ item: UIFocusItem) -> String {
        let name = String(String(describing: type(of: item)).prefix(60))
        guard let view = item as? UIView, view.window != nil else { return name }
        let f = view.convert(view.bounds, to: nil)
        return "\(name), y \(Int(f.minY.rounded()))"
    }

    private static func focusedItem() -> UIFocusItem? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return nil }
        return UIFocusSystem.focusSystem(for: window)?.focusedItem
    }

    /// Only a `UITabBar` ancestor counts (review M4: should the tvOS bar ever not be one, a successful move up is
    /// logged as "Fokus blieb im Inhalt" with y near 0, and the request is still held by the unchanged offset).
    static func isInTabBar(_ item: UIFocusItem) -> Bool {
        var env: UIFocusEnvironment? = item
        var steps = 0
        while let e = env, steps < 64 {
            if e is UITabBar { return true }
            env = e.parentFocusEnvironment
            steps += 1
        }
        return false
    }

    static func keyWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    static func tabBarController() -> UITabBarController? {
        tabBarController(from: keyWindow()?.rootViewController, depth: 0)
    }

    static func tabBarState() -> TabBarState {
        guard let window = keyWindow() else { return .notFound }
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
