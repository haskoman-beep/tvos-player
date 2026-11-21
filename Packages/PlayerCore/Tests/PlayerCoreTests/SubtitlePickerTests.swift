import Foundation
import Testing
@testable import PlayerCore

private func sub(_ id: Int, _ lang: String?, name: String? = nil, forced: Bool = false, sdh: Bool = false,
                 commentary: Bool = false, isDefault: Bool = false) -> AudioTrackInfo {
    AudioTrackInfo(id: id, language: lang, name: name, isDefault: isDefault, isForced: forced,
                   isHearingImpaired: sdh, isCommentary: commentary)
}

private let sec = ["en"]

// MARK: Modus

@Test func pickOffIsOff() {
    let p = SubtitlePicker.pick([sub(1, "ger", forced: true)], mode: .off, preferredLanguage: "de", audioLanguage: "ger")
    #expect(p.track == nil)
    #expect(p.logText == "UT aus (Einstellung Aus)")
}

@Test func pickNoTracks() {
    let p = SubtitlePicker.pick([], mode: .always, preferredLanguage: "de", audioLanguage: "de")
    #expect(p.track == nil)
    #expect(p.reason == "keine Untertitelspuren")
}

@Test func forcedOnlyPicksForcedInAudioLanguage() {
    // ger/deu/de müssen sich treffen (alter hasPrefix-Fehler).
    let tracks = [sub(1, "eng"), sub(2, "eng", forced: true), sub(3, "deu"), sub(4, "ger", forced: true)]
    let p = SubtitlePicker.pick(tracks, mode: .forcedOnly, preferredLanguage: "de", audioLanguage: "de", secondaryLanguages: sec)
    #expect(p.track?.id == 4)
    #expect(p.logText == "UT gewählt: Deutsch Erzwungen (erzwungen in Tonsprache)")
}

@Test func forcedOnlyFollowsAudioNotWish() {
    let tracks = [sub(1, "ger", forced: true), sub(2, "eng", forced: true)]
    let p = SubtitlePicker.pick(tracks, mode: .forcedOnly, preferredLanguage: "de", audioLanguage: "eng", secondaryLanguages: sec)
    #expect(p.track?.id == 2)
}

@Test func forcedOnlyWithoutForcedIsOff() {
    let tracks = [sub(1, "ger"), sub(2, "eng")]
    let p = SubtitlePicker.pick(tracks, mode: .forcedOnly, preferredLanguage: "de", audioLanguage: "ger", secondaryLanguages: sec)
    #expect(p.track == nil)
    #expect(p.logText == "UT aus (Nur erzwungene, keine erzwungene Spur in Deutsch)")
}

@Test func forcedOnlyForeignAudioGetsFullSubs() {
    let tracks = [sub(1, "jpn"), sub(2, "eng"), sub(3, "ger", sdh: true), sub(4, "ger")]
    let p = SubtitlePicker.pick(tracks, mode: .forcedOnly, preferredLanguage: "de", audioLanguage: "jpn", secondaryLanguages: sec)
    #expect(p.track?.id == 4)
    #expect(p.reason == "Ton Japanisch fremd, Wunschsprache")
}

@Test func forcedOnlyUnknownAudioUsesWishLanguage() {
    let tracks = [sub(1, "eng", forced: true), sub(2, "ger", forced: true)]
    let p = SubtitlePicker.pick(tracks, mode: .forcedOnly, preferredLanguage: "de", audioLanguage: "und", secondaryLanguages: sec)
    #expect(p.track?.id == 2)
    #expect(p.reason == "erzwungen, Tonsprache unbekannt")
}

@Test func forcedByNameOnly() {
    let tracks = [sub(1, "ger"), sub(2, "ger", name: "Deutsch Forced")]
    let p = SubtitlePicker.pick(tracks, mode: .forcedOnly, preferredLanguage: "de", audioLanguage: "de", secondaryLanguages: sec)
    #expect(p.track?.id == 2)
    #expect(p.logText.contains("Erzwungen"))
}

@Test func alwaysPrefersFullWishNonSDH() {
    let tracks = [sub(1, "ger", forced: true), sub(2, "ger", sdh: true), sub(3, "deu"), sub(4, "eng")]
    let p = SubtitlePicker.pick(tracks, mode: .always, preferredLanguage: "de", audioLanguage: "ger", secondaryLanguages: sec)
    #expect(p.track?.id == 3)
    #expect(p.logText == "UT gewählt: Deutsch (Wunschsprache)")
}

@Test func alwaysSDHWhenOnlySDH() {
    let tracks = [sub(1, "eng"), sub(2, "ger", name: "German SDH")]
    let p = SubtitlePicker.pick(tracks, mode: .always, preferredLanguage: "de", audioLanguage: "eng", secondaryLanguages: sec)
    #expect(p.track?.id == 2)
    #expect(p.logText == "UT gewählt: Deutsch SDH (Wunschsprache)")
}

@Test func alwaysDefaultBreaksTie() {
    let tracks = [sub(1, "ger"), sub(2, "ger", isDefault: true)]
    let p = SubtitlePicker.pick(tracks, mode: .always, preferredLanguage: "de", audioLanguage: "de")
    #expect(p.track?.id == 2)
}

@Test func alwaysFallsBackToSecondary() {
    let tracks = [sub(1, "fre"), sub(2, "eng", sdh: true), sub(3, "eng")]
    let p = SubtitlePicker.pick(tracks, mode: .always, preferredLanguage: "de", audioLanguage: "eng", secondaryLanguages: sec)
    #expect(p.track?.id == 3)
    #expect(p.reason == "Zweitsprache")
}

@Test func alwaysForcedAsLastResort() {
    let tracks = [sub(1, "fre"), sub(2, "ita", forced: true)]
    let p = SubtitlePicker.pick(tracks, mode: .always, preferredLanguage: "de", audioLanguage: "it", secondaryLanguages: sec)
    #expect(p.track?.id == 2)
    #expect(p.reason == "nur erzwungene Spur passt")
}

@Test func alwaysNothingMatches() {
    let p = SubtitlePicker.pick([sub(1, "fre")], mode: .always, preferredLanguage: "de", audioLanguage: "fr", secondaryLanguages: sec)
    #expect(p.track == nil)
    #expect(p.logText == "UT aus (keine Spur in Wunsch- oder Zweitsprache)")
}

@Test func commentaryNeverAutomatic() {
    let tracks = [sub(1, "ger", commentary: true), sub(2, "ger", name: "Kommentar des Regisseurs"),
                  sub(3, "eng", name: "Director's Commentary", forced: true)]
    let always = SubtitlePicker.pick(tracks, mode: .always, preferredLanguage: "de", audioLanguage: "en", secondaryLanguages: sec)
    #expect(always.track == nil)
    let forced = SubtitlePicker.pick(tracks, mode: .forcedOnly, preferredLanguage: "de", audioLanguage: "en", secondaryLanguages: sec)
    #expect(forced.track == nil)
}

@Test func sdhWordBoundary() {
    // "Sdhx" ist kein SDH-Kennzeichen.
    let tracks = [sub(1, "ger", name: "Sdhx"), sub(2, "ger", isDefault: true)]
    let p = SubtitlePicker.pick(tracks, mode: .always, preferredLanguage: "de", audioLanguage: "de")
    #expect(p.track?.id == 2)   // Standard-Flag entscheidet, nicht ein falsches SDH
}

@Test func secondaryLanguagesFromAudioPriority() {
    #expect(SubtitlePicker.secondaryLanguages(preferred: "de", audioPriority: ["de", "en", "orig"]) == ["en"])
    #expect(SubtitlePicker.secondaryLanguages(preferred: "de", audioPriority: ["ger", "fra", "eng"]) == ["fr", "en"])
    #expect(SubtitlePicker.secondaryLanguages(preferred: "de", audioPriority: ["orig"]) == ["en"])
    #expect(SubtitlePicker.secondaryLanguages(preferred: "en", audioPriority: ["en", "orig"]) == [])
}

// MARK: Profil-Migration

private func profileJSON(_ extra: String) -> Data {
    Data("{\"id\":\"8E1B0E4C-2C1D-4C59-9B5A-1F4C2D3E4F50\",\"name\":\"Ich\"\(extra)}".utf8)
}

@Test func profileDefaultSubtitleModeIsForcedOnly() throws {
    #expect(Profile.makeDefault().subtitleMode == .forcedOnly)
    let p = try JSONDecoder().decode(Profile.self, from: profileJSON(""))
    #expect(p.subtitleMode == .forcedOnly)
}

@Test func profileMigratesSubtitlesEnabledTrue() throws {
    let p = try JSONDecoder().decode(Profile.self, from: profileJSON(",\"subtitlesEnabled\":true,\"subtitleLanguage\":\"en\""))
    #expect(p.subtitleMode == .always)
    #expect(p.subtitleLanguage == "en")
}

@Test func profileMigratesSubtitlesEnabledFalse() throws {
    let p = try JSONDecoder().decode(Profile.self, from: profileJSON(",\"subtitlesEnabled\":false"))
    #expect(p.subtitleMode == .forcedOnly)
}

@Test func profileNewModeWinsOverLegacy() throws {
    let p = try JSONDecoder().decode(Profile.self, from: profileJSON(",\"subtitlesEnabled\":true,\"subtitleMode\":\"off\""))
    #expect(p.subtitleMode == .off)
}

@Test func profileUnknownModeFallsBack() throws {
    let p = try JSONDecoder().decode(Profile.self, from: profileJSON(",\"subtitleMode\":\"zukunft\""))
    #expect(p.subtitleMode == .forcedOnly)
}

@Test func profileSubtitleModeRoundTrip() throws {
    var p = Profile.makeDefault()
    p.subtitleMode = .always
    let data = try JSONEncoder().encode(p)
    #expect(String(decoding: data, as: UTF8.self).contains("\"subtitleMode\":\"always\""))
    #expect(try JSONDecoder().decode(Profile.self, from: data) == p)
}

// MARK: Geometrie

@Test func videoRectFitsWideMovie() {
    let r = SubtitleGeometry.videoRect(container: CGSize(width: 1920, height: 1080), videoWidth: 3840, videoHeight: 1600)
    #expect(r.width == 1920)
    #expect(abs(r.height - 800) < 0.01)
    #expect(abs(r.minY - 140) < 0.01)
}

@Test func videoRectPillarboxAndAnamorphic() {
    let r = SubtitleGeometry.videoRect(container: CGSize(width: 1920, height: 1080), videoWidth: 1440, videoHeight: 1080)
    #expect(r.width == 1440 && r.minX == 240)
    let a = SubtitleGeometry.videoRect(container: CGSize(width: 1920, height: 1080), videoWidth: 1440, videoHeight: 1080, pixelAspect: 4.0 / 3.0)
    #expect(abs(a.width - 1920) < 0.01 && abs(a.height - 1080) < 0.01)
    let unknown = SubtitleGeometry.videoRect(container: CGSize(width: 1920, height: 1080), videoWidth: 0, videoHeight: 0)
    #expect(unknown == CGRect(x: 0, y: 0, width: 1920, height: 1080))
}

@Test func bitmapFrameCanvasEqualsVideo() {
    let video = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let f = SubtitleGeometry.bitmapFrame(position: CGRect(x: 0.25, y: 0.8, width: 0.5, height: 0.1),
                                         canvas: .zero, codedVideo: CGSize(width: 3840, height: 2160), videoRect: video)
    #expect(abs(f.minX - 480) < 0.01 && abs(f.minY - 864) < 0.01)
    #expect(abs(f.width - 960) < 0.01 && abs(f.height - 108) < 0.01)
}

@Test func bitmapFrameTallCanvasOnCroppedVideo() {
    // 1920x1080-Fläche auf 1920x800-Video (beschnitten): Fläche mittig, ragt oben/unten 140 px hinaus.
    let video = CGRect(x: 0, y: 140, width: 1920, height: 800)
    let f = SubtitleGeometry.bitmapFrame(position: CGRect(x: 0, y: 0.9, width: 1, height: 0.05),
                                         canvas: CGSize(width: 1920, height: 1080),
                                         codedVideo: CGSize(width: 1920, height: 800), videoRect: video)
    // y im kodierten Bild: -140 + 972 = 832 → Bildschirm 140 + 832 = 972 (untere Leiste, wie von der Disc gedacht).
    #expect(abs(f.minY - 972) < 0.01)
    #expect(abs(f.height - 54) < 0.01)
}

@Test func bitmapFrameAnamorphicScalesPerAxis() {
    // 1440x1080 kodiert, angezeigt 1920x1080.
    let video = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let f = SubtitleGeometry.bitmapFrame(position: CGRect(x: 0.5, y: 0.5, width: 0.25, height: 0.1),
                                         canvas: CGSize(width: 1440, height: 1080),
                                         codedVideo: CGSize(width: 1440, height: 1080), videoRect: video)
    #expect(abs(f.minX - 960) < 0.01 && abs(f.width - 480) < 0.01)
    #expect(abs(f.minY - 540) < 0.01 && abs(f.height - 108) < 0.01)
}

@Test func anchorNumpad() {
    #expect(SubtitleGeometry.anchor(numpad: nil) == (0.5, 1.0))
    #expect(SubtitleGeometry.anchor(numpad: 1) == (0.0, 1.0))
    #expect(SubtitleGeometry.anchor(numpad: 5) == (0.5, 0.5))
    #expect(SubtitleGeometry.anchor(numpad: 9) == (1.0, 0.0))
    #expect(SubtitleGeometry.anchor(numpad: 42) == (0.5, 1.0))
}

@Test func cueActiveWindow() {
    #expect(SubtitleGeometry.isActive(start: 10, end: 12, at: 10))
    #expect(SubtitleGeometry.isActive(start: 10, end: 12, at: 11.99))
    #expect(!SubtitleGeometry.isActive(start: 10, end: 12, at: 12))
    #expect(!SubtitleGeometry.isActive(start: 10, end: 12, at: 9.9))
}
