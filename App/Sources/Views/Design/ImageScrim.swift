import SwiftUI

/// Task 5.1 (D-8): the one gradient under text on a picture (landscape cards, expanded poster, hero card, calendar
/// tile): the background tone at `strength` at the bottom, clear from the middle up. Before, landscape and
/// collection tiles put white text on the picture with only a soft shadow (unreadable on bright stills).
struct ImageScrim: View {
    enum Strength {
        /// 75 %: cards with one title line.
        case card
        /// 85 %: cards with two lines or a long overview (hero card, calendar tile).
        case strong

        var opacity: Double {
            switch self {
            case .card: 0.75
            case .strong: 0.85
            }
        }
    }

    var strength: Strength = .card
    @Environment(\.theme) private var theme

    var body: some View {
        LinearGradient(colors: [theme.color.base.opacity(strength.opacity), .clear], startPoint: .bottom,
                       endPoint: .center)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
