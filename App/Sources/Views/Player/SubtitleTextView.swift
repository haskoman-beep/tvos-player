import SwiftUI
import AetherFEL
import PlayerCore

// Wave U: drawing of one subtitle text block with the profile's style. Used by the player overlay
// (SubtitleOverlayView) and the live preview on the settings page, so both look exactly the same.

private struct SubtitleStyleKey: EnvironmentKey {
    static let defaultValue = SubtitleStyle()
}

extension EnvironmentValues {
    /// Subtitle style of the active profile; set once at the subtitle layer in PlayerScreen.
    var subtitleStyle: SubtitleStyle {
        get { self[SubtitleStyleKey.self] }
        set { self[SubtitleStyleKey.self] = newValue }
    }
}

/// One run of subtitle text with the formatting the cue carries (ASS/WebVTT tags).
struct SubtitleTextPart {
    var text: String
    var color: SubtitleColor? = nil
    var bold = false, italic = false, underline = false, strike = false
}

/// White (or cue-coloured) text with a black outline, optional box or soft shadow, sized by `look`.
struct SubtitleTextView: View {
    let parts: [SubtitleTextPart]
    let look: SubtitleLook
    var alignment: TextAlignment = .center

    var body: some View {
        let fill = Self.attributed(parts, look: look, outline: false)
        let core = ZStack {
            if look.outlineWidth > 0 {
                let stroke = Self.attributed(parts, look: look, outline: true)
                let w = look.outlineWidth
                // The same line eight times in black, offset around the text.
                let offsets: [CGSize] = [CGSize(width: -w, height: -w), CGSize(width: 0, height: -w), CGSize(width: w, height: -w),
                                         CGSize(width: -w, height: 0), CGSize(width: w, height: 0),
                                         CGSize(width: -w, height: w), CGSize(width: 0, height: w), CGSize(width: w, height: w)]
                ForEach(offsets.indices, id: \.self) { i in
                    Text(stroke).multilineTextAlignment(alignment).offset(offsets[i])
                }
            }
            Text(fill).multilineTextAlignment(alignment)
        }
        switch look.background {
        case .shadow:
            core.shadow(color: .black.opacity(0.55), radius: 6, x: 0, y: 2)
        case .box:
            core
                .padding(.horizontal, look.fontSize * 0.4)
                .padding(.vertical, look.fontSize * 0.12)
                .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: look.fontSize * 0.18, style: .continuous))
        case .none:
            core
        }
    }

    /// Runs as an AttributedString. `outline` = outline copy: all black, without underline/strikethrough.
    /// Font face and relative size from ASS (\fn, \fs) are ignored on purpose: one fixed, readable size.
    static func attributed(_ parts: [SubtitleTextPart], look: SubtitleLook, outline: Bool) -> AttributedString {
        var out = AttributedString()
        for p in parts {
            var a = AttributedString(p.text)
            var font = Font.system(size: look.fontSize, weight: p.bold ? .bold : .semibold)
            if p.italic { font = font.italic() }
            a.font = font
            if outline {
                a.foregroundColor = Color.black
            } else {
                let rgb = p.color.map { (Double($0.r) / 255, Double($0.g) / 255, Double($0.b) / 255) } ?? (1, 1, 1)
                let c = look.dimmed(red: rgb.0, green: rgb.1, blue: rgb.2)
                a.foregroundColor = Color(red: c.red, green: c.green, blue: c.blue)
                if p.underline { a.underlineStyle = Text.LineStyle.single }
                if p.strike { a.strikethroughStyle = Text.LineStyle.single }
            }
            out += a
        }
        return out
    }
}
