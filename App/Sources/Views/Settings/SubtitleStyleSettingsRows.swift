import SwiftUI
import PlayerCore

/// Wave U: entry row for the subtitle look (one self-contained component; since the wave S merge in „Sprache & Untertitel“,
/// between „Sprache“ and „Merken“). Stored in the profile (`Profile.subtitleStyle`) and synced with it.
struct SubtitleStyleSettingsRows: View {
    @Environment(AppModel.self) var model

    private let tint = SettingsCategory.audio.tint

    var body: some View {
        let s = model.profile.subtitleStyle
        SettingsSection {
            SettingsLinkRow(symbol: "textformat.size", tint: tint, title: "Untertitel-Aussehen",
                            detail: "Größe, Lage, Umriss, Hintergrund und Helligkeit bei HDR, mit Vorschau.",
                            value: s == SubtitleStyle() ? "Standard" : "Eigener Stil") {
                SubtitleStyleSettingsPage()
            }
        }
    }
}

/// Subpage with a live preview on top (dark and bright sample picture) and one row per setting.
/// Every row switches on OK to the next value, so the preview stays visible while choosing.
struct SubtitleStyleSettingsPage: View {
    @Environment(AppModel.self) var model
    @FocusState private var focus: Field?

    private let tint = SettingsCategory.audio.tint

    enum Field: Hashable { case size, position, outline, background, hdr, reset }

    var body: some View {
        let s = model.profile.subtitleStyle
        SettingsSubpage(title: "Untertitel-Aussehen",
                        summary: "Gilt für Text-Untertitel (SRT, VTT, ASS). Bild-Untertitel (PGS) folgen nur der Lage.") {
            SubtitleStylePreview(style: s, hdr: focus == .hdr)
            SettingsSection {
                cycleRow(.size, symbol: "textformat.size", title: "Größe",
                         options: SubtitleStyle.Size.allCases, keyPath: \.size, label: { $0.title })
                cycleRow(.position, symbol: "arrow.up.and.down.text.horizontal", title: "Lage",
                         detail: "Abstand vom unteren Bildrand. Bild-Untertitel werden nur angehoben.",
                         options: SubtitleStyle.Position.allCases, keyPath: \.position, label: { $0.title })
                cycleRow(.outline, symbol: "character.textbox", title: "Umriss",
                         options: SubtitleStyle.Outline.allCases, keyPath: \.outline, label: { $0.title })
                cycleRow(.background, symbol: "rectangle.fill", title: "Hintergrund",
                         options: SubtitleStyle.Background.allCases, keyPath: \.background, label: { $0.title })
                cycleRow(.hdr, symbol: "sun.max", title: "Helligkeit bei HDR/Dolby Vision",
                         detail: "Weißer Text blendet bei HDR. Die Vorschau zeigt den Wert, solange diese Zeile gewählt ist.",
                         options: SubtitleStyle.hdrBrightnessChoices, keyPath: \.hdrBrightness,
                         label: SubtitleStyle.brightnessTitle)
                if s != SubtitleStyle() {
                    SettingsRow(symbol: "arrow.uturn.backward", tint: tint, title: "Standard wiederherstellen",
                                reserveDetailSpace: false) {
                        focus = .size
                        model.update { $0.subtitleStyle = SubtitleStyle() }
                        RemoteLog.info("einstellung", "Untertitel-Aussehen: Standard")
                    }
                    .focused($focus, equals: .reset)
                }
            }
        }
    }

    /// OK switches to the next value (wraps around) and logs the new look.
    private func cycleRow<V: Equatable>(_ field: Field, symbol: String, title: String, detail: String? = nil,
                                        options: [V], keyPath: WritableKeyPath<SubtitleStyle, V>,
                                        label: @escaping (V) -> String) -> some View {
        let current = model.profile.subtitleStyle[keyPath: keyPath]
        return SettingsRow(symbol: symbol, tint: tint, title: title, detail: detail, accessory: .value(label(current)),
                           detailAlwaysVisible: field == .hdr, reserveDetailSpace: false) {
            guard !options.isEmpty else { return }
            let next = options.firstIndex(of: current).map { options[(options.index(after: $0)) % options.count] } ?? options[0]
            model.update { $0.subtitleStyle[keyPath: keyPath] = next }
            RemoteLog.info("einstellung", "Untertitel-Aussehen › \(title): \(label(next)) (\(model.profile.subtitleStyle.summary))")
        }
        .focused($focus, equals: field)
    }
}

/// Two scaled-down 1920×1080 frames (dark night scene, bright snow scene) with two sample lines, drawn by the
/// same view as the player overlay. `hdr`: show the HDR/DV brightness instead of SDR.
struct SubtitleStylePreview: View {
    let style: SubtitleStyle
    var hdr = false

    private static let frame = CGSize(width: 1920, height: 1080)
    private static let tileWidth: CGFloat = 440
    private static let sample = [SubtitleTextPart(text: "Wir müssen los, bevor es dunkel wird.\nIch hole nur noch schnell die Jacke.")]

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            tile(title: hdr ? "Dunkles Bild · HDR/DV" : "Dunkles Bild", picture: Self.dark)
            tile(title: hdr ? "Helles Bild · HDR/DV" : "Helles Bild", picture: Self.bright)
        }
        .padding(.horizontal, Theme.Space.m)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vorschau: \(style.summary)")
    }

    private func tile(title: String, picture: LinearGradient) -> some View {
        let scale = Self.tileWidth / Self.frame.width
        let look = style.look(hdr: hdr)
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            ZStack(alignment: .topLeading) {
                picture
                SubtitleTextView(parts: Self.sample, look: look)
                    .frame(maxWidth: Self.frame.width * 0.86)
                    .frame(width: Self.frame.width, height: Self.frame.height - look.bottomMargin, alignment: .bottom)
            }
            .frame(width: Self.frame.width, height: Self.frame.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: Self.frame.width * scale, height: Self.frame.height * scale, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(.easeInOut(duration: 0.2), value: style)
            .animation(.easeInOut(duration: 0.2), value: hdr)
            Text(title).textRole(.rowDetail)
        }
    }

    /// Night scene: dark blue sky to almost black ground.
    private static let dark = LinearGradient(colors: [Color(red: 0.06, green: 0.08, blue: 0.16), Color(red: 0.03, green: 0.03, blue: 0.05),
                                                      Color(red: 0.08, green: 0.07, blue: 0.06)],
                                             startPoint: .top, endPoint: .bottom)
    /// Bright scene: blue sky to snow, white right where the subtitles sit.
    private static let bright = LinearGradient(colors: [Color(red: 0.45, green: 0.68, blue: 0.92), Color(red: 0.82, green: 0.89, blue: 0.95),
                                                        Color(red: 0.97, green: 0.97, blue: 0.96)],
                                               startPoint: .top, endPoint: .bottom)
}
