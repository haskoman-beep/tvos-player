import Foundation

/// Task 4.1a (F-A-1): where the user is when an action starts that navigates after an `await` (hero "Abspielen",
/// TorBox file). `visit` counts every change of the visible page, so a push and a pop while waiting count too.
public struct NavigationStamp: Equatable, Hashable, Sendable {
    public let tab: AppTab
    /// Pushed pages in the tab's path.
    public let depth: Int
    public let visit: Int

    public init(tab: AppTab, depth: Int, visit: Int = 0) {
        self.tab = tab
        self.depth = depth
        self.visit = visit
    }
}

public enum NavigationGuard {
    /// A late navigation only happens while the visible page is still the one where the action started.
    public static func mayPush(startedAt: NavigationStamp, now: NavigationStamp) -> Bool {
        startedAt == now
    }

    /// Task 4.1a (F-A-8): the tab bar guard starts a new visit on a tab change or a pop, not on a push.
    public static func startsVisit(old: NavigationStamp, new: NavigationStamp) -> Bool {
        old.tab != new.tab || new.depth < old.depth
    }
}
