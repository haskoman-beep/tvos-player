import SwiftUI

/// Task 5.1 (D-23): "gesehen" mark at the top trailing corner of a card (black check on a white circle).
/// VoiceOver reads it through the card's value (`CardLayout.accessibilityValue`), so the mark itself is hidden.
struct WatchedMark: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill").font(.title3)
            .symbolRenderingMode(.palette).foregroundStyle(Color.black, Color.white)
            .shadow(radius: 4).padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
