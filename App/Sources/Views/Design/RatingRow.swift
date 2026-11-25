import SwiftUI
import PlayerCore

/// Task 5.3: the brand colours of the rating sources, as tokens (only the source name is coloured, never a foreign
/// logo). Moved here from `InfoBadges`, which forwards to it.
enum RatingColors {
    static let imdb = ThemeValues.rgb(0xF5C518)
    static let letterboxd = ThemeValues.rgb(0x00E054)
    static let trakt = ThemeValues.rgb(0xED1C24)
    static let tmdb = ThemeValues.rgb(0x01D1D9)

    /// Colour of the source name; unknown sources in the text colour.
    static func brand(_ source: String) -> Color {
        switch source {
        case "imdb": imdb
        case "letterboxd": letterboxd
        case "trakt": trakt
        case "tmdb": tmdb
        default: Theme.Palette.primary
        }
    }
}

/// Task 5.3 (`detail.ratingStyle`): the ratings of a title in one of three forms.
/// - `symbole`: symbol (or brand name) plus number per source (`ThemeBadge(rating:)`, today's row).
/// - `text`: one meta line „IMDb 7,9   Tomatometer 92 %   Trakt 81 %“ (`DetailLook.ratingLine`).
/// - `kacheln`: a tile per source, the source small on top (white 60 %), the value below; surface white 10 %,
///   inner spacing 10/16, radius 12, at least 110 wide.
/// The row never wraps; the caller drops ratings that do not fit (`ViewThatFits`).
struct RatingRow: View {
    let ratings: [RatingBadge]
    let style: LookRatingStyle

    var body: some View {
        switch style {
        case .symbole: symbols
        case .text: line
        case .kacheln: tiles
        }
    }

    private var symbols: some View {
        HStack(spacing: Theme.Space.m) {
            ForEach(ratings) { ThemeBadge(rating: $0, brandColor: RatingColors.brand($0.source)) }
        }
    }

    @ViewBuilder private var line: some View {
        if let text = DetailLook.ratingLine(ratings) {
            Text(text)
                .textRole(.rowDetail)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel(text.replacingOccurrences(of: "\u{00A0}", with: " "))
        }
    }

    private var tiles: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(ratings) { RatingTile(rating: $0) }
        }
    }
}

/// One tile of `ratingStyle = kacheln`.
private struct RatingTile: View {
    let rating: RatingBadge
    @Environment(\.theme) private var theme

    private static let minWidth: CGFloat = 110
    private static let radius: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.xxs) {
            Text(DetailLook.ratingName(rating))
                .font(theme.type.font(.badge))
                .foregroundStyle(Color.white.opacity(0.6))
            Text(rating.displayValue)
                .font(theme.type.font(.rowTitleEmphasis))
                .foregroundStyle(theme.color.primary)
                .monospacedDigit()
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .frame(minWidth: Self.minWidth, alignment: .leading)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DesignText.accessibilityLabel([rating.spokenSource,
                                                           rating.displayValue.replacingOccurrences(of: "\u{00A0}", with: " ")]))
    }
}
