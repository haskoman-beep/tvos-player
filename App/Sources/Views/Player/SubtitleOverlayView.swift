import SwiftUI
import Combine
import AetherFEL
import PlayerCore

extension AetherBackend {
    /// Untertitel-Ebene über der Surface: zeichnet die Cues der aktiven Spur, egal wer sie gewählt hat
    /// (Auto-Auswahl, Spur-Panel, Addon-Untertitel).
    func subtitleLayer(controlsInset: CGFloat) -> some View {
        SubtitleOverlayView(engine: engine, controlsInset: controlsInset)
    }
}

/// Zeichnet `engine.subtitleCues` gegen `engine.clock.sourceTime`.
///
/// Takt: Die Uhr der Engine tickt mit etwa 10 Hz. Das Overlay hält nur die Liste der gerade aktiven
/// Cues als Zustand und ändert sie nur, wenn sich wirklich etwas ändert. Der Rest des Players baut
/// dadurch nicht mit 10 Hz neu, und auch dieses Overlay nur beim Wechsel eines Cues.
struct SubtitleOverlayView: View {
    let engine: AetherEngine
    /// 0 = Steuerleiste verborgen, sonst ihre gemessene Höhe.
    var controlsInset: CGFloat

    /// Wave U: size, outline, margin and background come from the profile (`SubtitleStyle`, default = the old
    /// fixed look: font 48, outline 2.5, 70 pt margin, soft shadow). HDR/DV sources use the HDR brightness.
    @Environment(\.subtitleStyle) private var style
    /// Ersatz für die Höhe der Steuerleiste, solange noch keine Messung da ist (Schätzwert 272 pt).
    static let fallbackControlsInset: CGFloat = 272
    /// Abstand der Untertitel über der Oberkante der Steuerleiste.
    static let controlsGap: CGFloat = 24

    @State private var active: [SubtitleCue] = []
    /// Sichtbare Zeilen, die im neuesten Cue-Fenster fehlen: bleiben bis zu ihrem Ende stehen (kein Flackern).
    @State private var carry: [SubtitleCue] = []
    @State private var trackID: Int?
    @State private var nativeRendered = false
    /// The source is HDR or Dolby Vision (engine `sourceVideoFormat`).
    @State private var hdr = false

    var body: some View {
        GeometryReader { geo in
            let rect = SubtitleGeometry.videoRect(container: geo.size,
                                                  videoWidth: Int(engine.sourceVideoWidth),
                                                  videoHeight: Int(engine.sourceVideoHeight),
                                                  pixelAspect: engine.sourceVideoPixelAspectRatio)
            let look = style.look(hdr: hdr)
            let bottom = look.bottomInset(controlsInset: controlsInset, gap: Self.controlsGap)
            let lift = look.textLift(controlsInset: controlsInset, gap: Self.controlsGap)
            let shift = look.bitmapShift(controlsInset: controlsInset, gap: Self.controlsGap)
            ZStack(alignment: .topLeading) {
                if !nativeRendered {
                    ForEach(bitmapCues) { cue in
                        if case .image(let image) = cue.body { bitmap(image, in: rect, container: geo.size, shift: shift) }
                    }
                    ForEach(placedTextCues) { cue in
                        if let placement = cue.placement { placed(cue, placement, in: rect, lift: lift, look: look) }
                    }
                    VStack(spacing: 12) {
                        ForEach(bottomTextCues) { cue in textBody(cue, alignment: .center, look: look) }
                    }
                    .frame(maxWidth: max(min(rect.width, geo.size.width) * 0.86, 1))
                    .frame(width: geo.size.width, height: max(geo.size.height - bottom, 1),
                           alignment: .bottom)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.22), value: controlsInset)
            .animation(.easeInOut(duration: 0.22), value: look.bottomMargin)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // @Published-Senken laufen in willSet: immer den übergebenen Wert nehmen, nicht die Eigenschaft.
        .onReceive(engine.clock.$sourceTime) { t in refresh(window: engine.subtitleCues, carry: carry, at: t) }
        .onReceive(engine.$subtitleCues) { cues in
            var held: [SubtitleCue] = []
            if !trackChanged(to: engine.activeSubtitleTrackIndex) {
                held = SubtitleCueHold.carry(visible: active + carry, newWindow: cues, at: time(engine.clock.sourceTime),
                                             id: \.id, start: \.startTime, end: \.endTime)
            }
            refresh(window: cues, carry: held, at: engine.clock.sourceTime)
        }
        .onReceive(engine.$activeSubtitleTrackIndex) { id in
            if trackChanged(to: id) { refresh(window: [], carry: [], at: engine.clock.sourceTime) }
            let track = engine.subtitleTracks.first { $0.id == id }
            nativeRendered = track?.isNativelyRenderedSubtitle ?? false
        }
        .onReceive(engine.$sourceVideoFormat) { f in
            let now = SubtitleStyle.isHDR(formatName: "\(f)")
            if now != hdr { hdr = now }
        }
    }

    // MARK: Zeit

    private func time(_ sourceTime: Double) -> Double { sourceTime - engine.softwareSubtitleDelaySeconds }

    /// Spurwechsel oder Aus: nichts halten, alte Zeilen sofort weg.
    private func trackChanged(to id: Int?) -> Bool {
        guard id != trackID else { return false }
        trackID = id
        return true
    }

    private func refresh(window: [SubtitleCue], carry held: [SubtitleCue], at sourceTime: Double) {
        let r = SubtitleCueHold.active(window: window, carry: held, at: time(sourceTime),
                                       id: \.id, start: \.startTime, end: \.endTime)
        if r.carry != carry { carry = r.carry }
        if r.active != active { active = r.active }
    }

    private var bitmapCues: [SubtitleCue] { active.filter { Self.isImage($0) } }
    private var placedTextCues: [SubtitleCue] { active.filter { !Self.isImage($0) && $0.placement != nil } }
    private var bottomTextCues: [SubtitleCue] { active.filter { !Self.isImage($0) && $0.placement == nil } }
    private static func isImage(_ c: SubtitleCue) -> Bool {
        if case .image = c.body { return true }
        return false
    }

    // MARK: Bild-Untertitel

    /// Image subtitles only take the position from the style (no size or colour).
    private func bitmap(_ image: SubtitleImage, in rect: CGRect, container: CGSize, shift: CGFloat) -> some View {
        let frame = SubtitleGeometry.bitmapFrame(position: image.position, canvas: image.canvasSize,
                                                 codedVideo: CGSize(width: Int(engine.sourceVideoWidth),
                                                                    height: Int(engine.sourceVideoHeight)),
                                                 videoRect: rect)
        // Only images in the lower half follow the chosen position and move above the controls.
        let dy = frame.midY > container.height / 2 ? shift : 0
        return Image(decorative: image.cgImage, scale: 1, orientation: .up)
            .resizable()
            .frame(width: max(frame.width, 1), height: max(frame.height, 1))
            .position(x: frame.midX, y: frame.midY + dy)
    }

    // MARK: Text mit eigener Lage (ASS \an / \pos)

    @ViewBuilder
    private func placed(_ cue: SubtitleCue, _ placement: SubtitleTextPlacement, in rect: CGRect, lift: CGFloat,
                        look: SubtitleLook) -> some View {
        let anchor = SubtitleGeometry.anchor(numpad: placement.alignment)
        let textAlign: TextAlignment = anchor.x == 0 ? .leading : (anchor.x == 1 ? .trailing : .center)
        let dy = anchor.y == 1 ? -lift : 0
        if let p = placement.position {
            let x = rect.minX + min(max(p.x, 0), 1) * rect.width
            let y = rect.minY + min(max(p.y, 0), 1) * rect.height
            textBody(cue, alignment: textAlign, look: look)
                .frame(maxWidth: rect.width * 0.9)
                .fixedSize(horizontal: false, vertical: true)
                .position(x: x, y: y + dy)
        } else {
            let margin: CGFloat = 48
            textBody(cue, alignment: textAlign, look: look)
                .frame(maxWidth: rect.width * 0.86)
                .padding(.horizontal, margin)
                .padding(.vertical, anchor.y == 1 ? look.bottomMargin : margin)
                .frame(width: rect.width, height: rect.height,
                       alignment: Alignment(horizontal: anchor.x == 0 ? .leading : (anchor.x == 1 ? .trailing : .center),
                                            vertical: anchor.y == 0 ? .top : (anchor.y == 1 ? .bottom : .center)))
                .position(x: rect.midX, y: rect.midY + dy)
        }
    }

    // MARK: Text

    @ViewBuilder
    private func textBody(_ cue: SubtitleCue, alignment: TextAlignment, look: SubtitleLook) -> some View {
        switch cue.body {
        case .text(let s):
            SubtitleTextView(parts: [SubtitleTextPart(text: SubtitleText.clean(s))], look: look, alignment: alignment)
        case .richText(let runs):
            let parts = runs.map { SubtitleTextPart(text: SubtitleText.clean($0.text, trim: false), color: $0.color, bold: $0.isBold,
                                                    italic: $0.isItalic, underline: $0.isUnderlined, strike: $0.isStruckThrough) }
            SubtitleTextView(parts: parts, look: look, alignment: alignment)
        case .image:
            EmptyView()
        }
    }
}
