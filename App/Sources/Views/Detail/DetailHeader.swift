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
    static let height: CGFloat = ThemeBadge.TechSize.detail.height

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

    /// Markenfarbe des Quellennamens (nur Schrift, keine fremden Logos).
    static func brandColor(_ source: String) -> Color {
        switch source {
        case "imdb": Color(red: 0.96, green: 0.77, blue: 0.09)
        case "letterboxd": Color(red: 0.0, green: 0.88, blue: 0.33)
        case "trakt": Color(red: 0.93, green: 0.11, blue: 0.14)
        case "tmdb": Color(red: 0.0, green: 0.82, blue: 0.85)
        default: Theme.Palette.primary
        }
    }
}
