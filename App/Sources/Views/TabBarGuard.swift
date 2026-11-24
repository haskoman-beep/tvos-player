import SwiftUI
import UIKit
import PlayerCore

/// Wave F-m round 1: keeps the top tab bar bound to the visible page in every tab. Build 198 left the bar stuck far
/// above the screen (it followed the source list after the player, y −2250…−2182) on the home page and in the
/// Library tab. After every pop, after the player cover closed and after a failed move up, the guard compares the
/// bar with the offset of the visible page's main scroll view (`HomeTopRules.barStranded`) and repairs it step by
/// step (`TabBarRepair`): bind the page's scroll view as content scroll view of its controller, then hide and show
/// the bar through the tab bar controller. Every step and a failed repair is logged ("nav").
@MainActor final class TabBarGuard {
    static let shared = TabBarGuard()

    private var navigation: NavigationStyle = .sidebar
    /// Log name of the visible page (tab and depth), set by `TabBarGuardHook`.
    private var page = "Start, Tiefe 0"
    private var observer: NSObjectProtocol?
    private var task: Task<Void, Never>?
    /// Increases with every new check; a cancelled check never clears a newer one.
    private var generation = 0
    /// Steps done on the visible page, and whether "all steps done" was logged for it.
    private var lastRepair: TabBarRepair?
    private var loggedExhausted = false
    /// Main list handed over by a page (`PageScrollViewProbe`, home); preferred while it is in the visible page.
    weak var knownScrollView: UIScrollView?

    private init() {}

    /// Called by `TabBarGuardHook` (root view); idempotent.
    func install(navigation: NavigationStyle) {
        self.navigation = navigation
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: UIFocusSystem.movementDidFailNotification, object: nil,
                                                          queue: .main) { note in
            MainActor.assumeIsolated { TabBarGuard.shared.moveFailed(note) }
        }
    }

    func configure(navigation: NavigationStyle) { self.navigation = navigation }

    /// The visible page changed (`popped`: back to `page` by a pop).
    func visit(_ page: String, popped: Bool) {
        self.page = page
        if popped { check(.popped) }
    }

    /// Checks the bar after the trigger's delay and repairs it while it is stuck. A new visit (pop, player closed)
    /// replaces a running check and allows the steps again; focus triggers wait for a running check.
    func check(_ trigger: TabBarRepair.Trigger) {
        if trigger.startsVisit {
            task?.cancel()
            task = nil
            lastRepair = nil
            loggedExhausted = false
        } else if task != nil {
            return
        }
        generation += 1
        let mine = generation
        task = Task { [weak self] in
            let ms = trigger.delayMilliseconds
            if ms > 0 { try? await Task.sleep(for: .milliseconds(ms)) }
            guard !Task.isCancelled else { return }
            await self?.repair(trigger)
            guard let self, self.generation == mine else { return }
            self.task = nil
        }
    }

    // MARK: Repair

    private func repair(_ trigger: TabBarRepair.Trigger) async {
        var bar = HomeTopEdgeWatch.tabBarState()
        var target = Self.pageScrollView()
        var offset = target.map { Self.distanceFromTop($0.scrollView) } ?? 0
        while HomeTopRules.barStranded(bar, offset: offset, navigation: navigation) {
            guard let step = TabBarRepair.next(after: lastRepair) else {
                // Review F-m I1: every dead end is logged (once per page visit), also while scrolled down.
                if !loggedExhausted {
                    loggedExhausted = true
                    RemoteLog.info("nav", TabBarReachLog.repairExhausted(trigger: trigger, page: page, bar: bar,
                                                                         offset: offset, navigation: navigation))
                }
                return
            }
            lastRepair = step
            let observed = Self.observedDescription(target?.scrollView)
            let applied = apply(step, target)
            try? await Task.sleep(for: .milliseconds(TabBarRepair.checkMilliseconds))
            guard !Task.isCancelled else { return }
            let after = HomeTopEdgeWatch.tabBarState()
            RemoteLog.info("nav", TabBarReachLog.repaired(step, trigger: trigger, page: page, applied: applied, before: bar,
                                                          after: after, offset: offset, observed: observed,
                                                          navigation: navigation))
            bar = after
            target = Self.pageScrollView()
            offset = target.map { Self.distanceFromTop($0.scrollView) } ?? 0
        }
    }

    private func apply(_ step: TabBarRepair, _ target: PageScrollView?) -> Bool {
        switch step {
        case .rebind:
            // The navigation controller answers `contentScrollView(for: .top)` for its top page; bind it there.
            guard let target, target.scrollView.window != nil else { return false }
            target.page.setContentScrollView(target.scrollView, for: .top)
            HomeTopEdgeWatch.tabBarController()?.view.setNeedsLayout()
            return true
        case .reshow:
            guard let controller = HomeTopEdgeWatch.tabBarController() else { return false }
            controller.setTabBarHidden(true, animated: false)
            controller.setTabBarHidden(false, animated: true)
            return true
        }
    }

    private func moveFailed(_ note: Notification) {
        guard navigation == .top,
              let context = note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext,
              context.focusHeading.contains(.up) else { return }
        // Up inside the bar itself has no target; that is not a stuck bar.
        if context.previouslyFocusedItem.map(HomeTopEdgeWatch.isInTabBar) == true { return }
        // Cheap pre-check before any task (review N-M1): read the bar first, walk the page only for a bar off screen.
        let bar = HomeTopEdgeWatch.tabBarState()
        guard bar.found, bar.maxY <= 1 else { return }
        let offset = Self.pageScrollView().map { Self.distanceFromTop($0.scrollView) } ?? 0
        guard HomeTopRules.barStranded(bar, offset: offset, navigation: navigation) else { return }
        check(.upFailed)
    }

    // MARK: UIKit lookup

    struct PageScrollView {
        let scrollView: UIScrollView
        /// The visible page's controller (top of its navigation stack).
        let page: UIViewController
    }

    /// Main vertical scroll view of the visible page (`PageScrollPick`, review N-I1): only scroll views that scroll
    /// vertically, compared by their part inside the window; the list handed over by the page wins.
    static func pageScrollView() -> PageScrollView? {
        guard let selected = HomeTopEdgeWatch.tabBarController()?.selectedViewController else { return nil }
        let page = visibleNavigationController(in: selected)?.topViewController ?? selected
        guard let root = page.viewIfLoaded, let window = root.window else { return nil }
        let known = shared.knownScrollView
        var views: [UIScrollView] = []
        var candidates: [PageScrollPick.Candidate] = []
        var queue: [UIView] = [root]
        var i = 0
        while i < queue.count, i < 4000 {
            let v = queue[i]
            i += 1
            if v.isHidden || v.alpha < 0.01 { continue }
            if let sv = v as? UIScrollView {
                views.append(sv)
                candidates.append(PageScrollPick.Candidate(frame: sv.convert(sv.bounds, to: window),
                                                           contentSize: sv.contentSize,
                                                           alwaysBounceVertical: sv.alwaysBounceVertical,
                                                           known: sv === known))
            }
            queue.append(contentsOf: v.subviews)
        }
        guard let pick = PageScrollPick.choose(candidates, window: window.bounds) else { return nil }
        return PageScrollView(scrollView: views[pick], page: page)
    }

    /// Navigation controller of the visible page (review N-M2): of all stacks in the tab, the one with the largest
    /// part on screen (a split view or a settings column holds several).
    private static func visibleNavigationController(in vc: UIViewController) -> UINavigationController? {
        var found: [UINavigationController] = []
        collectNavigationControllers(in: vc, depth: 0, into: &found)
        var best: UINavigationController?
        var bestArea: CGFloat = 0
        for nav in found {
            guard let v = nav.viewIfLoaded, let window = v.window, !v.isHidden else { continue }
            let f = v.convert(v.bounds, to: window).intersection(window.bounds)
            let area = f.isNull ? 0 : f.width * f.height
            if best == nil || area > bestArea { best = nav; bestArea = area }
        }
        return best
    }

    private static func collectNavigationControllers(in vc: UIViewController, depth: Int,
                                                     into found: inout [UINavigationController]) {
        guard depth < 8 else { return }
        if let nav = vc as? UINavigationController {
            found.append(nav)
            // A nested stack lies in the top page only.
            if let top = nav.topViewController { collectNavigationControllers(in: top, depth: depth + 1, into: &found) }
            return
        }
        for child in vc.children { collectNavigationControllers(in: child, depth: depth + 1, into: &found) }
    }

    static func distanceFromTop(_ sv: UIScrollView) -> Double {
        Double(sv.contentOffset.y + sv.adjustedContentInset.top)
    }

    /// Which scroll view the tab bar controller reports for its top edge (log only): the page's, none, or another.
    private static func observedDescription(_ pageView: UIScrollView?) -> String {
        guard let selected = HomeTopEdgeWatch.tabBarController()?.selectedViewController else { return "unbekannt" }
        guard let sv = selected.contentScrollView(for: .top) else { return "keine" }
        if sv === pageView { return "Seite" }
        let name = String(String(describing: type(of: sv)).prefix(40))
        return "\(name) (Versatz \(Int(distanceFromTop(sv).rounded())) pt\(sv.window == nil ? ", nicht im Fenster" : ""))"
    }
}

/// Root view hook: installs the guard, follows the navigation style and reports the visible page; a lower depth
/// in the same tab is a pop.
struct TabBarGuardHook: ViewModifier {
    let tab: AppTab
    let depth: Int
    let navigation: NavigationStyle

    private struct Visible: Equatable { let tab: AppTab; let depth: Int }

    func body(content: Content) -> some View {
        content
            .onAppear { TabBarGuard.shared.install(navigation: navigation) }
            .onChange(of: navigation) { _, n in TabBarGuard.shared.configure(navigation: n) }
            .onChange(of: Visible(tab: tab, depth: depth), initial: true) { old, new in
                VisiblePage.moved(tab: new.tab, depth: new.depth)
                TabBarGuard.shared.visit("\(new.tab.logName), Tiefe \(new.depth)",
                                         popped: old.tab == new.tab && new.depth < old.depth,
                                         startsVisit: NavigationGuard.startsVisit(
                                             old: NavigationStamp(tab: old.tab, depth: old.depth),
                                             new: NavigationStamp(tab: new.tab, depth: new.depth)))
            }
    }
}

/// Task 4.1a (F-A-1): the visible page as a `NavigationStamp`, kept by `TabBarGuardHook`. Actions that navigate
/// after an `await` take a stamp before and push only while `NavigationGuard.mayPush` holds.
@MainActor enum VisiblePage {
    private(set) static var stamp = NavigationStamp(tab: .home, depth: 0)

    static func moved(tab: AppTab, depth: Int) {
        guard tab != stamp.tab || depth != stamp.depth else { return }
        stamp = NavigationStamp(tab: tab, depth: depth, visit: stamp.visit + 1)
    }

    /// A page outside the path (manager, browser, settings link) covers the current one: a new visit.
    static func covered() {
        stamp = NavigationStamp(tab: stamp.tab, depth: stamp.depth, visit: stamp.visit + 1)
    }

    /// True while the visible page is the one of `start`; otherwise logs the dropped jump.
    static func mayNavigate(from start: NavigationStamp, _ what: String) -> Bool {
        if NavigationGuard.mayPush(startedAt: start, now: stamp) { return true }
        RemoteLog.info("nav", "navigation: später Sprung verworfen (\(what))")
        return false
    }
}

/// Wave F-m round 2: zero-size UIKit view inside a page's main list; hands the list's `UIScrollView` to the guard
/// (review N-I1: preferred over the size heuristic). Not focusable, no touches, draws nothing.
struct PageScrollViewProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView {
        let v = ProbeView()
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ProbeView, context: Context) -> CGSize? { CGSize(width: 1, height: 1) }

    final class ProbeView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            // The nearest scroll view above the probe is the list (the probe sits in the list content, outside rows).
            var v = superview
            while let s = v {
                if let sv = s as? UIScrollView { TabBarGuard.shared.knownScrollView = sv; return }
                v = s.superview
            }
        }
    }
}
