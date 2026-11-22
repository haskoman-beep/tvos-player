import Foundation
import Testing
@testable import PlayerCore

// Wave U: subtitle look (size, position, outline, background, HDR brightness).

@Test func subtitleStyleDefaultIsTheOldFixedLook() {
    let look = SubtitleStyle().look(hdr: false)
    #expect(look.fontSize == 48)
    #expect(look.outlineWidth == 2.5)
    #expect(look.bottomMargin == 70)
    #expect(look.background == .shadow)
    #expect(look.textBrightness == 1)
    // Default HDR brightness is also full white: nothing changes until the user picks a value.
    #expect(SubtitleStyle().look(hdr: true) == look)
    #expect(SubtitleLook.standard == look)
    #expect(Profile(name: "x").subtitleStyle == SubtitleStyle())
}

@Test func subtitleStyleDecodesLenientlyAndRoundTrips() throws {
    // Older profile without the field: default style.
    let old = try JSONDecoder().decode(Profile.self, from: Data(#"{"id":"\#(UUID().uuidString)","name":"a"}"#.utf8))
    #expect(old.subtitleStyle == SubtitleStyle())
    // Unknown values (newer app) fall back per field, known ones are kept; brightness is clamped.
    let mixed = try JSONDecoder().decode(SubtitleStyle.self,
                                         from: Data(#"{"size":"huge","position":"high","outline":7,"background":"box","hdrBrightness":5}"#.utf8))
    #expect(mixed.size == .normal && mixed.position == .high && mixed.outline == .normal && mixed.background == .box)
    #expect(mixed.hdrBrightness == 40)
    var p = Profile(name: "x")
    p.subtitleStyle = SubtitleStyle(size: .large, position: .raised, outline: .strong, background: .none, hdrBrightness: 70)
    let back = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(p))
    #expect(back.subtitleStyle == p.subtitleStyle)
}

@Test func subtitleStyleStepsAreOrdered() {
    let sizes = SubtitleStyle.Size.allCases.map(\.points)
    #expect(sizes == sizes.sorted() && Set(sizes).count == sizes.count)
    let margins = SubtitleStyle.Position.allCases.map(\.bottomMargin)
    #expect(margins == margins.sorted() && Set(margins).count == margins.count)
    #expect(SubtitleStyle.Outline.none.width == 0)
    #expect(SubtitleStyle.hdrBrightnessChoices.first == 100)
    #expect(SubtitleStyle.hdrBrightnessChoices.allSatisfy { SubtitleStyle.clampBrightness($0) == $0 })
    #expect(SubtitleStyle.clampBrightness(150) == 100)
}

@Test func subtitleHDRBrightnessOnlyForHDRSources() {
    let s = SubtitleStyle(hdrBrightness: 70)
    #expect(s.look(hdr: false).textBrightness == 1)
    #expect(abs(s.look(hdr: true).textBrightness - 0.7) < 1e-9)
    for f in ["dolbyVision", "hdr10", "hdr10Plus", "hlg"] { #expect(SubtitleStyle.isHDR(formatName: f)) }
    for f in ["sdr", "", "unknown"] { #expect(!SubtitleStyle.isHDR(formatName: f)) }
    #expect(!SubtitleStyle.isHDR(formatName: nil))
    // White becomes grey, colours keep their hue (all channels scaled alike).
    let look = s.look(hdr: true)
    let w = look.dimmed(red: 1, green: 1, blue: 1)
    #expect(abs(w.red - 0.7) < 1e-9 && w.red == w.green && w.green == w.blue)
    let y = look.dimmed(red: 1, green: 1, blue: 0)
    #expect(abs(y.red - 0.7) < 1e-9 && y.blue == 0)
}

@Test func subtitleLayoutKeepsTheOldLiftAtDefault() {
    let look = SubtitleStyle().look(hdr: false)
    // Controls hidden: margin, no lift, image subtitles stay where they are.
    #expect(look.bottomInset(controlsInset: 0, gap: 24) == 70)
    #expect(look.textLift(controlsInset: 0, gap: 24) == 0)
    #expect(look.bitmapShift(controlsInset: 0, gap: 24) == 0)
    // Controls 272 pt: above them like before (272 + 24), lift 226 for text and images.
    #expect(look.bottomInset(controlsInset: 272, gap: 24) == 296)
    #expect(look.textLift(controlsInset: 272, gap: 24) == 226)
    #expect(look.bitmapShift(controlsInset: 272, gap: 24) == -226)
}

@Test func subtitleLayoutFollowsTheChosenPosition() {
    let high = SubtitleStyle(position: .high).look(hdr: false)
    #expect(high.bottomInset(controlsInset: 0, gap: 24) == 180)
    #expect(high.bitmapShift(controlsInset: 0, gap: 24) == -110)
    // Low controls: the higher of both wins, never below the chosen position.
    #expect(high.bottomInset(controlsInset: 100, gap: 24) == 180)
    #expect(high.textLift(controlsInset: 100, gap: 24) == 0)
    #expect(high.bottomInset(controlsInset: 272, gap: 24) == 296)
    let low = SubtitleStyle(position: .low).look(hdr: false)
    #expect(low.bottomInset(controlsInset: 0, gap: 24) == 40)
    // Image subtitles never move below their own position (overscan).
    #expect(low.bitmapShift(controlsInset: 0, gap: 24) == 0)
    #expect(low.bitmapShift(controlsInset: 272, gap: 24) == -226)
}
