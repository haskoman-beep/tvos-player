import Foundation
import Testing
@testable import PlayerCore

// Wave P-b: player side panel and pause card.

@Test func sidePanelEntriesLeaveOutEmptyParts() {
    let movie = SidePanelMenu.entries(SidePanelAvailability())
    #expect(movie.map(\.page) == [.info])
    #expect(movie[0].detail == "Technik der laufenden Quelle")

    let full = SidePanelMenu.entries(SidePanelAvailability(episodeCount: 20, seasonCount: 2, currentSeason: 1, currentEpisode: 3,
                                                           chapterCount: 8, currentChapter: "Ankunft", sourceCount: 5,
                                                           infoSummary: "4K · Dolby Vision"))
    #expect(full.map(\.page) == [.episodes, .chapters, .sources, .info])
    #expect(full[0].detail == "S1 F3 · 2 Staffeln")
    #expect(full[1].detail == "Ankunft · 8 Kapitel")
    #expect(full[2].detail == "4 weitere")
    #expect(full[3].detail == "4K · Dolby Vision")

    // Only the running source, or one episode: no entry.
    let lone = SidePanelMenu.entries(SidePanelAvailability(episodeCount: 1, chapterCount: 1, sourceCount: 1))
    #expect(lone.map(\.page) == [.chapters, .info])
    #expect(lone[0].detail == "1 Kapitel")
    #expect(SidePanelMenu.entries(SidePanelAvailability(episodeCount: 10, seasonCount: 1))[0].detail == "10 Folgen")
    #expect(SidePanelMenu.entries(SidePanelAvailability(sourceCount: 2))[0].detail == "1 weitere")
}

@Test func sidePanelTakesTheFreeVerticalGesture() {
    // Track panel gestures from build 198 stay; the side panel gets the other direction.
    #expect(SidePanelGesture.opens(trackStyle: .topBar, gesture: .swipeUp))
    #expect(SidePanelGesture.opens(trackStyle: .topBar, gesture: .clickUp))
    #expect(!SidePanelGesture.opens(trackStyle: .topBar, gesture: .swipeDown))
    #expect(!SidePanelGesture.opens(trackStyle: .topBar, gesture: .clickDown))
    for style in [TrackPanelStyle.bottomBar, .menu] {
        #expect(SidePanelGesture.opens(trackStyle: style, gesture: .swipeDown))
        #expect(SidePanelGesture.opens(trackStyle: style, gesture: .clickDown))
        #expect(!SidePanelGesture.opens(trackStyle: style, gesture: .swipeUp))
        #expect(!SidePanelGesture.opens(trackStyle: style, gesture: .clickUp))
    }
    // Never both panels for one gesture.
    for style in TrackPanelStyle.allCases {
        for g in [TrackPanelGesture.swipeDown, .swipeUp, .clickDown, .clickUp] {
            #expect(SidePanelGesture.opens(trackStyle: style, gesture: g) != TrackPanelEntry.opens(style: style, gesture: g))
        }
    }
    #expect(!SidePanelGesture.opensDownward(trackStyle: .topBar))
    #expect(SidePanelGesture.opensDownward(trackStyle: .menu))
}

@Test func sidePanelGuardStyleRunsTheTrackPanelGuards() {
    for g in [TrackPanelGesture.swipeDown, .swipeUp, .clickDown, .clickUp] {
        let style = SidePanelGesture.guardStyle(for: g)
        #expect(TrackPanelEntry.opens(style: style, gesture: g))
        #expect(TrackPanelEntry.decide(style: style, gesture: g, leaving: false, scrubbing: false, upNextShowing: false,
                                       failureShowing: false, alreadyOpen: false, skipPromptShowing: false, lock: nil) == .open)
        // Skip button showing: it keeps the focus, the side panel does not open either.
        #expect(TrackPanelEntry.decide(style: style, gesture: g, leaving: false, scrubbing: false, upNextShowing: false,
                                       failureShowing: false, alreadyOpen: false, skipPromptShowing: true, lock: nil) == .ignore(.skipPrompt))
    }
}

@Test func sidePanelHintFollowsTheGesture() {
    #expect(SidePanelMenu.hint(trackStyle: .topBar, pages: [.chapters, .info]) == "▲ Kapitel · Infos")
    #expect(SidePanelMenu.hint(trackStyle: .bottomBar, pages: [.episodes, .sources, .info]) == "▼ Folgen · Quelle · Infos")
    #expect(SidePanelMenu.hint(trackStyle: .topBar, pages: [.info]) == nil)
}

@Test func sidePanelNavIsAStackOfOne() {
    let entries = SidePanelMenu.entries(SidePanelAvailability(chapterCount: 3, sourceCount: 4))
    var nav = SidePanelNav(entries: entries)
    #expect(nav.page == nil && nav.listFocus == .chapters)
    nav.open(.sources)
    #expect(nav.page == .sources)
    #expect(nav.back() == .toList)
    #expect(nav.page == nil && nav.listFocus == .sources)
    #expect(nav.back() == .close)
}

@Test func sideChapterRowsMarkTheCurrentChapter() {
    let marks = [ChapterMark(name: "Ende", start: 3000, duration: 0),
                 ChapterMark(name: "", start: 0, duration: 0),
                 ChapterMark(name: "Chapter 02", start: 600, duration: 0),
                 ChapterMark(name: "Ankunft", start: 1200, duration: 0)]
    let rows = SideChapters.rows(marks, position: 1300)
    #expect(rows.map(\.title) == ["Kapitel 1", "Kapitel 2", "Ankunft", "Ende"])
    #expect(rows.map(\.time) == ["0:00", "10:00", "20:00", "50:00"])
    #expect(rows.filter(\.isCurrent).map(\.title) == ["Ankunft"])
    #expect(SideChapters.currentIndex(marks, position: 3600) == 0)
    #expect(SideChapters.currentIndex([ChapterMark(name: "a", start: 10, duration: 0)], position: 5) == nil)
    #expect(SideChapters.displayName("00:05:00.000", number: 4) == "Kapitel 4")
    #expect(SideChapters.displayName("Kapitel 01", number: 1) == "Kapitel 1")
    #expect(SideChapters.displayName("Prolog 1984", number: 1) == "Prolog 1984")
    #expect(SideChapters.timeLabel(3723) == "1:02:03")
}

@Test func sideEpisodeRowsPerSeason() {
    let eps = [EpisodeRef(season: 2, episode: 1, title: "Neu"), EpisodeRef(season: 1, episode: 2, title: "Zwei"),
               EpisodeRef(season: 1, episode: 1, title: "Pilot"), EpisodeRef(season: 1, episode: 3, title: nil)]
    #expect(SideEpisodes.seasons(eps) == [1, 2])
    #expect(SideEpisodes.initialSeason(current: 2, in: eps) == 2)
    #expect(SideEpisodes.initialSeason(current: 7, in: eps) == 1)
    #expect(SideEpisodes.initialSeason(current: nil, in: []) == nil)
    let rows = SideEpisodes.rows(eps, season: 1, current: EpisodeRef(season: 1, episode: 2), titles: [1: "Der Anfang"],
                                 isWatched: { $0.episode == 1 })
    #expect(rows.map(\.line) == ["F1 · Der Anfang", "F2 · Zwei", "F3"])
    #expect(rows.map(\.isCurrent) == [false, true, false])
    #expect(rows.map(\.isWatched) == [true, false, false])
    #expect(SideEpisodes.initialFocus(rows) == "1:2")
    let other = SideEpisodes.rows(eps, season: 1, current: EpisodeRef(season: 2, episode: 1), isWatched: { $0.episode == 1 })
    #expect(SideEpisodes.initialFocus(other) == "1:2")
    #expect(SideEpisodes.initialFocus([]) == nil)
}

@Test func sideSourceChoice() {
    #expect(SideSources.choose("a", current: "a", playable: true) == .keep)
    #expect(SideSources.choose("b", current: "a", playable: true) == .switchTo("b"))
    #expect(SideSources.choose("b", current: "a", playable: false) == .unavailable)
    #expect(SideSources.initialFocus(ids: ["x", "a"], current: "a") == "a")
    #expect(SideSources.initialFocus(ids: ["x", "a"], current: "z") == "x")
}

@Test func sideInfoRowsAddRateSizeAndAddon() {
    var audio = AudioTrackInfo(id: 1, language: "eng", name: nil, channels: 8)
    audio.codec = "truehd"; audio.isAtmos = true
    let tech = PlaybackTechSnapshot(videoWidth: 3840, sourceFormat: "dolbyVision", dolbyVisionProfile: 7, videoCodec: "hevc",
                                    activeAudio: audio, fileName: "Film.2160p.mkv")
    var traits = StreamTraits()
    traits.sizeBytes = 60_000_000_000
    let rows = SideInfo.rows(tech: tech, traits: traits, duration: 7200, addon: "Torrentio")
    let byLabel = Dictionary(rows.map { ($0.label, $0.value) }, uniquingKeysWith: { a, _ in a })
    #expect(byLabel["Auflösung"] == "4K")
    #expect(byLabel["Dynamik"] == "Dolby Vision (Profil 7)")
    #expect(byLabel["Tonspur"]?.hasPrefix("Englisch · Dolby Atmos (TrueHD) · 7.1") == true)
    #expect(byLabel["Datenrate"] == "≈ 66,7 Mbit/s")
    #expect(byLabel["Größe"] == "60,0 GB")
    #expect(byLabel["Addon"] == "Torrentio")
    #expect(byLabel["Quelle"] == "Film.2160p.mkv")
    #expect(SideInfo.summary(rows) == "4K · Dolby Vision (Profil 7)")
    #expect(SideInfo.bitrateLabel(sizeBytes: 1_000_000, duration: 30) == nil)
    #expect(SideInfo.bitrateLabel(sizeBytes: nil, duration: 3000) == nil)
    #expect(SideInfo.sizeLabel(850_000_000) == "850 MB")
    #expect(SideInfo.summary([]) == nil)
}

// MARK: Pause card

@Test func pauseCardAppearsAfterTwoSecondsOfPause() {
    var r = PauseCardRule()
    r.update(isPlaying: true, now: 0)
    #expect(!r.isVisible(now: 100, blocked: false))
    r.update(isPlaying: false, now: 10)
    #expect(!r.isVisible(now: 11.9, blocked: false))
    #expect(r.isVisible(now: 12, blocked: false))
    #expect(!r.isVisible(now: 12, blocked: true))
    // Input hides it; it waits longer before it comes back in the same pause.
    r.noteInput(now: 13)
    #expect(!r.isVisible(now: 15, blocked: false))
    #expect(r.isVisible(now: 19, blocked: false))
    // Playing again resets; a new pause starts with the short delay.
    let changed = r.update(isPlaying: true, now: 20)
    #expect(changed)
    #expect(!r.isVisible(now: 30, blocked: false))
    let again = r.update(isPlaying: true, now: 21)
    #expect(!again)
    r.update(isPlaying: false, now: 40)
    #expect(r.isVisible(now: 42, blocked: false))
    // Input while playing is ignored.
    var p = PauseCardRule()
    p.noteInput(now: 1)
    p.update(isPlaying: false, now: 2)
    #expect(p.isVisible(now: 4, blocked: false))
}

@Test func pauseCardBlockReasons() {
    #expect(PauseCardRule.blockReason(panelOpen: false, scrubbing: false, failure: false, upNext: false, skipPrompt: false,
                                      loading: false, leaving: false, noPicture: false) == nil)
    #expect(PauseCardRule.blockReason(panelOpen: true, scrubbing: true, failure: false, upNext: false, skipPrompt: false,
                                      loading: false, leaving: false, noPicture: false) == "Panel offen")
    #expect(PauseCardRule.blockReason(panelOpen: true, scrubbing: false, failure: true, upNext: false, skipPrompt: false,
                                      loading: false, leaving: false, noPicture: false) == "Fehlerkarte")
}

@Test func pauseCardContent() {
    let ep = PauseCardContent.make(title: "Serie", logo: " ", season: 1, episode: 3, episodeTitle: "Pilot",
                                   descriptions: [nil, "  ", "Folgentext."], cast: ["A", "", "B", "C", "D", "E"])
    #expect(ep.episodeLine == "S1 · F3 · Pilot")
    #expect(ep.logoURL == nil)
    #expect(ep.description == "Folgentext.")
    #expect(ep.castLine == "Mit A, B, C, D")
    let movie = PauseCardContent.make(title: "Film", logo: "https://x/logo.png", season: nil, episode: nil, episodeTitle: nil,
                                      descriptions: [], cast: [])
    #expect(movie.episodeLine == nil && movie.description == nil && movie.castLine == nil)
    #expect(movie.logoURL == "https://x/logo.png")
    #expect(PauseCardContent.make(title: "S", logo: nil, season: 2, episode: 1, episodeTitle: nil, descriptions: [], cast: []).episodeLine == "S2 · F1")
}

@Test func pauseCardShortensAtWordOrSentence() {
    let words = String(repeating: "Wort ", count: 80)
    let s = PauseCardContent.shortened(words, maxChars: 50)
    #expect(s.hasSuffix(" …"))
    #expect(s.count <= 52)
    #expect(!s.contains("  "))
    let sentence = String(repeating: "a", count: 40) + ". " + String(repeating: "b ", count: 40)
    #expect(PauseCardContent.shortened(sentence, maxChars: 50) == String(repeating: "a", count: 40) + ".")
    #expect(PauseCardContent.shortened("kurz", maxChars: 50) == "kurz")
}
