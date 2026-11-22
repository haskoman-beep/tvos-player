import Foundation
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
    #expect(HomeTopRules.barStranded(stuckBar, offset: 7, navigation: .top))
    #expect(HomeTopRules.barStranded(stuckBar, offset: 2, navigation: .top))
    // 55679472: focus in the rows, offsets 429 / 207 pt: still far beyond what the page offset explains.
    #expect(HomeTopRules.barStranded(stuckBar, offset: 429, navigation: .top))
    #expect(HomeTopRules.barStranded(stuckBar, offset: 207, navigation: .top))
    // A6EE9200 (Library): detail page or grid back at the top, same bar.
    #expect(HomeTopRules.barStranded(stuckBar, offset: 0, navigation: .top))
    // Sidebar: the tab bar is not the menu, nothing to repair.
    #expect(!HomeTopRules.barStranded(stuckBar, offset: 0, navigation: .sidebar))
}

@Test func barHiddenByScrollingIsNotStuck() {
    // Healthy bar on screen at the top position.
    let shown = TabBarState(found: true, minY: 46, maxY: 114)
    #expect(!HomeTopRules.barStranded(shown, offset: 0, navigation: .top))
    // Scrolled down 900 pt, the bar slid off with the page (at most one to one): normal.
    #expect(!HomeTopRules.barStranded(TabBarState(found: true, minY: -114, maxY: -46), offset: 900, navigation: .top))
    #expect(!HomeTopRules.barStranded(TabBarState(found: true, minY: -854, maxY: -786), offset: 900, navigation: .top))
    // Source list after the player (row 11, about 2300 pt): the bar follows it, that is not stuck.
    #expect(!HomeTopRules.barStranded(stuckBar, offset: 2296, navigation: .top))
    // Hidden on purpose (isHidden / controller): left alone.
    #expect(!HomeTopRules.barStranded(TabBarState(found: true, hidden: true, minY: -2250, maxY: -2182), offset: 0,
                                      navigation: .top))
    #expect(!HomeTopRules.barStranded(TabBarState(found: true, controllerHidden: true, minY: -2250, maxY: -2182),
                                      offset: 0, navigation: .top))
    #expect(!HomeTopRules.barStranded(.notFound, offset: 0, navigation: .top))
}

@Test func barSlidAwayByAShortScrollIsNotStuck() {
    // Review F-m M4: tvOS slides the bar off after a short scroll; up then fails at offset 30-60 (row 1 at the
    // bottom of the hero info). That bar is healthy and must not be shown over the hero info.
    let slidOff = TabBarState(found: true, minY: -140, maxY: 0)
    #expect(!HomeTopRules.barStranded(slidOff, offset: 30, navigation: .top))
    #expect(!HomeTopRules.barStranded(slidOff, offset: 0, navigation: .top))
    // The limit: further up than the offset explains by more than the tolerance.
    let limit = HomeTopRules.barRestTop - 60 - HomeTopRules.strandTolerance
    #expect(!HomeTopRules.barStranded(TabBarState(found: true, minY: limit, maxY: limit + 68), offset: 60, navigation: .top))
    #expect(HomeTopRules.barStranded(TabBarState(found: true, minY: limit - 1, maxY: limit + 67), offset: 60, navigation: .top))
}

@Test func repairStepsRunOnceEachPerVisitAlsoWhileScrolledDown() {
    // Review F-m I1: the reshow follows the rebind at any offset (no dead end while scrolled down).
    #expect(TabBarRepair.next(after: nil) == .rebind)
    #expect(TabBarRepair.next(after: .rebind) == .reshow)
    #expect(TabBarRepair.next(after: .reshow) == nil)
    // A pop or the closed player starts a new visit; the focus triggers continue the current one.
    #expect(TabBarRepair.Trigger.popped.startsVisit && TabBarRepair.Trigger.playerClosed.startsVisit)
    #expect(!TabBarRepair.Trigger.upFailed.startsVisit && !TabBarRepair.Trigger.arrivedAtTop.startsVisit)
    // Checks start after the pop transition, after the source list's focus move, and at once on a focus event.
    #expect(TabBarRepair.Trigger.popped.delayMilliseconds >= 500 && TabBarRepair.Trigger.popped.delayMilliseconds <= 1000)
    #expect(TabBarRepair.Trigger.playerClosed.delayMilliseconds > TabBarRepair.Trigger.popped.delayMilliseconds)
    #expect(TabBarRepair.Trigger.upFailed.delayMilliseconds == 0)
    #expect(TabBarRepair.checkMilliseconds >= 200 && TabBarRepair.checkMilliseconds <= 500)
}

@Test func repairLines() {
    let fixed = TabBarState(found: true, minY: 46, maxY: 114)
    #expect(TabBarReachLog.repaired(.rebind, trigger: .popped, page: "Bibliothek, Tiefe 1", applied: true, before: stuckBar,
                                    after: fixed, offset: 7, observed: "keine", navigation: .top)
            == "Leiste hing fest (nach dem Zurückgehen, Bibliothek, Tiefe 1): außerhalb des Bildes (y -2250…-2182) · Versatz 7 pt · beobachtet keine → an die Seite gebunden · danach Leiste sichtbar (y 46…114) · Menü oben")
    #expect(TabBarReachLog.repaired(.reshow, trigger: .upFailed, page: "Start, Tiefe 0", applied: false, before: stuckBar,
                                    after: stuckBar, offset: 207, observed: "Seite", navigation: .top)
            == "Leiste hing fest (nach gescheitertem Hoch, Start, Tiefe 0): außerhalb des Bildes (y -2250…-2182) · Versatz 207 pt · beobachtet Seite → über den Controller neu eingeblendet nicht möglich · danach Leiste außerhalb des Bildes (y -2250…-2182) · Menü oben")
    #expect(TabBarReachLog.repairExhausted(trigger: .upFailed, page: "Start, Tiefe 0", bar: stuckBar, offset: 207, navigation: .top)
            == "Leiste hängt weiter (nach gescheitertem Hoch, Start, Tiefe 0), alle Reparaturen versucht · Leiste außerhalb des Bildes (y -2250…-2182) · Versatz 207 pt · Menü oben")
    #expect(TabBarRepair.Trigger.arrivedAtTop.logName == "am oberen Rand")
    #expect(TabBarRepair.Trigger.playerClosed.logName == "nach dem Player")
}

@Test func pageScrollPickIgnoresHorizontalRowsAndOffscreenParts() {
    let window = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    // Hero home (review N-I1): list 470…1041 (571 pt) and a hero row strip of 738 pt, full width, partly below.
    let list = PageScrollPick.Candidate(frame: CGRect(x: 0, y: 470, width: 1920, height: 571),
                                        contentSize: CGSize(width: 1920, height: 4000), alwaysBounceVertical: true)
    let heroRow = PageScrollPick.Candidate(frame: CGRect(x: 0, y: 900, width: 1920, height: 738),
                                           contentSize: CGSize(width: 9000, height: 738))
    #expect(PageScrollPick.choose([heroRow, list], window: window) == 1)
    // A row that would scroll vertically but lies mostly below the screen loses by its visible part.
    let lowTall = PageScrollPick.Candidate(frame: CGRect(x: 0, y: 700, width: 1920, height: 2000),
                                           contentSize: CGSize(width: 1920, height: 3000))
    #expect(PageScrollPick.choose([lowTall, list], window: window) == 1)
    // Large posters with badges below: strip as tall as the list, still not vertical.
    let strip = PageScrollPick.Candidate(frame: CGRect(x: 0, y: 470, width: 1920, height: 562),
                                         contentSize: CGSize(width: 8000, height: 562))
    #expect(PageScrollPick.choose([strip, list], window: window) == 1)
    // The list handed over by the page wins over a larger vertical one; nothing vertical → nil.
    var known = list
    known.known = true
    let grid = PageScrollPick.Candidate(frame: window, contentSize: CGSize(width: 1920, height: 5000))
    #expect(PageScrollPick.choose([grid, known], window: window) == 1)
    #expect(PageScrollPick.choose([grid, list], window: window) == 0)
    #expect(PageScrollPick.choose([heroRow, strip], window: window) == nil)
    // Detail page whose content fits: counts only with vertical bounce.
    let fits = PageScrollPick.Candidate(frame: window, contentSize: CGSize(width: 1920, height: 1080))
    #expect(PageScrollPick.choose([fits], window: window) == nil)
    #expect(PageScrollPick.choose([PageScrollPick.Candidate(frame: window, contentSize: window.size, alwaysBounceVertical: true)],
                                  window: window) == 0)
}
