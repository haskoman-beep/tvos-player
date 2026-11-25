import SwiftUI
import PlayerCore

/// Task 5.3: what one episode shows, worked out once by `DetailView` (the button, focus and navigation stay there).
struct EpisodeLabelData {
    let number: Int
    let title: String
    let overview: String?
    let thumbnail: String?
    let watched: Bool
    /// Progress 0…1 of a started, unwatched episode (from 60 s on), else nil.
    let progress: Double?
    /// Spoiler protection: unwatched still blurred.
    let spoiler: Bool

    var heading: String { "\(number). \(title)" }
}

/// Task 5.3 (`episodes = reihe`, default): one card of the horizontal row: a 16:9 still with the watched mark and
/// the progress on the picture, the title „1. Name“ below; the description shows only while the card has the
/// focus (meta, space kept so the row never jumps).
struct EpisodeCardLabel: View {
    let data: EpisodeLabelData
    @Environment(\.isFocused) private var focused
    @Environment(\.theme) private var theme

    static let width: CGFloat = 400
    static let height: CGFloat = 225

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.xs) {
            still
            Text(data.heading).textRoleInRow(.rowTitleEmphasis).lineLimit(1)
            Text(data.overview ?? " ")
                .textRoleInRow(.rowDetail)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .opacity(focused && data.overview != nil ? 1 : 0)
        }
        .frame(width: Self.width, alignment: .leading)
    }

    private var still: some View {
        RemoteImage(url: data.thumbnail, maxPixels: 800, blur: data.spoiler ? SpoilerStill.blurRadius : 0)
            .frame(width: Self.width, height: Self.height)
            .clipped()
            .spoilerMark(data.spoiler)
            .overlay(alignment: .topTrailing) { watchedMark }
            .overlay(alignment: .bottom) { progressBar }
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.row, style: .continuous))
    }

    @ViewBuilder private var watchedMark: some View {
        if data.watched {
            Image(systemName: "checkmark.circle.fill")
                .font(theme.type.font(.sectionTitle))
                .foregroundStyle(Theme.Tone.ok.color)
                .padding(theme.space.xs)
                .background(Circle().fill(Theme.Palette.badgeOnImage))
                .padding(theme.space.xs)
                .accessibilityLabel("Gesehen")
        }
    }

    @ViewBuilder private var progressBar: some View {
        if let p = data.progress {
            ProgressView(value: p)
                .tint(theme.color.primary)
                .padding(.horizontal, theme.space.s)
                .padding(.bottom, theme.space.xs)
        }
    }
}

/// Task 5.3 (`episodes = liste`): today's list row (still left, title with mark or progress, two lines of text).
struct EpisodeListLabel: View {
    let data: EpisodeLabelData

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            RemoteImage(url: data.thumbnail, maxPixels: 560, blur: data.spoiler ? SpoilerStill.blurRadius : 0)
                .frame(width: 280, height: 158).clipped()
                .spoilerMark(data.spoiler)
            // Welle F-i: Farben aus den Tokens (`textRoleInRow`, Zeilenstil), kein Systemknopf mit Akzentfarbe.
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack {
                    Text(data.heading).textRoleInRow(.rowTitleEmphasis)
                    if data.watched {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Tone.ok.color)
                    } else if let p = data.progress {
                        ProgressView(value: p).frame(width: 120)
                    }
                }
                if let o = data.overview {
                    Text(o).textRoleInRow(.rowDetail).lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            Spacer()
        }
    }
}
