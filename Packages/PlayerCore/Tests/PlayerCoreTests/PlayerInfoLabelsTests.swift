import Foundation
import Testing
@testable import PlayerCore

@Test func infoBadgesPixelsExample() {
    let atmos = AudioTrackInfo(id: 1, language: "eng", name: "Surround 7.1", channels: 8, codec: "truehd",
                               profile: "Dolby TrueHD + Dolby Atmos", isAtmos: true)
    #expect(MediaLabels.infoBadges(videoWidth: 1920, videoFormat: "sdr", audio: atmos, subtitle: nil)
            == ["1080p", "Englisch · Dolby Atmos (TrueHD) 7.1"])
}

@Test func infoBadgesWithHDRAndSubtitle() {
    let dd = AudioTrackInfo(id: 2, language: "ger", channels: 6, codec: "eac3")
    let sub = AudioTrackInfo(id: 5, language: "deu", codec: "subrip")
    #expect(MediaLabels.infoBadges(videoWidth: 3840, videoFormat: "dolbyVision", audio: dd, subtitle: sub)
            == ["4K", "Dolby Vision", "Deutsch · Dolby Digital+ 5.1", "UT: Deutsch"])
    #expect(MediaLabels.infoBadges(videoWidth: 3840, videoFormat: "hdr10", audio: nil, subtitle: nil) == ["4K", "HDR10"])
}

@Test func infoBadgesEmptyWithoutData() {
    #expect(MediaLabels.infoBadges(videoWidth: 0, videoFormat: "sdr", audio: nil, subtitle: nil).isEmpty)
    #expect(MediaLabels.infoBadges(videoWidth: nil, videoFormat: nil, audio: AudioTrackInfo(id: 0, language: nil), subtitle: nil).isEmpty)
}

@Test func audioBadgeDropsUnknownParts() {
    #expect(MediaLabels.audioBadge(AudioTrackInfo(id: 0, language: "und", channels: 2, codec: "aac")) == "AAC Stereo")
    #expect(MediaLabels.audioBadge(AudioTrackInfo(id: 0, language: "eng")) == "Englisch")
    #expect(MediaLabels.audioBadge(AudioTrackInfo(id: 0, language: "fre", codec: "dts", profile: "DTS-HD MA")) == "Französisch · DTS-HD MA")
    #expect(MediaLabels.audioBadge(AudioTrackInfo(id: 0, language: "eng", channels: 6, codec: "ac3", channelLayout: "5.1(side)"))
            == "Englisch · Dolby Digital 5.1")
}

@Test func subtitleBadgeVariants() {
    #expect(MediaLabels.subtitleBadge(AudioTrackInfo(id: 0, language: "ger", codec: "subrip")) == "UT: Deutsch")
    #expect(MediaLabels.subtitleBadge(AudioTrackInfo(id: 0, language: "eng", codec: "subrip", isForced: true)) == "UT: Englisch (erzwungen)")
    #expect(MediaLabels.subtitleBadge(AudioTrackInfo(id: 0, language: nil, name: "Track 3 (subrip)", codec: "subrip")) == "UT: an")
    #expect(MediaLabels.subtitleBadge(AudioTrackInfo(id: 0, language: nil, name: "Signs & Songs", codec: "ass")) == "UT: Signs & Songs")
}

@Test func episodeLineFormats() {
    #expect(MediaLabels.episodeLine(season: 1, episode: 2, title: "Der Anfang") == "S01E02 · Der Anfang")
    #expect(MediaLabels.episodeLine(season: 12, episode: 104, title: "  ") == "S12E104")
    #expect(MediaLabels.episodeLine(season: 3, episode: 7, title: nil) == "S03E07")
    #expect(MediaLabels.episodeLine(season: nil, episode: 2, title: "x") == nil)
}

@Test func endTimeFormats() {
    let utc = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 22 * 3600 + 10 * 60)   // 22:10 UTC
    #expect(MediaLabels.endTime(remaining: 31 * 60 + 20, now: now, timeZone: utc) == "Endet um 22:41")
    #expect(MediaLabels.endTime(remaining: 2 * 3600, now: now, timeZone: utc) == "Endet um 00:10")
    #expect(MediaLabels.endTime(remaining: 0, now: now, timeZone: utc) == nil)
    #expect(MediaLabels.endTime(remaining: .nan, now: now, timeZone: utc) == nil)
}
