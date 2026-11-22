import Testing
@testable import PlayerCore

// MARK: Home page top edge and tab bar (wave F-j)

@Test func topEdgeIsHeroButtonsWheneverHeroShows() {
    #expect(HomeTopEdge.topmost(hasHero: true, rowCount: 5, layoutEmpty: false) == .heroButtons)
    #expect(HomeTopEdge.topmost(hasHero: true, rowCount: 0, layoutEmpty: false) == .heroButtons)
}

@Test func topEdgeWithoutHero() {
    #expect(HomeTopEdge.topmost(hasHero: false, rowCount: 3, layoutEmpty: false) == .firstRow)
    #expect(HomeTopEdge.topmost(hasHero: false, rowCount: 0, layoutEmpty: true) == .addRowsButton)
    #expect(HomeTopEdge.topmost(hasHero: false, rowCount: 0, layoutEmpty: false) == .managerButton)
}

@Test func topFocusCountsOnlyThePartOfTheCurrentEdge() {
    var f = HomeTopFocus(edge: .heroButtons)
    #expect(!f.atTop)
    f.set(.firstRow, true)
    #expect(!f.atTop)              // first row lies below the hero buttons
    f.set(.heroButtons, true)
    #expect(f.atTop)
    f.set(.heroButtons, false)
    #expect(!f.atTop)
    f.edge = .firstRow             // hero disappeared: the first row is on top now
    #expect(f.atTop)
    f.edge = .addRowsButton
    #expect(!f.atTop)
    f.set(.actionButton, true)
    #expect(f.atTop)
    f.edge = .managerButton
    #expect(f.atTop)
}

@Test func trackerKeepsTopForGracePeriod() {
    var t = TopEdgeTracker()
    #expect(!t.wasAtTop(now: 0))
    let entered = t.set(true, now: 1)
    #expect(entered)
    let again = t.set(true, now: 1.1)
    #expect(!again)                  // no change
    #expect(t.wasAtTop(now: 5))
    let left = t.set(false, now: 10)
    #expect(left)
    #expect(t.wasAtTop(now: 10.2))
    #expect(t.wasAtTop(now: 10.29))
    #expect(!t.wasAtTop(now: 10.5))
    t.set(true, now: 11)
    #expect(t.leftAt == nil)
}

@Test func barIsRequestedAtTheTopEdgeInTheBarOrAtTheTopPosition() {
    let rest = HomeTopRules.restOffset
    // Top edge focused: always, whatever the offset.
    #expect(HomeTopRules.barRequest(atTop: true, inBar: false, offset: 900, navigation: .top) == .visible)
    // Focus in the bar: held even when the page is scrolled.
    #expect(HomeTopRules.barRequest(atTop: false, inBar: true, offset: 900, navigation: .top) == .visible)
    // Page at its top position (residual padding): held, beyond it the system decides.
    #expect(HomeTopRules.barRequest(atTop: false, inBar: false, offset: 0, navigation: .top) == .visible)
    #expect(HomeTopRules.barRequest(atTop: false, inBar: false, offset: rest, navigation: .top) == .visible)
    #expect(HomeTopRules.barRequest(atTop: false, inBar: false, offset: rest + 0.1, navigation: .top) == .automatic)
    #expect(HomeTopRules.barRequest(atTop: false, inBar: false, offset: 900, navigation: .top) == .automatic)
    // Sidebar: never.
    #expect(HomeTopRules.barRequest(atTop: true, inBar: true, offset: 0, navigation: .sidebar) == .automatic)
}

/// Review F-j I1: "Abspielen" → up into the bar. The top edge loses focus the moment the bar gains it; the request
/// must stay `.visible` through that step and only drop once the page scrolls down with the focus in the content.
@Test func barRequestSurvivesTheMoveFromTheTopEdgeIntoTheBar() {
    struct Step { let atTop: Bool; let inBar: Bool; let offset: Double }
    let steps = [
        Step(atTop: true, inBar: false, offset: 24),    // "Abspielen" focused, residual padding
        Step(atTop: false, inBar: false, offset: 24),   // focus left the button, bar not yet reported
        Step(atTop: false, inBar: true, offset: 24),    // focus in the bar
        Step(atTop: false, inBar: true, offset: 24),    // left/right inside the bar
        Step(atTop: true, inBar: false, offset: 24),    // back down to "Abspielen"
        Step(atTop: false, inBar: false, offset: 420),  // down into the rows, page scrolled
    ]
    let requests = steps.map { HomeTopRules.barRequest(atTop: $0.atTop, inBar: $0.inBar, offset: $0.offset, navigation: .top) }
    #expect(requests == [.visible, .visible, .visible, .visible, .visible, .automatic])
    // Even if the bar is not recognised (inBar stays false), the unchanged offset holds the request.
    #expect(HomeTopRules.barRequest(atTop: false, inBar: false, offset: 24, navigation: .top) == .visible)
}

@Test func scrollToTopOnlyWhenNeeded() {
    let rest = HomeTopRules.restOffset
    // Bar off screen: snap whenever not exactly at the top.
    #expect(HomeTopRules.shouldScrollToTop(atTop: true, offset: 24, barOnScreen: false, navigation: .top))
    #expect(HomeTopRules.shouldScrollToTop(atTop: true, offset: 0.6, barOnScreen: false, navigation: .top))
    #expect(!HomeTopRules.shouldScrollToTop(atTop: true, offset: 0.4, barOnScreen: false, navigation: .top))
    #expect(!HomeTopRules.shouldScrollToTop(atTop: true, offset: -2, barOnScreen: false, navigation: .top))
    // Review F-j M1: bar on screen, residual padding is left alone (no shift of its own), more is snapped.
    #expect(!HomeTopRules.shouldScrollToTop(atTop: true, offset: 24, barOnScreen: true, navigation: .top))
    #expect(!HomeTopRules.shouldScrollToTop(atTop: true, offset: rest, barOnScreen: true, navigation: .top))
    #expect(HomeTopRules.shouldScrollToTop(atTop: true, offset: rest + 1, barOnScreen: true, navigation: .top))
    // Not at the top edge or with the sidebar: never.
    #expect(!HomeTopRules.shouldScrollToTop(atTop: false, offset: 500, barOnScreen: false, navigation: .top))
    #expect(!HomeTopRules.shouldScrollToTop(atTop: true, offset: 500, barOnScreen: false, navigation: .sidebar))
}

@Test func tabBarStateSummary() {
    #expect(TabBarState.notFound.summary == "nicht gefunden")
    #expect(!TabBarState.notFound.onScreen)
    let visible = TabBarState(found: true, minY: 0, maxY: 140)
    #expect(visible.onScreen)
    #expect(visible.summary == "sichtbar (y 0…140)")
    #expect(TabBarState(found: true, alpha: 0.5, minY: 0, maxY: 140).summary == "sichtbar (y 0…140, Alpha 0.50)")
    let hidden = TabBarState(found: true, hidden: true, minY: 0, maxY: 140)
    #expect(!hidden.onScreen)
    #expect(hidden.summary == "versteckt (isHidden)")
    let controller = TabBarState(found: true, hidden: true, controllerHidden: true, minY: 0, maxY: 140)
    #expect(controller.summary == "versteckt (Controller)")
    let transparent = TabBarState(found: true, alpha: 0, minY: 0, maxY: 140)
    #expect(!transparent.onScreen)
    #expect(transparent.summary == "unsichtbar (Alpha 0.00)")
    let above = TabBarState(found: true, minY: -140, maxY: 0)
    #expect(!above.onScreen)
    #expect(above.summary == "außerhalb des Bildes (y -140…0)")
    let partly = TabBarState(found: true, minY: -100, maxY: 40)
    #expect(partly.onScreen)
}

@Test func arrivedLine() {
    let bar = TabBarState(found: true, minY: -140, maxY: 0)
    #expect(TabBarReachLog.arrived(edge: .heroButtons, offset: 24, scrolledToTop: true, bar: bar, request: .visible,
                                   navigation: .top)
            == "Oberer Rand fokussiert (Knopfzeile) · Versatz 24 pt → nach ganz oben · Leiste außerhalb des Bildes (y -140…0) · Leiste angefordert · Menü oben")
    #expect(TabBarReachLog.arrived(edge: .firstRow, offset: 0, scrolledToTop: false, bar: .notFound, request: .automatic,
                                   navigation: .sidebar)
            == "Oberer Rand fokussiert (erste Reihe) · Versatz 0 pt · Leiste nicht gefunden · Seitenleiste")
}

@Test func upLines() {
    let bar = TabBarState(found: true, hidden: true, minY: 0, maxY: 140)
    #expect(TabBarReachLog.up(.reachedBar, atTop: true, edge: .heroButtons, bar: bar, offset: 0, navigation: .top)
            == "Hoch am oberen Rand → Leiste erreicht · Menü oben")
    #expect(TabBarReachLog.up(.failed, atTop: true, edge: .heroButtons, bar: bar, offset: 3.6, navigation: .top)
            == "Hoch am oberen Rand → Leiste nicht erreichbar (kein Ziel) · Leiste versteckt (isHidden) · Versatz 4 pt · Menü oben")
    #expect(TabBarReachLog.up(.stayedInContent("Button"), atTop: true, edge: .firstRow, bar: bar, offset: 0,
                              navigation: .top)
            == "Hoch am oberen Rand → Leiste nicht erreicht, Fokus blieb im Inhalt (Button) · Leiste versteckt (isHidden) · Versatz 0 pt · Menü oben")
    // Away from the top only failures are logged.
    #expect(TabBarReachLog.up(.stayedInContent("Button"), atTop: false, edge: .heroButtons, bar: bar, offset: 900,
                              navigation: .top) == nil)
    #expect(TabBarReachLog.up(.reachedBar, atTop: false, edge: .heroButtons, bar: bar, offset: 900, navigation: .top) == nil)
    #expect(TabBarReachLog.up(.failed, atTop: false, edge: .heroButtons, bar: bar, offset: 900, navigation: .top)
            == "Hoch gescheitert, nicht am oberen Rand (oben: Knopfzeile) · Leiste versteckt (isHidden) · Versatz 900 pt · Menü oben")
}

@Test func upMovesLoggedAndKeyedByCase() {
    #expect(TabBarReachLog.logs(.reachedBar, atTop: true))
    #expect(TabBarReachLog.logs(.stayedInContent("x"), atTop: true))
    #expect(TabBarReachLog.logs(.failed, atTop: false))
    #expect(!TabBarReachLog.logs(.reachedBar, atTop: false))
    #expect(!TabBarReachLog.logs(.stayedInContent("x"), atTop: false))
    // Review F-j M3: the throttle key ignores the description (target type and y position).
    #expect(TabBarReachLog.UpOutcome.stayedInContent("A, y 40").kind == TabBarReachLog.UpOutcome.stayedInContent("B, y 300").kind)
    let all: [TabBarReachLog.UpOutcome] = [.reachedBar, .stayedInContent("x"), .failed]
    #expect(Set(all.map(\.kind)).count == 3)
}

@Test func autostartWaitsForThePushTransition() {
    let settle = AutostartAfterPush.settleMs
    // Cache hit as in the log: player wanted 143 ms after the push → wait the rest.
    #expect(AutostartAfterPush.remainingWait(elapsedMs: 143) == settle - 143)
    #expect(AutostartAfterPush.remainingWait(elapsedMs: 0) == settle)
    #expect(AutostartAfterPush.remainingWait(elapsedMs: -5) == settle)
    // Slow search: the transition is long over, no extra wait.
    #expect(AutostartAfterPush.remainingWait(elapsedMs: settle) == 0)
    #expect(AutostartAfterPush.remainingWait(elapsedMs: 8400) == 0)
    // Longer than the tvOS push animation (about 0.5 s), short enough not to feel slow.
    #expect(settle >= 600 && settle <= 1000)
}

@Test func throttleAllowsOneLinePerKeyAndInterval() {
    var t = LogThrottle(interval: 1)
    var results: [Bool] = []
    for (key, now) in [("a", 0.0), ("a", 0.5), ("b", 0.5), ("a", 1.0), ("a", 1.9)] {
        results.append(t.allow(key, now: now))
    }
    #expect(results == [true, false, true, true, false])
}

// MARK: Stuck tab bar (wave F-m)

/// Bar position from the build 198 device log after the player: it followed the source list (row 11) off screen.
private let stuckBar = TabBarState(found: true, minY: -2250, maxY: -2182)

@Test func barStuckAfterThePlayerIsDetectedWithTheLoggedValues() {
    // 8F2D5F48: button row focused, offset 7 → 2 pt, bar at −2250: stuck.
    #expect(HomeTopRules.barStranded(stuckBar, atTop: true, offset: 7, navigation: .top))
    #expect(HomeTopRules.barStranded(stuckBar, atTop: true, offset: 2, navigation: .top))
    // 55679472: focus in the rows, offsets 429 / 207 pt: still far beyond what the page offset explains.
    #expect(HomeTopRules.barStranded(stuckBar, atTop: false, offset: 429, navigation: .top))
    #expect(HomeTopRules.barStranded(stuckBar, atTop: false, offset: 207, navigation: .top))
    // Sidebar: the tab bar is not the menu, nothing to repair.
    #expect(!HomeTopRules.barStranded(stuckBar, atTop: true, offset: 0, navigation: .sidebar))
}

@Test func barHiddenByScrollingIsNotStuck() {
    // Healthy bar on screen at the top position.
    let shown = TabBarState(found: true, minY: 46, maxY: 114)
    #expect(!HomeTopRules.barStranded(shown, atTop: true, offset: 0, navigation: .top))
    // Scrolled down 900 pt, the bar slid off with the page (at most one to one): normal.
    #expect(!HomeTopRules.barStranded(TabBarState(found: true, minY: -114, maxY: -46), atTop: false, offset: 900,
                                      navigation: .top))
    #expect(!HomeTopRules.barStranded(TabBarState(found: true, minY: -854, maxY: -786), atTop: false, offset: 900,
                                      navigation: .top))
    // Hidden on purpose (isHidden / controller): left alone.
    #expect(!HomeTopRules.barStranded(TabBarState(found: true, hidden: true, minY: -2250, maxY: -2182), atTop: true,
                                      offset: 0, navigation: .top))
    #expect(!HomeTopRules.barStranded(TabBarState(found: true, controllerHidden: true, minY: -2250, maxY: -2182),
                                      atTop: true, offset: 0, navigation: .top))
    #expect(!HomeTopRules.barStranded(.notFound, atTop: true, offset: 0, navigation: .top))
}

@Test func barOffScreenAtTheTopPositionIsStuck() {
    // At the top position (focus on the top edge or offset within the rest offset) the bar belongs on screen.
    let justAbove = TabBarState(found: true, minY: -140, maxY: 0)
    #expect(HomeTopRules.barStranded(justAbove, atTop: true, offset: 300, navigation: .top))
    #expect(HomeTopRules.barStranded(justAbove, atTop: false, offset: HomeTopRules.restOffset, navigation: .top))
    #expect(!HomeTopRules.barStranded(justAbove, atTop: false, offset: HomeTopRules.restOffset + 1, navigation: .top))
}

@Test func repairStepsRunOnceEachAndReshowOnlyAtRest() {
    #expect(TabBarRepair.next(after: nil, atRest: false) == .rebind)
    #expect(TabBarRepair.next(after: nil, atRest: true) == .rebind)
    // Showing the bar while scrolled down would cover the rows: the second step waits for the top position.
    #expect(TabBarRepair.next(after: .rebind, atRest: false) == nil)
    #expect(TabBarRepair.next(after: .rebind, atRest: true) == .reshow)
    #expect(TabBarRepair.next(after: .reshow, atRest: true) == nil)
    // Checks start after the pop transition and before a hurried second press up.
    #expect(TabBarRepair.appearMilliseconds >= 500 && TabBarRepair.appearMilliseconds <= 1000)
    #expect(TabBarRepair.checkMilliseconds >= 200 && TabBarRepair.checkMilliseconds <= 500)
}

@Test func repairLines() {
    let fixed = TabBarState(found: true, minY: 46, maxY: 114)
    #expect(TabBarReachLog.repaired(.rebind, trigger: .appeared, applied: true, before: stuckBar, after: fixed, offset: 7,
                                    observed: "keine", navigation: .top)
            == "Leiste hing fest (nach dem Erscheinen): außerhalb des Bildes (y -2250…-2182) · Versatz 7 pt · beobachtet keine → an die Startseite gebunden · danach Leiste sichtbar (y 46…114) · Menü oben")
    #expect(TabBarReachLog.repaired(.reshow, trigger: .upFailed, applied: false, before: stuckBar, after: stuckBar,
                                    offset: 0, observed: "Startseite", navigation: .top)
            == "Leiste hing fest (nach gescheitertem Hoch): außerhalb des Bildes (y -2250…-2182) · Versatz 0 pt · beobachtet Startseite → über den Controller neu eingeblendet nicht möglich · danach Leiste außerhalb des Bildes (y -2250…-2182) · Menü oben")
    #expect(TabBarReachLog.repairExhausted(bar: stuckBar, offset: 0, navigation: .top)
            == "Leiste hängt weiter, keine Reparatur mehr in diesem Besuch · Leiste außerhalb des Bildes (y -2250…-2182) · Versatz 0 pt · Menü oben")
    #expect(TabBarRepair.Trigger.arrivedAtTop.logName == "am oberen Rand")
}
