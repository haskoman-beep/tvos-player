import SwiftUI
import Combine
import AetherEngine
import PlayerCore

extension AetherBackend {
    /// Untertitel-Ebene über der Surface: zeichnet die Cues der aktiven Spur, egal wer sie gewählt hat
    /// (Auto-Auswahl, Spur-Panel, Addon-Untertitel).
    func subtitleLayer(controlsVisible: Bool) -> some View {
        SubtitleOverlayView(engine: engine, controlsVisible: controlsVisible)
    }
}

/// Zeichnet `engine.subtitleCues` gegen `engine.clock.sourceTime`.
///
/// Takt: Die Uhr der Engine tickt mit etwa 10 Hz. Das Overlay hält nur die Liste der gerade aktiven
/// Cues als Zustand und ändert sie nur, wenn sich wirklich etwas ändert. Der Rest des Players baut
/// dadurch nicht mit 10 Hz neu, und auch dieses Overlay nur beim Wechsel eines Cues.
struct SubtitleOverlayView: View {
    let engine: AetherEngine
    var controlsVisible: Bool

    /// Gut lesbar auf einem 4K-Fernseher aus Sofa-Entfernung (tvOS-Punkte, 1920×1080).
    static let fontSize: CGFloat = 48
    static let outlineWidth: CGFloat = 2.5
    /// Abstand zum unteren Bildschirmrand ohne Steuerleiste.
    static let bottomMargin: CGFloat = 70
    /// So weit rücken untere Untertitel hoch, solange die Steuerleiste steht (Vorbild NuvioTVOS: 272).
    static let controlsLift: CGFloat = 272

    @State private var active: [SubtitleCue] = []
    @State private var nativeRendered = false

    var body: some View {
        GeometryReader { geo in
            let rect = SubtitleGeometry.videoRect(container: geo.size,
                                                  videoWidth: Int(engine.sourceVideoWidth),
                                                  videoHeight: Int(engine.sourceVideoHeight),
                                                  pixelAspect: engine.sourceVideoPixelAspectRatio)
            let lift = controlsVisible ? Self.controlsLift : 0
            ZStack(alignment: .topLeading) {
                if !nativeRendered {
                    ForEach(bitmapCues) { cue in
                        if case .image(let image) = cue.body { bitmap(image, in: rect, container: geo.size, lift: lift) }
                    }
                    ForEach(placedTextCues) { cue in
                        if let placement = cue.placement { placed(cue, placement, in: rect, lift: lift) }
                    }
                    VStack(spacing: 12) {
                        ForEach(bottomTextCues) { cue in textBody(cue, alignment: .center) }
                    }
                    .frame(maxWidth: max(min(rect.width, geo.size.width) * 0.86, 1))
                    .frame(width: geo.size.width, height: max(geo.size.height - Self.bottomMargin - lift, 1),
                           alignment: .bottom)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.22), value: controlsVisible)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onReceive(engine.clock.$sourceTime) { t in refresh(cues: engine.subtitleCues, at: t) }
        .onReceive(engine.$subtitleCues) { cues in refresh(cues: cues, at: engine.clock.sourceTime) }
        .onReceive(engine.$activeSubtitleTrackIndex) { id in
            let track = engine.subtitleTracks.first { $0.id == id }
            nativeRendered = track?.isNativelyRenderedSubtitle ?? false
        }
    }

    // MARK: Zeit

    private func refresh(cues: [SubtitleCue], at sourceTime: Double) {
        let t = sourceTime - engine.softwareSubtitleDelaySeconds
        let now = cues.filter { SubtitleGeometry.isActive(start: $0.startTime, end: $0.endTime, at: t) }
            .sorted { ($0.startTime, $0.id) < ($1.startTime, $1.id) }
        if now != active { active = now }
    }

    private var bitmapCues: [SubtitleCue] { active.filter { Self.isImage($0) } }
    private var placedTextCues: [SubtitleCue] { active.filter { !Self.isImage($0) && $0.placement != nil } }
    private var bottomTextCues: [SubtitleCue] { active.filter { !Self.isImage($0) && $0.placement == nil } }
    private static func isImage(_ c: SubtitleCue) -> Bool {
        if case .image = c.body { return true }
        return false
    }

    // MARK: Bild-Untertitel

    private func bitmap(_ image: SubtitleImage, in rect: CGRect, container: CGSize, lift: CGFloat) -> some View {
        let frame = SubtitleGeometry.bitmapFrame(position: image.position, canvas: image.canvasSize,
                                                 codedVideo: CGSize(width: Int(engine.sourceVideoWidth),
                                                                    height: Int(engine.sourceVideoHeight)),
                                                 videoRect: rect)
        // Nur Bilder in der unteren Hälfte weichen der Steuerleiste aus.
        let dy = frame.midY > container.height / 2 ? -lift : 0
        return Image(decorative: image.cgImage, scale: 1, orientation: .up)
            .resizable()
            .frame(width: max(frame.width, 1), height: max(frame.height, 1))
            .position(x: frame.midX, y: frame.midY + dy)
    }

    // MARK: Text mit eigener Lage (ASS \an / \pos)

    @ViewBuilder
    private func placed(_ cue: SubtitleCue, _ placement: SubtitleTextPlacement, in rect: CGRect, lift: CGFloat) -> some View {
        let anchor = SubtitleGeometry.anchor(numpad: placement.alignment)
        let textAlign: TextAlignment = anchor.x == 0 ? .leading : (anchor.x == 1 ? .trailing : .center)
        let dy = anchor.y == 1 ? -lift : 0
        if let p = placement.position {
            let x = rect.minX + min(max(p.x, 0), 1) * rect.width
            let y = rect.minY + min(max(p.y, 0), 1) * rect.height
            textBody(cue, alignment: textAlign)
                .frame(maxWidth: rect.width * 0.9)
                .fixedSize(horizontal: false, vertical: true)
                .position(x: x, y: y + dy)
        } else {
            let margin: CGFloat = 48
            textBody(cue, alignment: textAlign)
                .frame(maxWidth: rect.width * 0.86)
                .padding(.horizontal, margin)
                .padding(.vertical, anchor.y == 1 ? Self.bottomMargin : margin)
                .frame(width: rect.width, height: rect.height,
                       alignment: Alignment(horizontal: anchor.x == 0 ? .leading : (anchor.x == 1 ? .trailing : .center),
                                            vertical: anchor.y == 0 ? .top : (anchor.y == 1 ? .bottom : .center)))
                .position(x: rect.midX, y: rect.midY + dy)
        }
    }

    // MARK: Text

    @ViewBuilder
    private func textBody(_ cue: SubtitleCue, alignment: TextAlignment) -> some View {
        switch cue.body {
        case .text(let s):
            let parts = [Part(text: s)]
            outlined(fill: Self.attributed(parts, outline: false), stroke: Self.attributed(parts, outline: true), alignment: alignment)
        case .richText(let runs):
            let parts = runs.map { Part(text: $0.text, color: $0.color, bold: $0.isBold, italic: $0.isItalic,
                                        underline: $0.isUnderlined, strike: $0.isStruckThrough) }
            outlined(fill: Self.attributed(parts, outline: false), stroke: Self.attributed(parts, outline: true), alignment: alignment)
        case .image:
            EmptyView()
        }
    }

    /// Weiße Schrift mit schwarzem Rand: dieselbe Zeile achtmal schwarz versetzt dahinter, dazu ein weicher Schatten.
    private func outlined(fill: AttributedString, stroke: AttributedString, alignment: TextAlignment) -> some View {
        let w = Self.outlineWidth
        let offsets: [CGSize] = [CGSize(width: -w, height: -w), CGSize(width: 0, height: -w), CGSize(width: w, height: -w),
                                 CGSize(width: -w, height: 0), CGSize(width: w, height: 0),
                                 CGSize(width: -w, height: w), CGSize(width: 0, height: w), CGSize(width: w, height: w)]
        return ZStack {
            ForEach(offsets.indices, id: \.self) { i in
                Text(stroke).multilineTextAlignment(alignment).offset(offsets[i])
            }
            Text(fill).multilineTextAlignment(alignment)
        }
        .shadow(color: .black.opacity(0.55), radius: 6, x: 0, y: 2)
    }

    private struct Part {
        var text: String
        var color: SubtitleColor? = nil
        var bold = false, italic = false, underline = false, strike = false
    }

    /// Läufe als AttributedString. `outline` = Randkopie: alles schwarz, ohne Unter-/Durchstreichung.
    /// Schriftart und relative Größe aus ASS (\fn, \fs) werden bewusst ignoriert: eine feste, gut lesbare Größe.
    private static func attributed(_ parts: [Part], outline: Bool) -> AttributedString {
        var out = AttributedString()
        for p in parts {
            var a = AttributedString(p.text.replacingOccurrences(of: "\r\n", with: "\n"))
            var font = Font.system(size: fontSize, weight: p.bold ? .bold : .semibold)
            if p.italic { font = font.italic() }
            a.font = font
            if outline {
                a.foregroundColor = Color.black
            } else {
                let color: Color = p.color.map { Color(red: Double($0.r) / 255, green: Double($0.g) / 255, blue: Double($0.b) / 255) } ?? Color.white
                a.foregroundColor = color
                if p.underline { a.underlineStyle = Text.LineStyle.single }
                if p.strike { a.strikethroughStyle = Text.LineStyle.single }
            }
            out += a
        }
        return out
    }
}
