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

@Test func barIsRequestedOnlyAtTopWithTopNavigation() {
    #expect(HomeTopRules.barRequest(atTop: true, navigation: .top) == .visible)
    #expect(HomeTopRules.barRequest(atTop: false, navigation: .top) == .automatic)
    #expect(HomeTopRules.barRequest(atTop: true, navigation: .sidebar) == .automatic)
    #expect(HomeTopRules.barRequest(atTop: false, navigation: .sidebar) == .automatic)
}

@Test func scrollToTopOnlyWhenAtTopAndNotScrolledFully() {
    #expect(HomeTopRules.shouldScrollToTop(atTop: true, offset: 24, navigation: .top))
    #expect(HomeTopRules.shouldScrollToTop(atTop: true, offset: 0.6, navigation: .top))
    #expect(!HomeTopRules.shouldScrollToTop(atTop: true, offset: 0.4, navigation: .top))
    #expect(!HomeTopRules.shouldScrollToTop(atTop: true, offset: -2, navigation: .top))
    #expect(!HomeTopRules.shouldScrollToTop(atTop: false, offset: 500, navigation: .top))
    #expect(!HomeTopRules.shouldScrollToTop(atTop: true, offset: 500, navigation: .sidebar))
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

@Test func throttleAllowsOneLinePerKeyAndInterval() {
    var t = LogThrottle(interval: 1)
    var results: [Bool] = []
    for (key, now) in [("a", 0.0), ("a", 0.5), ("b", 0.5), ("a", 1.0), ("a", 1.9)] {
        results.append(t.allow(key, now: now))
    }
    #expect(results == [true, false, true, true, false])
}
