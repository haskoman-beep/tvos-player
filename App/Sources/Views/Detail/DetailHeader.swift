import SwiftUI
import Combine
import PlayerCore

/// Wave F-n: the title's poster on the detail page, left of the info block. Same picture choice as the poster tiles
/// (`TilePosterImage`: metadata addon poster when that setting is on, then the catalogue/TMDB poster, a failed address
/// is skipped; without any picture the title shows on the placeholder). Not focusable.
struct DetailPoster: View {
    let item: MetaPreview

    var body: some View {
        TilePosterImage(item: item)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
            .accessibilityHidden(true)
    }
}

/// Wave F-n: padding of `FocusHighlight` (the detail poster ends with the description text, not its highlight).
enum FocusHighlightMetrics {
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 10
}

/// Dezente Fokusanzeige für Text-Knöpfe (`.buttonStyle(.plain)`).
struct FocusHighlight<C: View>: View {
    @Environment(\.isFocused) private var focused
    @ViewBuilder let content: C
    var body: some View {
        content
            .padding(.horizontal, FocusHighlightMetrics.horizontalPadding).padding(.vertical, FocusHighlightMetrics.verticalPadding)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(focused ? 0.14 : 0)))
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// Blatt mit dem ganzen Text (Beschreibung, Biografie).
struct FullTextSheet: View {
    let title: String
    let text: String
    var body: some View {
        // tvOS scrollt nur von Fokus zu Fokus: Text in Absätze/Stücke teilen, jedes Stück fokussierbar.
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text(title).textRole(.pageTitle).accessibilityAddTraits(.isHeader)
                ForEach(Array(TextChunks.split(text).enumerated()), id: \.offset) { _, chunk in
                    Text(chunk).font(.body).focusable()
                }
            }
            .frame(maxWidth: 1300, alignment: .leading)
            .padding(60)
        }
    }
}

/// Infozeile der Detailseite (§4.5): Technik gefüllt neutral, Bewertungen ohne Rahmen („IMDb 7,1“).
/// Einzeilig: passt die Zeile nicht, entfallen Bewertungen von hinten (Technik bleibt), nie Umbruch.
struct InfoBadges: View {
    /// Welle E-a: schon nach der Bewertungsauswahl gefiltert (`AppModel.ratingBadges`).
    let ratings: [RatingBadge]
    /// Höchstens 5 (`QualityBadges.detailRow`); die Altersfreigabe steht in der Textzeile darüber.
    let tech: [QualityBadge]
    /// Task 5.3: the home hero frames the row with this height; it stays at the old 34 although detail badges are
    /// 38 now (the hero only shows ratings here, and its layout belongs to the home page).
    static let height: CGFloat = 34

    var body: some View {
        // Immer vorhandener Platzhalter hält die Zeilenhöhe, auch bevor die erste Plakette kommt.
        ZStack(alignment: .leading) {
            Color.clear.frame(height: Self.height)
            if !ratings.isEmpty || !tech.isEmpty {
                ViewThatFits(in: .horizontal) {
                    ForEach(Array((0...ratings.count).reversed()), id: \.self) { n in row(ratings: Array(ratings.prefix(n))) }
                }
                .frame(maxWidth: 1400, alignment: .leading)
                .transition(.opacity)
            }
        }
    }

    private func row(ratings shown: [RatingBadge]) -> some View {
        HStack(spacing: Theme.Space.m) {
            if !tech.isEmpty {
                HStack(spacing: Theme.Space.xs) {
                    ForEach(tech) { ThemeBadge($0, size: .detail) }
                }
            }
            ForEach(shown) { ThemeBadge(rating: $0, brandColor: Self.brandColor($0.source)) }
        }
    }

    /// Markenfarbe des Quellennamens (nur Schrift, keine fremden Logos). Task 5.3: tokens in `RatingColors`.
    static func brandColor(_ source: String) -> Color { RatingColors.brand(source) }
}

/// Task 5.3: the badge row of the detail page: tech badges (style `detail.badgeStyle`, drawn by `ThemeBadge`) and
/// the ratings in `detail.ratingStyle` (`RatingRow`). Never wraps: ratings that do not fit drop from the end.
struct DetailBadges: View {
    let ratings: [RatingBadge]
    let tech: [QualityBadge]
    let ratingStyle: LookRatingStyle
    var centred = false

    /// Tiles are taller than a badge; the placeholder keeps the row's height before the first badge comes.
    private var height: CGFloat { ratingStyle == .kacheln && !ratings.isEmpty ? 72 : ThemeBadge.TechSize.detail.height }

    var body: some View {
        ZStack(alignment: centred ? .center : .leading) {
            Color.clear.frame(height: height)
            if !ratings.isEmpty || !tech.isEmpty {
                ViewThatFits(in: .horizontal) {
                    ForEach(Array((0...ratings.count).reversed()), id: \.self) { n in row(Array(ratings.prefix(n))) }
                }
                .frame(maxWidth: 1400, alignment: centred ? .center : .leading)
                .transition(.opacity)
            }
        }
    }

    private func row(_ shown: [RatingBadge]) -> some View {
        HStack(spacing: Theme.Space.m) {
            if !tech.isEmpty {
                HStack(spacing: Theme.Space.xs) {
                    ForEach(tech) { ThemeBadge($0, size: .detail) }
                }
            }
            if !shown.isEmpty { RatingRow(ratings: shown, style: ratingStyle) }
        }
    }
}

/// Task 5.3: the backdrop of the detail page with the shades of `detail.layout` (always in the background tone).
struct DetailBackdrop: View {
    let url: String?
    let shades: [DetailShade]
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.color.base
            RemoteImage(url: url)
            ForEach(Array(shades.enumerated()), id: \.offset) { _, shade in
                DetailShadeView(shade: shade, base: theme.color.base)
            }
        }
        .ignoresSafeArea()
    }
}

/// One shade as a linear gradient in `base` (PlayerCore `DetailShade`, stops from its starting edge).
private struct DetailShadeView: View {
    let shade: DetailShade
    let base: Color

    var body: some View {
        switch shade {
        case .fromBottom(let stops):
            LinearGradient(stops: gradientStops(stops), startPoint: .bottom, endPoint: .top)
        case .fromLeading(let stops):
            LinearGradient(stops: gradientStops(stops), startPoint: .leading, endPoint: .trailing)
        }
    }

    private func gradientStops(_ stops: [DetailShadeStop]) -> [Gradient.Stop] {
        stops.map { Gradient.Stop(color: base.opacity($0.opacity), location: CGFloat($0.location)) }
    }
}

/// Task 5.3: the backing of the part below the head (episodes, cast, similar titles): it runs in from clear to
/// the background tone, so the head's picture stays visible and the text below is readable over any picture.
struct DetailLowerBacking: View {
    @Environment(\.theme) private var theme
    private static let fade: CGFloat = 160
    private static let opacity: Double = 0.92

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [theme.color.base.opacity(0), theme.color.base.opacity(Self.opacity)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: Self.fade)
            theme.color.base.opacity(Self.opacity)
        }
        .padding(.top, -Self.fade)
        .padding(.bottom, -Theme.Space.edgeVertical)
    }
}
