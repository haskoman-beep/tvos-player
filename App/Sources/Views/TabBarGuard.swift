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
        // Cheap pre-check before any task: only a stuck bar is repaired.
        let bar = HomeTopEdgeWatch.tabBarState()
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

    /// Main vertical scroll view of the visible page: the largest scroll view in the window that covers at least
    /// 40 % of the screen height (horizontal tile rows are lower). Outermost first on equal size.
    static func pageScrollView() -> PageScrollView? {
        guard let selected = HomeTopEdgeWatch.tabBarController()?.selectedViewController else { return nil }
        let page = navigationController(in: selected, depth: 0)?.topViewController ?? selected
        guard let root = page.viewIfLoaded, let window = root.window else { return nil }
        let minHeight = window.bounds.height * 0.4
        var best: UIScrollView?
        var bestArea: CGFloat = 0
        var queue: [UIView] = [root]
        var i = 0
        while i < queue.count, i < 4000 {
            let v = queue[i]
            i += 1
            if v.isHidden || v.alpha < 0.01 { continue }
            if let sv = v as? UIScrollView {
                let f = sv.convert(sv.bounds, to: window)
                let area = f.width * f.height
                if f.height >= minHeight, area > bestArea { best = sv; bestArea = area }
            }
            queue.append(contentsOf: v.subviews)
        }
        return best.map { PageScrollView(scrollView: $0, page: page) }
    }

    private static func navigationController(in vc: UIViewController, depth: Int) -> UINavigationController? {
        guard depth < 8 else { return nil }
        if let nav = vc as? UINavigationController { return nav }
        for child in vc.children {
            if let nav = navigationController(in: child, depth: depth + 1) { return nav }
        }
        return nil
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
                TabBarGuard.shared.visit("\(new.tab.logName), Tiefe \(new.depth)",
                                         popped: old.tab == new.tab && new.depth < old.depth)
            }
    }
}
