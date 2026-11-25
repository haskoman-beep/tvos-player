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

    func line(seconds: Int) -> String { "Nächste Folge in \(seconds) s · \(episodeLine)" }
}

/// Task 5.4 (`player.upNext`): the up-next countdown in three layouts.
/// - `karte`: card bottom right (80 from the edges), 640 wide, still 200 high, title, buttons.
/// - `leiste`: a bar 80 from the left/right and 60 from the bottom, one line plus the buttons.
/// - `vollbild`: the next episode's still fills the screen (the player shrinks the video to 420 × 236 at the top
///   left, `PlayerUpNextFullScreen.videoScale`), the info sits bottom left.
/// Nothing here takes focus: as before (Build 198), a click on the play surface starts the next episode and an
/// arrow or swipe cancels. The buttons are labels that name those two ways.
struct PlayerUpNextView: View {
    let style: LookUpNext
    let seconds: Int
    let info: UpNextInfo
    @Environment(\.theme) private var theme

    var body: some View {
        switch style {
        case .karte: card
        case .leiste: bar
        case .vollbild: fullScreen
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            still.frame(width: 640, height: 200).clipped()
            VStack(alignment: .leading, spacing: theme.space.s) {
                Text("Nächste Folge in \(seconds) s").textRole(.rowTitleEmphasis).monospacedDigit()
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
                Text("Nächste Folge in \(seconds) s").textRole(.sectionTitle).monospacedDigit()
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
            // Label only (a click on the surface starts): the resting face of ThemeButton(.primary) / (.secondary).
            UpNextButtonLabel(text: "Jetzt abspielen", symbol: "play.fill", primary: true)
            UpNextButtonLabel(text: "Abbrechen", symbol: nil, primary: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Klicken: jetzt abspielen. Wischen: abbrechen.")
    }
}

/// A button face without focus (see `PlayerUpNextView`): primary = the resting `ThemeButton(.primary)` (accent,
/// `onAccent` text), otherwise `badgeFill`.
private struct UpNextButtonLabel: View {
    let text: String
    let symbol: String?
    let primary: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: theme.space.xs) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(theme.type.font(.rowTitleEmphasis))
        .foregroundStyle(primary ? theme.color.onAccent : theme.color.primary)
        .padding(.horizontal, theme.space.m).padding(.vertical, theme.space.xs)
        .background(primary ? theme.color.accent.opacity(ThemeButton.primaryRestOpacity) : theme.color.badgeFill,
                    in: RoundedRectangle(cornerRadius: theme.radius.row, style: .continuous))
        .lineLimit(1)
        .fixedSize()
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
