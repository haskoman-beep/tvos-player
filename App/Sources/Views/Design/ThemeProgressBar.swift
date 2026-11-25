import SwiftUI

/// Task 5.1 (D-23): progress bar at the bottom of a card (continue watching): white on white 30 %, 6 pt, inset 10.
/// One view instead of the inline capsules of `CardStateOverlay`.
struct ThemeProgressBar: View {
    /// 0…1; values outside are clamped.
    let fraction: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.3))
                Capsule().fill(Color.white).frame(width: g.size.width * CGFloat(min(1, max(0, fraction))))
            }
        }
        .frame(height: 6)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
