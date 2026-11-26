import SwiftUI
import PlayerCore

/// Task 5.2: what every hero variant draws: the title shown, its picture, the status text of an empty or failed
/// hero source, and how its info looks.
struct HeroContent {
    var item: MetaPreview?
    /// Picture of `item` (scene image, else poster).
    var picture: String?
    /// Status text when there is no item (F-A-4: the hero frame stays).
    var status: String?
    var info: HeroInfoStyle
    /// The info is collapsed (focus in the rows, `HeroCollapse`).
    var collapsed: Bool
}

/// Hintergrund + Info des angezeigten Titels hinter der Startseiten-Liste; steuert den Diashow-Takt.
/// Task 5.2: picks exactly one variant per `heroStyle` (full screen, banner, carousel; `aus` never reaches here,
/// `HomeView` shows the page without hero). The list on top (button row, rows) is the same for all variants, so
/// the focused view keeps its identity when the style changes.
struct HeroLayout: View {
    @Environment(HomeFocus.self) private var focus
    let style: LookHeroStyle
    let level: LookHeroInfo
    let title: LookHeroTitle
    /// `backdropFollowsFocus`: while the focus is in the rows the resting card is shown (else the slide stays).
    let followsFocus: Bool
    let slides: HeroSlides
    /// P2 (follow-up 2): collapsed info while the focus is in the rows.
    let collapse: HeroCollapse

    private var shown: MetaPreview? {
        focus.inRows && followsFocus ? (focus.item ?? slides.current) : slides.current
    }

    var body: some View {
        variant
            // Diashow: alle 10 s, nur solange der Fokus nicht in den Reihen liegt; startet nach jeder Rückkehr neu.
            // Task 5.2: the index is part of the key, so a carousel step restarts the 10 s.
            .task(id: "\(focus.inRows)|\(slides.items.count)|\(slides.index)") {
                guard !focus.inRows, slides.items.count > 1 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled else { return }
                    slides.advance()
                }
            }
            .onChange(of: slides.index, initial: true) {
                // Nächste Folie schon laden, damit die Überblendung ohne Lücke läuft (Karussell: der angeschnittene
                // Nachbartitel ist dieselbe Folie).
                guard let n = slides.next, let s = n.background ?? n.poster, let u = URL(string: s) else { return }
                // P3 device test 1: same target as `HeroPicture` (1920×1080), so the swap hits the prefetched bitmap.
                Task { await ImagePipeline.shared.prefetch([u], target: .heroBackdrop) }
            }
    }

    @ViewBuilder private var variant: some View {
        let content = makeContent()
        switch style {
        case .banner:
            HeroBanner(content: content, height: cardHeight)
        case .karussell:
            HeroCarouselCard(content: content, next: slides.next, height: cardHeight)
        case .vollbild, .aus:
            HeroFullscreen(content: content)
        }
    }

    /// Banner and carousel: card height, expanded or ending above the collapsed list (PlayerCore `HeroInfoMetrics`).
    private var cardHeight: CGFloat {
        HeroMetrics.infoMetrics.cardHeight(style, level: level,
                                           collapsedTop: collapse.collapsed ? collapse.collapsedTop : nil)
    }

    private func makeContent() -> HeroContent {
        let item = shown
        let picture = item.flatMap { $0.background ?? $0.poster }
        let status = item == nil ? slides.phase.statusText(empty: HeroSlides.emptyText) : nil
        return HeroContent(item: item, picture: picture, status: status, info: infoStyle(),
                           collapsed: collapse.collapsed)
    }

    /// Parts, logo, gaps and width of the info for this style and state.
    private func infoStyle() -> HeroInfoStyle {
        let m = HeroMetrics.infoMetrics
        let card = HeroInfoMetrics.isCard(style)
        let collapsed = collapse.collapsed
        let parts = collapsed ? HeroInfoParts.collapsed(level, style: style) : HeroInfoParts.of(level)
        let logo: CGFloat = collapsed ? collapse.compactLogo : (card ? m.cardLogo : m.logo)
        let spacing: CGFloat = collapsed || card ? m.compactSpacing : m.spacing
        return HeroInfoStyle(parts: parts, title: title, logoHeight: logo, spacing: spacing,
                             width: HeroMetrics.infoWidth(style), overviewLines: collapsed ? collapse.overviewLines : 2)
    }
}

extension HeroMetrics {
    /// Task 5.2: width of the overview and title text. Full screen keeps today's `contentMaxWidth` (device-verified
    /// line breaks); banner 860 (plan); carousel 700 after its 0.8 scale (laid out at 875).
    static func infoWidth(_ style: LookHeroStyle) -> CGFloat {
        switch style {
        case .banner: 860
        case .karussell: 700 / infoMetrics.carouselInfoScale
        case .vollbild, .aus: Theme.Layout.contentMaxWidth
        }
    }

    /// Task 5.2: leading inset of the button row: full screen at the content edge, banner and carousel inside the
    /// card at the info's inset (56).
    static func buttonLeading(_ style: LookHeroStyle) -> CGFloat {
        let card: Bool = HeroInfoMetrics.isCard(style)
        return card ? Theme.Space.edge + infoMetrics.cardInnerLeading : Theme.Space.edge
    }
}
