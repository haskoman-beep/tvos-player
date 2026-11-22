import Testing
@testable import PlayerCore

// MARK: Menu-Kette (N1/N2)

@Test func menuChainStartTabLeavesOnlyFromTabBar() {
    #expect(MenuChain.target(.tabRoot, tab: .home) == .system)
    #expect(MenuChain.target(.tabBar, tab: .home) == .leaveApp)
    #expect(MenuChain.target(.leftColumn, tab: .home) == .system)
}

@Test func menuChainOtherTabsGoToStartFirst() {
    for tab in AppTab.allCases where tab != .home {
        #expect(MenuChain.target(.tabRoot, tab: tab) == .startTab)
        #expect(MenuChain.target(.tabBar, tab: tab) == .startTab)
        #expect(MenuChain.target(.leftColumn, tab: tab) == .startTab)
    }
}

@Test func menuChainInnerLevelsStepOneBack() {
    for tab in AppTab.allCases {
        #expect(MenuChain.target(.sheet, tab: tab) == .system)
        #expect(MenuChain.target(.pushedPage, tab: tab) == .system)
        #expect(MenuChain.target(.rightColumn, tab: tab) == .activeCategory)
    }
}

@Test func menuChainTabLevelOnlyAtRootOfNonStartTabs() {
    #expect(MenuChain.handlesAtTabLevel(tab: .search, depth: 0))
    #expect(MenuChain.handlesAtTabLevel(tab: .settings, depth: 0))
    #expect(!MenuChain.handlesAtTabLevel(tab: .search, depth: 1))
    #expect(!MenuChain.handlesAtTabLevel(tab: .library, depth: 3))
    #expect(!MenuChain.handlesAtTabLevel(tab: .home, depth: 0))
    #expect(!MenuChain.handlesAtTabLevel(tab: .home, depth: 2))
}

@Test func appTabLogNamesAreGerman() {
    #expect(AppTab.home.logName == "Start")
    #expect(AppTab.calendar.logName == "Kalender")
}

// MARK: Folge nach dem Player

private func ep(_ s: Int, _ e: Int) -> EpisodeRef { EpisodeRef(season: s, episode: e) }
private let twoSeasons = [ep(1, 1), ep(1, 2), ep(1, 3), ep(2, 1), ep(2, 2)]

@Test func episodeFocusStaysOnUnfinishedAnchor() {
    let watched: Set<EpisodeRef> = [ep(1, 1)]
    #expect(EpisodeFocus.target(episodes: twoSeasons, anchor: ep(1, 2), isWatched: watched.contains) == ep(1, 2))
}

@Test func episodeFocusMovesToNextUnwatched() {
    let watched: Set<EpisodeRef> = [ep(1, 1), ep(1, 2)]
    #expect(EpisodeFocus.target(episodes: twoSeasons, anchor: ep(1, 2), isWatched: watched.contains) == ep(1, 3))
}

@Test func episodeFocusCrossesSeasonBoundary() {
    let watched: Set<EpisodeRef> = [ep(1, 3)]
    #expect(EpisodeFocus.target(episodes: twoSeasons, anchor: ep(1, 3), isWatched: watched.contains) == ep(2, 1))
    // Gesehene Folgen am Anfang der neuen Staffel werden übersprungen.
    let more: Set<EpisodeRef> = [ep(1, 3), ep(2, 1)]
    #expect(EpisodeFocus.target(episodes: twoSeasons, anchor: ep(1, 3), isWatched: more.contains) == ep(2, 2))
}

@Test func episodeFocusAfterAutoplaySkipsWatchedRun() {
    // Gestartet bei 1×1, Autoplay lief bis 2×1 (gesehen); Fortschritt zeigt 2×1 als letzte.
    let watched: Set<EpisodeRef> = [ep(1, 1), ep(1, 2), ep(1, 3), ep(2, 1)]
    #expect(EpisodeFocus.target(episodes: twoSeasons, anchor: ep(2, 1), isWatched: watched.contains) == ep(2, 2))
}

@Test func episodeFocusAtSeriesEnd() {
    let gap: Set<EpisodeRef> = [ep(1, 2), ep(1, 3), ep(2, 1), ep(2, 2)]
    #expect(EpisodeFocus.target(episodes: twoSeasons, anchor: ep(2, 2), isWatched: gap.contains) == ep(1, 1))
    let all = Set(twoSeasons)
    #expect(EpisodeFocus.target(episodes: twoSeasons, anchor: ep(2, 2), isWatched: all.contains) == ep(2, 2))
    // Anker nicht (mehr) in der Liste, alles gesehen: letzte Folge.
    #expect(EpisodeFocus.target(episodes: twoSeasons, anchor: ep(3, 1), isWatched: all.contains) == ep(2, 2))
}

@Test func episodeFocusWithoutAnchor() {
    #expect(EpisodeFocus.target(episodes: twoSeasons, anchor: nil, isWatched: { _ in false }) == ep(1, 1))
    let watched: Set<EpisodeRef> = [ep(1, 1)]
    #expect(EpisodeFocus.target(episodes: twoSeasons, anchor: nil, isWatched: watched.contains) == ep(1, 2))
    #expect(EpisodeFocus.target(episodes: [], anchor: ep(1, 1), isWatched: { _ in false }) == nil)
}

@Test func episodeFocusIgnoresTitleWhenMatching() {
    let list = [EpisodeRef(season: 1, episode: 1, title: "Pilot"), EpisodeRef(season: 1, episode: 2, title: "Zwei")]
    #expect(EpisodeFocus.target(episodes: list, anchor: ep(1, 1), isWatched: { _ in false })?.title == "Pilot")
}

// MARK: Quellenliste

@Test func sourceFocusEntryPrefersLastPlayed() {
    let ids = ["a", "b", "c"]
    #expect(SourceFocus.entry(ids: ids, lastPlayed: "c", isPlayable: { _ in true }) == "c")
    #expect(SourceFocus.entry(ids: ids, lastPlayed: "x", isPlayable: { $0 != "a" }) == "b")
    #expect(SourceFocus.entry(ids: ids, lastPlayed: nil, isPlayable: { _ in false }) == "a")
    #expect(SourceFocus.entry(ids: [], lastPlayed: "a", isPlayable: { _ in true }) == nil)
}

@Test func sourceFocusAfterNormalEndStaysOnPlayed() {
    #expect(SourceFocus.afterPlayer(ids: ["a", "b", "c"], played: "b", failed: false, isPlayable: { _ in true }) == "b")
}

@Test func sourceFocusAfterFailureGoesBelow() {
    let ids = ["a", "b", "c", "d"]
    #expect(SourceFocus.afterPlayer(ids: ids, played: "b", failed: true, isPlayable: { $0 != "b" }) == "c")
    // Unspielbare bzw. schon gescheiterte darunter werden übersprungen.
    #expect(SourceFocus.afterPlayer(ids: ids, played: "b", failed: true, isPlayable: { $0 == "a" || $0 == "d" }) == "d")
}

@Test func sourceFocusAfterFailureAtBottom() {
    let ids = ["a", "b", "c"]
    #expect(SourceFocus.afterPlayer(ids: ids, played: "c", failed: true, isPlayable: { $0 == "b" }) == "b")
    #expect(SourceFocus.afterPlayer(ids: ids, played: "c", failed: true, isPlayable: { _ in false }) == "c")
}

@Test func sourceFocusAfterPlayerWithChangedList() {
    // Liste zeigt inzwischen eine andere Folge: Eintrittsregel.
    #expect(SourceFocus.afterPlayer(ids: ["x", "y"], played: "b", failed: true, isPlayable: { $0 == "y" }) == "y")
}

// MARK: Player-Menu (N5)

@Test func playerMenuClosesOverlaysFirst() {
    #expect(PlayerMenuStep.decide(upNext: true, controlsVisible: true, hasPicture: true, failed: false) == .cancelUpNext)
    #expect(PlayerMenuStep.decide(upNext: false, controlsVisible: true, hasPicture: true, failed: false) == .hideControls)
    #expect(PlayerMenuStep.decide(upNext: false, controlsVisible: false, hasPicture: true, failed: false) == .leave)
}

@Test func playerMenuLeavesWhileLoadingOrFailed() {
    #expect(PlayerMenuStep.decide(upNext: false, controlsVisible: true, hasPicture: false, failed: false) == .leave)
    #expect(PlayerMenuStep.decide(upNext: true, controlsVisible: true, hasPicture: true, failed: true) == .leave)
}
