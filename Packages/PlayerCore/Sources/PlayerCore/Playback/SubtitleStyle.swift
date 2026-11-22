import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Wave U: look of text subtitles (size, position, outline, background) plus a separate text brightness for
/// HDR/Dolby Vision, because full white is blinding at HDR peak. Stored in the profile (`Profile.subtitleStyle`),
/// synced with it. The defaults reproduce the fixed look from before wave U (font 48, outline 2.5, soft shadow,
/// 70 pt above the bottom edge, full white).
///
/// Image subtitles (PGS/DVB/DVD) only take the position; they cannot be resized or recoloured here.
public struct SubtitleStyle: Codable, Sendable, Equatable {
    public enum Size: String, Codable, Sendable, CaseIterable {
        case small, normal, large, extraLarge

        /// Font size in tvOS points (1920×1080 layout).
        public var points: CGFloat {
            switch self {
            case .small: 40
            case .normal: 48
            case .large: 58
            case .extraLarge: 70
            }
        }

        public var title: String {
            switch self {
            case .small: "Klein"
            case .normal: "Normal"
            case .large: "Groß"
            case .extraLarge: "Sehr groß"
            }
        }
    }

    public enum Position: String, Codable, Sendable, CaseIterable {
        case low, standard, raised, high

        /// Distance of the bottom line from the bottom screen edge while the controls are hidden (points).
        public var bottomMargin: CGFloat {
            switch self {
            case .low: 40
            case .standard: 70
            case .raised: 120
            case .high: 180
            }
        }

        public var title: String {
            switch self {
            case .low: "Am Rand"
            case .standard: "Standard"
            case .raised: "Angehoben"
            case .high: "Hoch"
            }
        }
    }

    public enum Outline: String, Codable, Sendable, CaseIterable {
        case none, thin, normal, strong

        /// Offset of the black outline copies in points (0 = no outline).
        public var width: CGFloat {
            switch self {
            case .none: 0
            case .thin: 1.5
            case .normal: 2.5
            case .strong: 4
            }
        }

        public var title: String {
            switch self {
            case .none: "Keiner"
            case .thin: "Dünn"
            case .normal: "Normal"
            case .strong: "Stark"
            }
        }
    }

    public enum Background: String, Codable, Sendable, CaseIterable {
        /// Plain text (outline only).
        case none
        /// Dark half-transparent box behind each line block.
        case box
        /// Soft drop shadow (the look before wave U).
        case shadow

        public var title: String {
            switch self {
            case .none: "Keiner"
            case .box: "Kasten"
            case .shadow: "Schatten"
            }
        }
    }

    /// Selectable HDR/DV text brightness in percent. Below 40 % white text turns into a hard-to-read grey.
    public static let hdrBrightnessChoices = [100, 85, 70, 55, 40]
    public static let defaultHDRBrightness = 100

    public var size: Size
    public var position: Position
    public var outline: Outline
    public var background: Background
    /// Text brightness in percent while the TV presents HDR or Dolby Vision (SDR always 100 %). A perceptual step:
    /// it scales the gamma-encoded colour, so 70 % is about 46 % luminance and 40 % about 13 %.
    public var hdrBrightness: Int

    public init(size: Size = .normal, position: Position = .standard, outline: Outline = .normal,
                background: Background = .shadow, hdrBrightness: Int = SubtitleStyle.defaultHDRBrightness) {
        self.size = size
        self.position = position
        self.outline = outline
        self.background = background
        self.hdrBrightness = Self.clampBrightness(hdrBrightness)
    }

    enum CodingKeys: String, CodingKey { case size, position, outline, background, hdrBrightness }

    /// Missing or unknown values (older or newer app) fall back to the default per field.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SubtitleStyle()
        size = (try? c.decodeIfPresent(Size.self, forKey: .size)) ?? nil ?? d.size
        position = (try? c.decodeIfPresent(Position.self, forKey: .position)) ?? nil ?? d.position
        outline = (try? c.decodeIfPresent(Outline.self, forKey: .outline)) ?? nil ?? d.outline
        background = (try? c.decodeIfPresent(Background.self, forKey: .background)) ?? nil ?? d.background
        hdrBrightness = Self.clampBrightness((try? c.decodeIfPresent(Int.self, forKey: .hdrBrightness)) ?? nil ?? d.hdrBrightness)
    }

    /// Keeps the stored value readable: 40…100 %.
    public static func clampBrightness(_ v: Int) -> Int { min(max(v, 40), 100) }

    public static func brightnessTitle(_ percent: Int) -> String { percent >= 100 ? "100 % (wie SDR)" : "\(percent) %" }

    /// Is the format (name of the engine `VideoFormat` case, use the presented output) HDR or Dolby Vision?
    public static func isHDR(formatName: String?) -> Bool {
        switch formatName?.lowercased() {
        case "dolbyvision", "hdr10", "hdr10plus", "hlg": true
        default: false
        }
    }

    /// Concrete numbers for the overlay. `hdr`: the TV presents an HDR/DV picture (the output format, not the source).
    public func look(hdr: Bool) -> SubtitleLook {
        SubtitleLook(fontSize: size.points, outlineWidth: outline.width, bottomMargin: position.bottomMargin,
                     background: background, textBrightness: hdr ? Double(Self.clampBrightness(hdrBrightness)) / 100 : 1)
    }

    /// One line for logs and summaries, e.g. "Normal · Standard · Umriss Normal · Schatten · HDR 70 %".
    public var summary: String {
        "\(size.title) · \(position.title) · Umriss \(outline.title) · \(background.title) · HDR \(hdrBrightness) %"
    }
}

/// Resolved subtitle look for one frame (see `SubtitleStyle.look(hdr:)`).
public struct SubtitleLook: Sendable, Equatable {
    public var fontSize: CGFloat
    public var outlineWidth: CGFloat
    public var bottomMargin: CGFloat
    public var background: SubtitleStyle.Background
    /// Multiplier 0.4…1 for the text colour (outline and box stay black).
    public var textBrightness: Double

    public init(fontSize: CGFloat, outlineWidth: CGFloat, bottomMargin: CGFloat,
                background: SubtitleStyle.Background, textBrightness: Double) {
        self.fontSize = fontSize
        self.outlineWidth = outlineWidth
        self.bottomMargin = bottomMargin
        self.background = background
        self.textBrightness = textBrightness
    }

    /// The default look (same as before wave U).
    public static let standard = SubtitleStyle().look(hdr: false)

    /// Text colour scaled by the brightness (0…1 per gamma-encoded channel, a perceptual step, not linear light).
    /// White at 70 % → 0.7 grey; colours keep their hue.
    public func dimmed(red: Double, green: Double, blue: Double) -> (red: Double, green: Double, blue: Double) {
        let f = min(max(textBrightness, 0), 1)
        return (min(max(red, 0), 1) * f, min(max(green, 0), 1) * f, min(max(blue, 0), 1) * f)
    }

    /// Bottom edge of the subtitle block above the screen edge: the chosen margin, or above the visible
    /// controls (`controlsInset` > 0) plus `gap`, whichever is higher.
    public func bottomInset(controlsInset: CGFloat, gap: CGFloat) -> CGFloat {
        controlsInset > 0 ? max(controlsInset + gap, bottomMargin) : bottomMargin
    }

    /// Lift of text with its own bottom anchor (ASS \an1-3), which already sits at `bottomMargin`.
    public func textLift(controlsInset: CGFloat, gap: CGFloat) -> CGFloat {
        max(0, bottomInset(controlsInset: controlsInset, gap: gap) - bottomMargin)
    }

    /// Vertical shift of an image subtitle in the lower half (negative = up). Image subtitles bring their own
    /// position, which matches the standard margin; the chosen position and the controls move them from there.
    /// Only upwards: a lower position would push a disc subtitle near the screen edge (overscan).
    public func bitmapShift(controlsInset: CGFloat, gap: CGFloat) -> CGFloat {
        min(0, -(bottomInset(controlsInset: controlsInset, gap: gap) - SubtitleStyle.Position.standard.bottomMargin))
    }
}
