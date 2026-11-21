import Foundation
import Testing
@testable import PlayerCore

private func t(_ id: Int, _ lang: String?, name: String? = nil, ch: Int? = nil, codec: String? = nil,
               forced: Bool = false, sdh: Bool = false, comm: Bool = false, ext: Bool = false) -> AudioTrackInfo {
    AudioTrackInfo(id: id, language: lang, name: name, channels: ch, codec: codec,
                   isForced: forced, isHearingImpaired: sdh, isCommentary: comm, isExternal: ext)
}

@Test func audioGroupsPreferredLanguageFirst() {
    let tracks = [t(0, "eng"), t(1, "fre"), t(2, "ger"), t(3, "en"), t(4, nil), t(5, "spa")]
    let g = TrackPanelLogic.groupByLanguage(tracks, preferred: ["de", "en", "orig"])
    #expect(g.map(\.code) == ["de", "en", "fr", "es", nil])
    #expect(g.map(\.name) == ["Deutsch", "Englisch", "Französisch", "Spanisch", "Unbekannt"])
    #expect(g[1].tracks.map(\.id) == [0, 3])
    #expect(TrackPanelLogic.sortedAudio(tracks, priority: ["de", "en", "orig"]).map(\.id) == [2, 0, 3, 1, 5, 4])
}

@Test func preferredOrigAndDuplicatesIgnored() {
    let tracks = [t(0, "jpn"), t(1, "eng")]
    let g = TrackPanelLogic.groupByLanguage(tracks, preferred: ["orig", "ger", "eng", "en"])
    #expect(g.map(\.code) == ["en", "ja"])
}

@Test func withinGroupNonSDHBeforeSDHCommentaryLast() {
    let tracks = [t(0, "ger", sdh: true), t(1, "ger", comm: true), t(2, "ger", forced: true), t(3, "ger"), t(4, "eng")]
    let g = TrackPanelLogic.subtitleGroups(tracks, preferredLanguage: "de")
    #expect(g.first?.code == "de")
    #expect(g.first?.tracks.map(\.id) == [2, 3, 0, 1])
    #expect(g.first?.header == "Deutsch (4)")
    #expect(g.last?.header == "Englisch (1)")
}

@Test func subtitleGroupsWithoutPreference() {
    let tracks = [t(0, "eng"), t(1, "ger")]
    #expect(TrackPanelLogic.subtitleGroups(tracks, preferredLanguage: nil).map(\.code) == ["en", "de"])
    #expect(TrackPanelLogic.subtitleGroups([], preferredLanguage: "de").isEmpty)
}

@Test func audioRowLabel() {
    var a = AudioTrackInfo(id: 0, language: "eng", name: "Surround 7.1", channels: 8, codec: "truehd",
                           isDefault: true, profile: "Dolby TrueHD + Dolby Atmos", channelLayout: "7.1")
    var r = TrackPanelLogic.audioRow(a)
    #expect(r.title == "Englisch")
    #expect(r.detail == "Dolby Atmos (TrueHD) · 7.1")
    #expect(r.name == nil)
    #expect(r.badges == ["Standard"])
    a.name = "Regiekommentar"; a.isCommentary = true; a.isDefault = false
    r = TrackPanelLogic.audioRow(a)
    #expect(r.name == "Regiekommentar")
    #expect(r.badges == ["Kommentar"])
}

@Test func subtitleRowLabel() {
    // Sprache steht im Gruppenkopf: nie im Zeilentitel.
    let s = AudioTrackInfo(id: 3, language: "ger", name: "German (SDH)", codec: "hdmv_pgs_subtitle",
                           isHearingImpaired: true, isImage: true)
    let r = TrackPanelLogic.subtitleRow(s)
    #expect(r.title == "German (SDH)")
    #expect(r.detail == "PGS · Bild")
    #expect(r.name == nil)
    #expect(r.badges == ["SDH"])
    let e = TrackPanelLogic.subtitleRow(t(9, "en", name: "OpenSubtitles", codec: "subrip", ext: true))
    #expect(e.title == "OpenSubtitles")
    #expect(e.detail == "SRT")
    #expect(e.badges == ["Extern"])
    #expect(e.name == nil)
    let plain = TrackPanelLogic.subtitleRow(t(4, "ger", name: "Deutsch", codec: "subrip"))
    #expect(plain.title == "SRT")
    #expect(plain.detail == nil)
    let bare = TrackPanelLogic.subtitleRow(t(5, "eng"), number: 2)
    #expect(bare.title == "Spur 2")
    #expect(TrackPanelLogic.subtitleRow(t(5, nil)).title == "Spur 6")
}

@Test func audioRowUnknownLanguageNoUnbekannt() {
    let named = TrackPanelLogic.audioRow(AudioTrackInfo(id: 1, language: "und", name: "Director's Cut Mix", channels: 6, codec: "ac3"))
    #expect(named.title == "Director's Cut Mix")
    #expect(named.name == nil)
    #expect(named.detail == "Dolby Digital · 5.1")
    let format = TrackPanelLogic.audioRow(AudioTrackInfo(id: 1, language: nil, name: "Surround", channels: 2, codec: "aac"))
    #expect(format.title == "AAC")
    #expect(format.detail == "Stereo")
    #expect(format.name == nil)
    let bare = TrackPanelLogic.audioRow(AudioTrackInfo(id: 1, language: "qaa"), number: 3)
    #expect(bare.title == "Spur 3")
    #expect(bare.detail == nil)
    #expect(TrackPanelLogic.audioRow(AudioTrackInfo(id: 1, language: nil)).title == "Spur 2")
    for r in [named, format, bare] { #expect(r.title != "Unbekannt") }
}

@Test func unknownLanguagesShareOneLastGroup() {
    let tracks = [t(0, "qaa"), t(1, "eng"), t(2, nil), t(3, "und"), t(4, "ger")]
    let g = TrackPanelLogic.groupByLanguage(tracks, preferred: ["de"])
    #expect(g.map(\.code) == ["de", "en", nil])
    #expect(g.last?.name == "Unbekannt")
    #expect(g.last?.tracks.map(\.id) == [0, 2, 3])
}

@Test func subtitleFormats() {
    #expect(TrackPanelLogic.subtitleFormat(codec: "subrip", isImage: false) == "SRT")
    #expect(TrackPanelLogic.subtitleFormat(codec: "ass", isImage: false) == "ASS")
    #expect(TrackPanelLogic.subtitleFormat(codec: "webvtt", isImage: false) == "WebVTT")
    #expect(TrackPanelLogic.subtitleFormat(codec: "mov_text", isImage: false) == "Text")
    #expect(TrackPanelLogic.subtitleFormat(codec: "dvd_subtitle", isImage: false) == "VobSub · Bild")
    #expect(TrackPanelLogic.subtitleFormat(codec: "dvb_subtitle", isImage: true) == "DVB · Bild")
    #expect(TrackPanelLogic.subtitleFormat(codec: nil, isImage: false) == nil)
    #expect(TrackPanelLogic.subtitleFormat(codec: "", isImage: true) == "Bild")
}

@Test func audioOutputOnlyWhenConverted() {
    #expect(TrackPanelLogic.audioOutput(pipeline: "TRUEHD → EAC3 bridge", delivery: "bridged", sourceChannels: 8)
            == "Dolby Digital+ 5.1 (umgewandelt)")
    #expect(TrackPanelLogic.audioOutput(pipeline: "AAC → EAC3 bridge (shaped)", delivery: "bridged", sourceChannels: 2)
            == "Dolby Digital+ Stereo (umgewandelt)")
    #expect(TrackPanelLogic.audioOutput(pipeline: "DTS → FLAC bridge", delivery: "bridged", sourceChannels: 8, sourceLayout: "7.1")
            == "FLAC 7.1 (umgewandelt, verlustfrei)")
    #expect(TrackPanelLogic.audioOutput(pipeline: "libavcodec OPUS → CoreAudio", delivery: "decoded", sourceChannels: 2)
            == "PCM Stereo (dekodiert)")
    #expect(TrackPanelLogic.audioOutput(pipeline: "TRUEHD Atmos → PCM 7.1.4", delivery: "bridged", sourceChannels: 8)
            == "PCM 7.1.4 (Atmos gerendert)")
    #expect(TrackPanelLogic.audioOutput(pipeline: "DTS:X → APAC 5.1.4", delivery: "bridged", sourceChannels: 8)
            == "APAC 5.1.4 (DTS:X gerendert)")
    #expect(TrackPanelLogic.audioOutput(pipeline: "EAC3 Atmos → PCM 7.1.4 (system decoder)", delivery: "bridged", sourceChannels: 6)
            == "PCM 7.1.4 (Atmos gerendert)")
    #expect(TrackPanelLogic.audioOutput(pipeline: "Stream-copy (EAC3+JOC Atmos)", delivery: "streamCopy", sourceChannels: 6) == nil)
    #expect(TrackPanelLogic.audioOutput(pipeline: nil, delivery: "bridged", sourceChannels: 6) == nil)
}

@Test func sourceFileNameOnlyForMediaFiles() {
    #expect(TrackPanelLogic.sourceFileName(URL(string: "https://x.example/dl/abc/Pixels.2015.1080p.mkv")) == "Pixels.2015.1080p.mkv")
    #expect(TrackPanelLogic.sourceFileName(URL(string: "https://x.example/dl/Mein%20Film.mp4?token=1")) == "Mein Film.mp4")
    #expect(TrackPanelLogic.sourceFileName(URL(string: "https://x.example/stream?id=5")) == nil)
    #expect(TrackPanelLogic.sourceFileName(URL(string: "https://x.example/master.m3u8")) == nil)
    #expect(TrackPanelLogic.sourceFileName(nil) == nil)
}

@Test func infoRowsWithToneMapping() {
    let s = PlaybackTechSnapshot(videoWidth: 3840, sourceFormat: "dolbyVision", outputFormat: "sdr", dolbyVisionProfile: 8,
                                 videoCodec: "hevc", audioPipeline: "TRUEHD → EAC3 bridge", audioDelivery: "bridged",
                                 activeAudio: t(0, "eng", ch: 8, codec: "truehd"), fileName: "Film.mkv")
    let rows = TrackPanelLogic.infoRows(s)
    #expect(rows.map(\.label) == ["Auflösung", "Dynamik", "Ausgabe", "Video-Codec", "Ton-Ausgabe", "Quelle"])
    #expect(rows.map(\.value) == ["4K", "Dolby Vision (Profil 8)", "SDR", "HEVC", "Dolby Digital+ 5.1 (umgewandelt)", "Film.mkv"])
}

@Test func infoRowsPlainSDR() {
    let s = PlaybackTechSnapshot(videoWidth: 1920, sourceFormat: "sdr", outputFormat: "sdr", videoCodec: "h264",
                                 audioPipeline: "Stream-copy (AC3)", audioDelivery: "streamCopy")
    let rows = TrackPanelLogic.infoRows(s)
    #expect(rows.map(\.label) == ["Auflösung", "Dynamik", "Video-Codec"])
    #expect(rows.map(\.value) == ["1080p", "SDR", "H.264"])
    #expect(TrackPanelLogic.infoRows(PlaybackTechSnapshot()).isEmpty)
}
