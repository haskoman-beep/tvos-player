import SwiftUI

/// Task 5.4: the one surface over video (control-bar cards, Ton & Untertitel, Nächste Folge, „Noch da?“, skip and
/// post-play cards, side panel): material plus `color.scrim`, `radius.panel`, shadow `elevation.overlay`.
/// With system "reduce transparency" the scrim is `bg.base` (opaque, `ThemeValues.make`), so nothing shines through.
enum OverlayCardShape: Equatable {
    /// All corners `radius.panel` (a card floating over the picture).
    case rounded
    /// Square corners (a panel flush with the screen edges, e.g. the side panel from the right).
    case flush
}

/// Background of an overlay card for views that lay out their own content (panels with measured heights).
struct OverlayCardBackground: ViewModifier {
    var shape: OverlayCardShape = .rounded
    /// Edges where the surface reaches past the safe area to the screen edge (the content stays inside).
    var bleed: Edge.Set = []
    /// Shadow `elevation.overlay` (off for panels flush with the screen edge: nothing to lift off).
    var lifted = true
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        let radius: CGFloat = shape == .rounded ? theme.radius.panel : 0
        let shadow = theme.elevation.overlay
        content.background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                theme.color.scrim
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(lifted ? shadow.opacity : 0), radius: lifted ? shadow.radius : 0,
                    y: lifted ? shadow.y : 0)
            .ignoresSafeArea(.container, edges: bleed)
        }
    }
}

extension View {
    /// Task 5.4: draw this view on an overlay card (see `OverlayCardBackground`).
    func overlayCard(_ shape: OverlayCardShape = .rounded, bleed: Edge.Set = [], lifted: Bool = true) -> some View {
        modifier(OverlayCardBackground(shape: shape, bleed: bleed, lifted: lifted))
    }
}

/// Task 5.4: a padded overlay card. `padding` defaults to 36 (configurator `.dlg`).
struct OverlayCard<Content: View>: View {
    var padding: CGFloat = OverlayCardMetrics.padding
    var shape: OverlayCardShape = .rounded
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .overlayCard(shape)
    }
}

/// Fixed sizes of the cards over video (plan Task 5.4, configurator scene „Player“).
enum OverlayCardMetrics {
    /// Inner padding of a dialog card.
    static let padding: CGFloat = 36
    /// Dimming behind the centred track card („Mitte“) and the „Noch da?“ dialog.
    static let dimTrackCard: Double = 0.45
    static let dimDialog: Double = 0.6
}
