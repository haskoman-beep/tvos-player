import SwiftUI
import PlayerCore

/// Task 5.2 (`heroStyle` banner): the picture as an own card from the content edge to 80 from the right, rounded
/// with `radius.panel`; the info bottom left inside it (56 / 44), the button row of the list inside its bottom.
/// Collapsed (focus in the rows) the card ends above the list and keeps logo and meta line.
struct HeroBanner: View {
    @Environment(\.theme) private var theme
    let content: HeroContent
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            theme.color.base.ignoresSafeArea()
            HeroPanel(content: content, height: height, infoScale: 1)
                .padding(.horizontal, Theme.Space.edge)
                .padding(.top, HeroMetrics.infoMetrics.frameTop)
        }
        .allowsHitTesting(false)
    }
}

/// Task 5.2: one hero card (banner, carousel): picture, gradients and the info at its bottom left.
struct HeroPanel: View {
    @Environment(\.theme) private var theme
    let content: HeroContent
    let height: CGFloat
    /// Carousel: 0.8 (plan), anchored bottom left.
    let infoScale: CGFloat

    private var metrics: HeroInfoMetrics { HeroMetrics.infoMetrics }

    /// Expanded: room for the button row (and a gap) below the info; collapsed only the card inset.
    private var bottomInset: CGFloat {
        let m = metrics
        if content.collapsed { return m.cardInnerBottom }
        return m.cardInnerBottom + m.buttonRow + m.spacing
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HeroPicture(url: content.picture)
            HeroScrim()
            info
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous))
    }

    @ViewBuilder private var info: some View {
        if let item = content.item {
            HeroInfo(item: item, style: content.info)
                .scaleEffect(infoScale, anchor: .bottomLeading)
                .padding(.leading, metrics.cardInnerLeading)
                .padding(.bottom, bottomInset)
        } else if let text = content.status {
            // F-A-4: the card stays; the reason stands where the info would be.
            Text(text).textRole(.rowDetail)
                .padding(.leading, metrics.cardInnerLeading)
                .padding(.bottom, bottomInset)
        }
    }
}
