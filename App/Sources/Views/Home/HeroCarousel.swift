import SwiftUI
import PlayerCore

/// Task 5.2 (`heroStyle` karussell): a 1320 × 460 card with the next title cut off after a gap of 32. Left on
/// „Abspielen“ / right on „Details“ switches the title (`HeroButtons.carousel`, wraps; sidebar navigation: right only); down goes to the
/// first row (the button row is its own focus section). The cut-off next title is a picture only, never focusable.
/// The info is scaled by 0.8 at a width of 700.
struct HeroCarouselCard: View {
    @Environment(\.theme) private var theme
    let content: HeroContent
    let next: MetaPreview?
    let height: CGFloat

    private var metrics: HeroInfoMetrics { HeroMetrics.infoMetrics }

    var body: some View {
        ZStack(alignment: .topLeading) {
            theme.color.base.ignoresSafeArea()
            HStack(alignment: .top, spacing: metrics.carouselGap) {
                HeroPanel(content: content, height: height, infoScale: metrics.carouselInfoScale)
                    .frame(width: metrics.carouselWidth)
                HeroCarouselPeek(item: next, height: height)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.leading, Theme.Space.edge)
            .padding(.top, metrics.frameTop)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }
}

/// The cut-off next title of the carousel: its picture, dimmed (the slide prefetch already loaded it).
private struct HeroCarouselPeek: View {
    @Environment(\.theme) private var theme
    let item: MetaPreview?
    let height: CGFloat

    var body: some View {
        if let item {
            HeroPicture(url: item.background ?? item.poster, logs: false)
                .frame(width: HeroMetrics.infoMetrics.carouselWidth, height: height)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous))
                .opacity(0.6)
                .accessibilityHidden(true)
        }
    }
}
