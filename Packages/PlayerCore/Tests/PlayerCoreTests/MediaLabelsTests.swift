import Foundation
import Testing
@testable import PlayerCore

@Test func languageCodeNormalizes() {
    #expect(MediaLabels.languageCode("ger") == "de")
    #expect(MediaLabels.languageCode("deu") == "de")
    #expect(MediaLabels.languageCode("GER") == "de")
    #expect(MediaLabels.languageCode("German") == "de")
    #expect(MediaLabels.languageCode("deutsch") == "de")
    #expect(MediaLabels.languageCode("de-DE") == "de")
    #expect(MediaLabels.languageCode("en_US") == "en")
    #expect(MediaLabels.languageCode("eng") == "en")
    #expect(MediaLabels.languageCode("fre") == "fr")
    #expect(MediaLabels.languageCode("fra") == "fr")
    #expect(MediaLabels.languageCode("dut") == "nl")
    #expect(MediaLabels.languageCode("cze") == "cs")
    #expect(MediaLabels.languageCode("chi") == "zh")
    #expect(MediaLabels.languageCode("gre") == "el")
    #expect(MediaLabels.languageCode("rum") == "ro")
    #expect(MediaLabels.languageCode("pob") == "pt-BR")
    #expect(MediaLabels.languageCode("pt-br") == "pt-BR")
    #expect(MediaLabels.languageCode("jpn") == "ja")
    #expect(MediaLabels.languageCode("spa") == "es")
    #expect(MediaLabels.languageCode("es") == "es")
    #expect(MediaLabels.languageCode("und") == nil)
    #expect(MediaLabels.languageCode("") == nil)
    #expect(MediaLabels.languageCode("  ") == nil)
    #expect(MediaLabels.languageCode(nil) == nil)
}

@Test func languageNameInGerman() {
    #expect(MediaLabels.languageName("de") == "Deutsch")
    #expect(MediaLabels.languageName("en") == "Englisch")
    #expect(MediaLabels.languageName("ger") == "Deutsch")
    #expect(MediaLabels.languageName("eng") == "Englisch")
    #expect(MediaLabels.languageName("jpn") == "Japanisch")
    #expect(MediaLabels.languageName("pob") == "Portugiesisch (Brasilien)")
    #expect(MediaLabels.languageName("und") == "Unbekannt")
    #expect(MediaLabels.languageName(nil) == "Unbekannt")
    #expect(MediaLabels.languageName("qaa") == "Unbekannt")
    #expect(MediaLabels.languageName("xx") == "Unbekannt")
}

@Test func resolutionByWidth() {
    #expect(MediaLabels.resolution(width: 1920) == "1080p")
    #expect(MediaLabels.resolution(width: 1500) == "1080p")
    #expect(MediaLabels.resolution(width: 1499) == "720p")
    #expect(MediaLabels.resolution(width: 1280) == "720p")
    #expect(MediaLabels.resolution(width: 1100) == "720p")
    #expect(MediaLabels.resolution(width: 1099) == "SD")
    #expect(MediaLabels.resolution(width: 720) == "SD")
    #expect(MediaLabels.resolution(width: 2560) == "1440p")
    #expect(MediaLabels.resolution(width: 2200) == "1440p")
    #expect(MediaLabels.resolution(width: 3840) == "4K")
    #expect(MediaLabels.resolution(width: 3000) == "4K")
    #expect(MediaLabels.resolution(width: 7680) == "8K")
    #expect(MediaLabels.resolution(width: 0) == nil)
    #expect(MediaLabels.resolution(width: nil) == nil)
}

@Test func dynamicRangeAndVideoCodec() {
    #expect(MediaLabels.dynamicRange("dolbyVision") == "Dolby Vision")
    #expect(MediaLabels.dynamicRange("hdr10Plus") == "HDR10+")
    #expect(MediaLabels.dynamicRange("hdr10") == "HDR10")
    #expect(MediaLabels.dynamicRange("hlg") == "HLG")
    #expect(MediaLabels.dynamicRange("sdr") == nil)
    #expect(MediaLabels.dynamicRange(nil) == nil)
    #expect(MediaLabels.videoCodec("hevc") == "HEVC")
    #expect(MediaLabels.videoCodec("h264") == "H.264")
    #expect(MediaLabels.videoCodec("av1") == "AV1")
    #expect(MediaLabels.videoCodec("vp9") == "VP9")
    #expect(MediaLabels.videoCodec("mpeg2video") == "MPEG-2")
    #expect(MediaLabels.videoCodec("vc1") == "VC1")
    #expect(MediaLabels.videoCodec(nil) == nil)
}

@Test func audioFormatByCodecAndFlags() {
    func f(_ c: String?, _ p: String? = nil, atmos: Bool = false, dtsx: Bool = false) -> String {
        MediaLabels.audioFormat(codec: c, profile: p, isAtmos: atmos, isDTSX: dtsx)
    }
    #expect(f("truehd", atmos: true) == "Dolby Atmos (TrueHD)")
    #expect(f("truehd", "Dolby TrueHD + Dolby Atmos") == "Dolby Atmos (TrueHD)")
    #expect(f("truehd") == "Dolby TrueHD")
    #expect(f("eac3", atmos: true) == "Dolby Atmos (DD+)")
    #expect(f("eac3") == "Dolby Digital+")
    #expect(f("ac3") == "Dolby Digital")
    #expect(f("dts", "DTS-HD MA") == "DTS-HD MA")
    #expect(f("dts", "DTS-HD MA + DTS:X") == "DTS:X")
    #expect(f("dts", "DTS-HD MA", dtsx: true) == "DTS:X")
    #expect(f("dts", "DTS-HD HRA") == "DTS-HD HR")
    #expect(f("dts") == "DTS")
    #expect(f("dca", "DTS-HD MA") == "DTS-HD MA")
    #expect(f("aac", "LC") == "AAC")
    #expect(f("flac") == "FLAC")
    #expect(f("opus") == "Opus")
    #expect(f("pcm_s24le") == "PCM")
    #expect(f("mp3") == "MP3")
    #expect(f(nil) == "Unbekannt")
}

@Test func channelLabels() {
    #expect(MediaLabels.channels(1) == "Mono")
    #expect(MediaLabels.channels(2) == "Stereo")
    #expect(MediaLabels.channels(6) == "5.1")
    #expect(MediaLabels.channels(8) == "7.1")
    #expect(MediaLabels.channels(3) == "3 Kanäle")
    #expect(MediaLabels.channels(0) == nil)
    #expect(MediaLabels.channels(nil) == nil)
    #expect(MediaLabels.channels(6, layout: "5.1(side)") == "5.1")
    #expect(MediaLabels.channels(8, layout: "7.1") == "7.1")
    #expect(MediaLabels.channels(2, layout: "stereo") == "Stereo")
    #expect(MediaLabels.channels(3, layout: "2.1") == "2.1")
    #expect(MediaLabels.channels(6, layout: "hexagonal") == "5.1")
    #expect(MediaLabels.channels(4, layout: "quad") == "4 Kanäle")
    #expect(MediaLabels.channels(nil, layout: "mono") == "Mono")
}

@Test func genericTrackNames() {
    #expect(MediaLabels.isGenericTrackName("English", language: "eng", codec: "truehd"))
    #expect(MediaLabels.isGenericTrackName("Surround 7.1", language: "eng", codec: "truehd"))
    #expect(MediaLabels.isGenericTrackName("TrueHD", language: "eng", codec: "truehd"))
    #expect(MediaLabels.isGenericTrackName("Deutsch", language: "ger", codec: "ac3"))
    #expect(MediaLabels.isGenericTrackName("German DTS-HD MA 5.1", language: "deu", codec: "dts"))
    #expect(MediaLabels.isGenericTrackName("ENG (subrip)", language: "eng", codec: "subrip"))
    #expect(MediaLabels.isGenericTrackName("GER", language: "deu", codec: "subrip"))
    #expect(MediaLabels.isGenericTrackName("Track 3 (subrip)", language: nil, codec: "subrip"))
    #expect(MediaLabels.isGenericTrackName(nil, language: "eng", codec: "aac"))
    #expect(MediaLabels.isGenericTrackName("", language: "eng", codec: "aac"))
    #expect(!MediaLabels.isGenericTrackName("Director's Commentary", language: "eng", codec: "ac3"))
    #expect(!MediaLabels.isGenericTrackName("English SDH", language: "eng", codec: "subrip"))
    #expect(!MediaLabels.isGenericTrackName("Forced", language: "ger", codec: "pgssub"))
    #expect(!MediaLabels.isGenericTrackName("English", language: nil, codec: "aac"))
    #expect(!MediaLabels.isGenericTrackName("Deutsch", language: "eng", codec: "aac"))
}

@Test func trackBadgeOrder() {
    #expect(MediaLabels.trackBadges(isForced: true, isHearingImpaired: true, isCommentary: true,
                                    isDefault: true, isExternal: true, source: nil)
            == ["Erzwungen", "SDH", "Kommentar", "Standard", "Extern"])
    #expect(MediaLabels.trackBadges(isForced: false, isHearingImpaired: false, isCommentary: false,
                                    isDefault: false, isExternal: true, source: "OpenSubtitles")
            == ["OpenSubtitles"])
    #expect(MediaLabels.trackBadges(isVisualImpaired: true, isDefault: true) == ["Hörfilm", "Standard"])
    #expect(MediaLabels.trackBadges(isForced: false, isHearingImpaired: false, isCommentary: false,
                                    isDefault: false, isExternal: false, source: "x").isEmpty)
}

@Test func imageSubtitleCodecs() {
    #expect(MediaLabels.isImageSubtitleCodec("pgssub"))
    #expect(MediaLabels.isImageSubtitleCodec("hdmv_pgs_subtitle"))
    #expect(MediaLabels.isImageSubtitleCodec("dvdsub"))
    #expect(MediaLabels.isImageSubtitleCodec("dvb_subtitle"))
    #expect(!MediaLabels.isImageSubtitleCodec("subrip"))
    #expect(!MediaLabels.isImageSubtitleCodec("ass"))
    #expect(!MediaLabels.isImageSubtitleCodec(nil))
}

@Test func trackInfoKeepsOldInitAndDefaults() {
    let t = AudioTrackInfo(id: 1, language: "eng", name: "x", channels: 6, codec: "eac3")
    #expect(!t.isDefault && !t.isForced && !t.isAtmos && !t.isImage && t.profile == nil && t.channelLayout == nil)
    let s = AudioTrackInfo(id: 2, language: "ger", codec: "pgssub", isForced: true, isImage: true)
    #expect(s.isForced && s.isImage && !s.isHearingImpaired)
}

@Test func preferredAudioUsesSharedLanguageCode() {
    let tracks = [AudioTrackInfo(id: 0, language: "jpn"), AudioTrackInfo(id: 1, language: "en-US", channels: 6),
                  AudioTrackInfo(id: 2, language: "GER", channels: 6)]
    #expect(preferredAudioTrack(tracks, priority: ["de", "en"])?.id == 2)
    #expect(preferredAudioTrack(tracks, priority: ["en"])?.id == 1)
    #expect(preferredAudioTrack(tracks, priority: ["ja"])?.id == 0)
    #expect(preferredAudioTrack(tracks, priority: ["fr", "orig"])?.id == 0)
}
