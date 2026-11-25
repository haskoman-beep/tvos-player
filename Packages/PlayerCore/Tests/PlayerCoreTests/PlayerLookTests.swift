import Foundation
import Testing
@testable import PlayerCore

// Task 5.4: player options of the look (time display, badges, track panel mapping).

private let utc = TimeZone(identifier: "UTC")!
/// 20:15:10 UTC: with 1:25:50 left the movie ends at 21:41 (the plan example).
private let now = Date(timeIntervalSince1970: 20 * 3600 + 15 * 60 + 10)
private let position: TimeInterval = 42 * 60 + 10          // 42:10
private let duration: TimeInterval = 2 * 3600 + 8 * 60      // 2:08:00

@Test func timeTextModeRest() {
    let t = PlayerTimeText.make(position: position, duration: duration, now: now, mode: .rest, timeZone: utc)
    #expect(t.leading == "42:10")
    #expect(t.trailing == "−1:25:50")
}

@Test func timeTextModeGesamt() {
    let t = PlayerTimeText.make(position: position, duration: duration, now: now, mode: .gesamt, timeZone: utc)
    #expect(t.leading == "42:10")
    #expect(t.trailing == "2:08:00")
}

@Test func timeTextModeEnde() {
    let t = PlayerTimeText.make(position: position, duration: duration, now: now, mode: .ende, timeZone: utc)
    #expect(t.leading == "42:10")
    #expect(t.trailing == "Endet um 21:41")
}

@Test func timeTextEdgeCases() {
    // Unknown duration (still loading, live): no trailing text, never "−0:00" or a nonsense end time.
    for mode in LookTimeDisplay.allCases {
        let t = PlayerTimeText.make(position: 12, duration: 0, now: now, mode: mode, timeZone: utc)
        #expect(t.leading == "0:12")
        #expect(t.trailing == "")
    }
    // Position past the end and NaN never produce negative or broken numbers.
    #expect(PlayerTimeText.make(position: 9000, duration: duration, now: now, mode: .rest, timeZone: utc).trailing == "−0:00")
    #expect(PlayerTimeText.make(position: .nan, duration: duration, now: now, mode: .gesamt, timeZone: utc).leading == "0:00")
    // At the end "ende" shows the current time instead of nothing.
    #expect(PlayerTimeText.make(position: duration, duration: duration, now: now, mode: .ende, timeZone: utc).trailing
            == "Endet um 20:15")
}

// MARK: Badges

private let dvAtmos = StreamTechInfo(videoWidth: 3840, videoFormat: "dolbyVision", videoCodec: "hevc",
                                     audio: AudioTrackInfo(id: 1, language: "eng", channels: 8, codec: "truehd",
                                                           profile: "Dolby TrueHD + Dolby Atmos", isAtmos: true),
                                     bitrateMbps: 61.3)

@Test func badgeSetCompactHasAtMostThree() {
    let b = PlayerBadgeSet.make(dvAtmos, mode: .kompakt)
    #expect(b == ["4K", "DV", "Atmos"])
    #expect(b.count <= 3)
    let hdr = StreamTechInfo(videoWidth: 1920, videoFormat: "hdr10", audio: AudioTrackInfo(id: 2, language: "ger", channels: 6, codec: "eac3"))
    #expect(PlayerBadgeSet.make(hdr, mode: .kompakt) == ["1080p", "HDR10", "DD+"])
    // SDR shows no dynamic-range badge, unknown audio none either.
    #expect(PlayerBadgeSet.make(StreamTechInfo(videoWidth: 1280, videoFormat: "sdr"), mode: .kompakt) == ["720p"])
}

@Test func badgeSetFullHasAtMostSix() {
    let b = PlayerBadgeSet.make(dvAtmos, mode: .voll)
    #expect(b == ["4K", "Dolby Vision", "Atmos", "7.1", "HEVC", "61 Mbit/s"])
    #expect(b.count <= 6)
    #expect(PlayerBadgeSet.make(dvAtmos, mode: .aus).isEmpty)
    #expect(PlayerBadgeSet.make(StreamTechInfo(), mode: .voll).isEmpty)
    // A low data rate keeps one decimal; zero or NaN is left out.
    var low = StreamTechInfo(videoWidth: 1920, videoFormat: "sdr", videoCodec: "h264", bitrateMbps: 4.26)
    #expect(PlayerBadgeSet.make(low, mode: .voll) == ["1080p", "H.264", "4,3 Mbit/s"])
    low.bitrateMbps = .nan
    #expect(PlayerBadgeSet.make(low, mode: .voll) == ["1080p", "H.264"])
}

@Test func badgeSetShortAudioNames() {
    func short(_ codec: String, profile: String? = nil, atmos: Bool = false, dtsx: Bool = false) -> String? {
        PlayerBadgeSet.audioShort(AudioTrackInfo(id: 0, language: nil, codec: codec, profile: profile, isAtmos: atmos, isDTSX: dtsx))
    }
    #expect(short("eac3", atmos: true) == "Atmos")
    #expect(short("truehd") == "TrueHD")
    #expect(short("ac3") == "DD")
    #expect(short("dts", profile: "DTS-HD MA") == "DTS-HD MA")
    #expect(short("dts", dtsx: true) == "DTS:X")
    #expect(short("aac") == "AAC")
    #expect(PlayerBadgeSet.audioShort(AudioTrackInfo(id: 0, language: "eng")) == nil)
}

// MARK: Track panel

@Test func trackPanelMappingCoversAllStyles() {
    // Every old style maps to a look value and back (the same table as `LookMigration`).
    for style in TrackPanelStyle.allCases {
        #expect(TrackPanelStyle(style.look) == style)
    }
    for value in LookTrackPanel.allCases {
        #expect(TrackPanelStyle(value).look == value)
    }
    #expect(Set(TrackPanelStyle.allCases.map(\.look)) == Set(LookTrackPanel.allCases))
    // Same direction as the migration of old profiles.
    for style in TrackPanelStyle.allCases {
        var p = PlayerComfortSettings()
        p.trackPanelStyle = style
        let look = Look.migrated(from: Appearance(), player: p, sources: SourceSettings()).resolved()
        #expect(look.player.trackPanel == style.look)
        #expect(LookMigration.oldValues(for: look).trackPanelStyle == style)
    }
}

@Test func trackPanelSideClosesOnlyFromTheVeryTop() {
    // "Seite" stacks Ton over Untertitel over Versatz: a swipe up from the top row of Untertitel is a step up into
    // Ton, only the first row of the first column with rows closes.
    let audio = TrackPanelColumnModel(column: .audio, title: "Ton",
                                      rows: [TrackPanelRow(id: .track(1), line: "Deutsch"), TrackPanelRow(id: .track(2), line: "Englisch")])
    let subs = TrackPanelColumnModel(column: .subtitles, title: "Untertitel",
                                     rows: [TrackPanelRow(id: .off, line: "Aus"), TrackPanelRow(id: .track(5), line: "Deutsch")])
    let cols = [audio, subs]
    #expect(TrackPanelLayout.closesOnSwipe(.swipeUp, style: .topBar, startSpot: TrackPanelSpot(.audio, .track(1)), columns: cols))
    #expect(!TrackPanelLayout.closesOnSwipe(.swipeUp, style: .topBar, startSpot: TrackPanelSpot(.audio, .track(2)), columns: cols))
    #expect(!TrackPanelLayout.closesOnSwipe(.swipeUp, style: .topBar, startSpot: TrackPanelSpot(.subtitles, .off), columns: cols))
    #expect(TrackPanelLayout.closesOnSwipe(.swipeUp, style: .topBar, startSpot: nil, columns: cols))
    // Without audio rows the subtitles' first row is the top of the panel.
    let noAudio = [TrackPanelColumnModel(column: .audio, title: "Ton", rows: []), subs]
    #expect(TrackPanelLayout.closesOnSwipe(.swipeUp, style: .topBar, startSpot: TrackPanelSpot(.subtitles, .off), columns: noAudio))
    // Swipe down in the side panel is always a list step.
    #expect(!TrackPanelLayout.closesOnSwipe(.swipeDown, style: .topBar, startSpot: TrackPanelSpot(.subtitles, .track(5)), columns: cols))
    // Stacked panel: moving down from Ton into Untertitel keeps the row the focus engine chose (no jump to the
    // active row), the columns side by side still jump to it.
    #expect(TrackPanelStyle.topBar.isStacked)
    #expect(!TrackPanelStyle.bottomBar.isStacked && !TrackPanelStyle.menu.isStacked)
}

@Test func trackPanelStyleTitlesFollowTheLook() {
    #expect(TrackPanelStyle.topBar.title == "Seite")
    #expect(TrackPanelStyle.bottomBar.title == "Unten")
    #expect(TrackPanelStyle.menu.title == "Mitte")
    // As before: only the side panel keeps the control bar; "Unten" and the dimmed centre card hide it.
    #expect(!TrackPanelStyle.topBar.coversBottom)
    #expect(TrackPanelStyle.bottomBar.coversBottom)
    #expect(TrackPanelStyle.menu.coversBottom)
}

// MARK: Catalog

@Test func playerOptionsAreActiveInThisBuild() {
    let v = LookPreset.values(.appleTV)
    for key in ["controlBar", "badges", "timeDisplay", "trackPanel", "upNext", "stillWatching"] {
        let r = LookOptionCatalog.isEnabled(key, in: v)
        #expect(r.enabled, "\(key)")
        #expect(r.reason == nil, "\(key)")
    }
}
