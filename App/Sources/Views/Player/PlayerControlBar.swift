import SwiftUI
import PlayerCore

/// Task 5.4 (`player.controlBar`): the control bar over the video in three layouts.
/// - `minimal`: only timeline and times, 80 from the left/right screen edge, 60 from the bottom.
/// - `standard`: gradient from the bottom (420 high, black 85 % → 0), title, badges and the way into the panels above
///   the timeline.
/// - `ausfuehrlich`: `standard` plus chapter marks on the timeline and the gesture help line.
/// The bar has no focusable element: every remote key keeps reaching the play surface (gestures of Build 198).
struct PlayerControlBar: View {
    struct Content {
        var title: String
        var episodeLine: String?
        var position: Double
        var duration: Double
        var marks: [TimelineMark]
        /// Chapter starts as fractions 0…1 (shown only in `ausfuehrlich`).
        var chapters: [Double]
        var scrubTarget: Double?
        var current: Double
        var times: (leading: String, trailing: String)
        var badges: [String]
        /// "Ton … · Untertitel … · nach unten wischen: ändern"; nil = no tracks yet.
        var trackLine: String?
        /// "▲ Folgen · Kapitel · Infos" (side panel); nil = none.
        var sideHint: String?
        var sideHintSpoken: String?
        var gestureHint: String
    }

    let mode: LookControlBar
    let content: Content
    /// Height of the bar's content from the screen bottom (for the subtitle inset; the gradient does not count).
    var onHeight: (CGFloat) -> Void = { _ in }
    @Environment(\.theme) private var theme

    static let gradientHeight: CGFloat = 420
    static let edgeH: CGFloat = 80
    static let edgeBottom: CGFloat = 60

    var body: some View {
        stack
            .padding(.horizontal, Self.edgeH)
            .padding(.bottom, Self.edgeBottom)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
            .background(alignment: .bottom) {
                if mode != .minimal {
                    LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .bottom, endPoint: .top)
                        .frame(height: Self.gradientHeight)
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea(.container, edges: [.bottom, .horizontal])
    }

    @ViewBuilder private var stack: some View {
        VStack(alignment: .leading, spacing: theme.space.s) {
            if mode != .minimal { header }
            timeline
            times
            if mode == .ausfuehrlich {
                Text(content.gestureHint).textRole(.rowDetail).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: theme.space.xs) {
            Text(content.title).textRole(.sectionTitle).lineLimit(1)
            if let ep = content.episodeLine { Text(ep).textRole(.rowDetail).lineLimit(1) }
        }
        if !content.badges.isEmpty {
            HStack(spacing: theme.space.xs) {
                ForEach(content.badges, id: \.self) { b in
                    ThemeBadge(kind: .tech(.detail), text: b, spokenText: PlayerControlBar.spoken(b))
                }
            }
        }
        chips
    }

    /// The "buttons" of the configurator: the ways into Ton & Untertitel and the side panel, as hint chips without
    /// focus (they name the gesture; opening stays on the swipe/arrow of the play surface).
    @ViewBuilder private var chips: some View {
        if content.trackLine != nil || content.sideHint != nil {
            HStack(spacing: theme.space.s) {
                if let t = content.trackLine { chip(t, spoken: nil) }
                if let s = content.sideHint { chip(s, spoken: content.sideHintSpoken) }
            }
        }
    }

    private func chip(_ text: String, spoken: String?) -> some View {
        Text(text)
            .font(theme.type.font(.rowDetail))
            .foregroundStyle(theme.color.primary)
            .lineLimit(1)
            .padding(.horizontal, theme.space.s).padding(.vertical, theme.space.xs / 2)
            .background(theme.color.badgeFill, in: Capsule())
            .accessibilityLabel(spoken ?? text)
    }

    private var timeline: some View {
        PlayerTimeline(position: content.position, duration: content.duration, marks: content.marks,
                       chapters: mode == .ausfuehrlich ? content.chapters : [],
                       scrubTarget: content.scrubTarget, current: content.current)
    }

    private var times: some View {
        HStack {
            Text(content.times.leading)
            Spacer()
            Text(content.times.trailing)
        }
        .font(theme.type.font(.rowDetail).monospacedDigit())
        .foregroundStyle(theme.color.primary)
    }

    /// VoiceOver text of a short badge.
    static func spoken(_ badge: String) -> String? {
        switch badge {
        case "DV": "Dolby Vision"
        case "DD+": "Dolby Digital Plus"
        case "DD": "Dolby Digital"
        case "Atmos": "Dolby Atmos"
        default: nil
        }
    }
}

/// Task 5.4: what VoiceOver hears on the video surface and the actions it offers (play/pause, ±10 s). Applied to
/// the picture only, so the skip button and the cards over it stay their own elements.
struct PlayerSurfaceAccessibility: ViewModifier {
    let title: String
    let value: String
    let toggle: () -> Void
    let seek: (Double) -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(value)
            .accessibilityAction(named: Text("Wiedergabe/Pause")) { toggle() }
            .accessibilityAction(named: Text("10 Sekunden vor")) { seek(10) }
            .accessibilityAction(named: Text("10 Sekunden zurück")) { seek(-10) }
            .accessibilityAdjustableAction { dir in
                switch dir {
                case .increment: seek(10)
                case .decrement: seek(-10)
                @unknown default: break
                }
            }
    }
}

extension PlayerControls {
    /// Task 5.4: the stream's technical data for `PlayerBadgeSet` (engine values plus the data rate of the source:
    /// file size from the addon text over the running time).
    var streamTech: StreamTechInfo {
        let snap = (engine as? any PlaybackTechInfoSource)?.trackPanelTech
        var rate: Double?
        if let s = sideExtras?.links?.stream, engine.duration > 0 {
            var t = StreamTraits.parse(s)
            t.durationSeconds = engine.duration
            rate = t.bitrateMbps
        }
        return StreamTechInfo(videoWidth: snap?.videoWidth ?? engine.sourceVideoWidth,
                              videoFormat: snap?.sourceFormat ?? engine.sourceVideoFormatName,
                              videoCodec: snap?.videoCodec,
                              audio: engine.audioTracks.first { $0.id == engine.activeAudioID },
                              bitrateMbps: rate)
    }
}
