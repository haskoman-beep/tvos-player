import SwiftUI
import PlayerCore

/// Task 5.4: what the up-next surfaces show about the next episode.
struct UpNextInfo {
    /// "S1 F4 · Titel" (without episode data: the title of the next request).
    var episodeLine: String
    /// Still of the next episode (nil = none known).
    var image: String?
    /// Spoiler protection of unwatched stills (like the side panel).
    var blur: Bool

    func line(seconds: Int) -> String { "\(UpNextCountdown.line(seconds: seconds)) · \(episodeLine)" }
}

/// Task 5.4 (`player.upNext`): the up-next countdown in three layouts.
/// - `karte`: card bottom right (80 from the edges), 640 wide, still 200 high, title, buttons.
/// - `leiste`: a bar 80 from the left/right and 60 from the bottom, one line plus the buttons.
/// - `vollbild`: the next episode's still fills the screen (the player shrinks the video to 420 × 236 at the top
///   left, `PlayerUpNextFullScreen.videoScale`), the info sits bottom left.
/// User decision 26.11. (back to the plan): „Jetzt abspielen“ (`ThemeButton(.primary)`, first focus) and
/// „Abbrechen“ are real buttons; the player surface gives up its focus while the card stands. Menu, the vertical
/// swipe of the track style and Play/Pause keep working as before (cancel, cancel, play now).
struct PlayerUpNextView: View {
    let style: LookUpNext
    let seconds: Int
    let info: UpNextInfo
    let onPlay: () -> Void
    let onCancel: () -> Void
    /// Review M2: focus did not land on a button after the retries; the player surface takes over.
    let onFocusMissed: () -> Void
    @Environment(\.theme) private var theme
    @FocusState private var focus: Target?

    private enum Target: Hashable { case play, cancel }

    var body: some View {
        Group {
            switch style {
            case .karte: card
            case .leiste: bar
            case .vollbild: fullScreen
            }
        }
        .defaultFocus($focus, .play)
        .task {
            // Focus at once (the surface is no longer focusable), then retry while the card slides in (as
            // `PostPlayCard`); still no button focused after about 0.6 s: the surface takes over (review M2).
            focus = .play
            for _ in 0..<6 {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
                if focus != nil { return }
                focus = .play
            }
            try? await Task.sleep(for: .milliseconds(100))
            if !Task.isCancelled, focus == nil { onFocusMissed() }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            still.frame(width: 640, height: 200).clipped()
            VStack(alignment: .leading, spacing: theme.space.s) {
                Text(UpNextCountdown.line(seconds: seconds)).textRole(.rowTitleEmphasis).monospacedDigit()
                Text(info.episodeLine).textRole(.rowDetail).lineLimit(1)
                buttons
            }
            .padding(OverlayCardMetrics.padding)
        }
        .frame(width: 640, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous))
        .overlayCard()
        .padding(.trailing, 80).padding(.bottom, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .ignoresSafeArea()
    }

    private var bar: some View {
        HStack(spacing: theme.space.m) {
            Text(info.line(seconds: seconds)).textRole(.rowTitle).monospacedDigit().lineLimit(1)
            Spacer(minLength: theme.space.m)
            buttons
        }
        .padding(.horizontal, OverlayCardMetrics.padding).padding(.vertical, theme.space.m)
        .overlayCard()
        .padding(.horizontal, 80).padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
    }

    private var fullScreen: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .bottom, endPoint: .top)
                .frame(height: 520).frame(maxHeight: .infinity, alignment: .bottom)
            VStack(alignment: .leading, spacing: theme.space.s) {
                Text(UpNextCountdown.line(seconds: seconds)).textRole(.sectionTitle).monospacedDigit()
                Text(info.episodeLine).textRole(.rowTitle).lineLimit(2)
                buttons
            }
            .frame(maxWidth: 1100, alignment: .leading)
            .padding(.leading, 80).padding(.bottom, 80)
        }
        .ignoresSafeArea()
    }

    /// Background of `vollbild`: drawn by the player under the shrunk video.
    static func backdrop(_ info: UpNextInfo) -> some View {
        RemoteImage(url: info.image, maxPixels: 1920, blur: info.blur ? SpoilerStill.blurRadius : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    private var still: some View {
        RemoteImage(url: info.image, maxPixels: 640, blur: info.blur ? SpoilerStill.blurRadius : 0)
            .spoilerMark(info.blur && info.image != nil)
    }

    private var buttons: some View {
        HStack(spacing: theme.space.s) {
            Button { onPlay() } label: { ThemeButtonLabel("Jetzt abspielen", symbol: "play.fill") }
                .buttonStyle(ThemeButton(.primary))
                .focused($focus, equals: .play)
            Button { onCancel() } label: { ThemeButtonLabel("Abbrechen", symbol: "xmark") }
                .buttonStyle(ThemeButton(.secondary))
                .focused($focus, equals: .cancel)
        }
        .fixedSize()
        .focusSection()
    }
}

/// Task 5.4: the shrunk video of `upNext = vollbild` (420 × 236 at 36/36 on the 1920 × 1080 screen).
enum PlayerUpNextFullScreen {
    static let videoScale: CGFloat = 420 / 1920
    static let videoInset: CGFloat = 36
}

extension PlayerControls {
    /// Task 5.4: next episode for the up-next surfaces (season/episode, title and still from the side extras).
    var upNextInfo: UpNextInfo {
        guard let n = sideExtras?.request?.nextRequest, let s = n.season, let e = n.episode else {
            return UpNextInfo(episodeLine: nextTitle ?? "", image: nil, blur: false)
        }
        let t = n.episodes.first { $0.season == s && $0.episode == e }?.title.flatMap { $0.isEmpty ? nil : $0 }
        let line = t.map { "S\(s) F\(e) · \($0)" } ?? "S\(s) F\(e)"
        return UpNextInfo(episodeLine: line, image: sideExtras?.thumbnail(season: s, episode: e),
                          blur: sideExtras?.blursStill(season: s, episode: e) ?? false)
    }
}
