import SwiftUI
import PlayerCore

/// Task 5.2 (`heroStyle` vollbild, Apple-TV default): the picture fills the screen behind the list, with the
/// gradients to the left and bottom; the info stands top left (Build 4 layout, device-verified).
struct HeroFullscreen: View {
    let content: HeroContent

    var body: some View {
        ZStack(alignment: .topLeading) {
            HeroBackdrop(url: content.picture)
            if let item = content.item {
                HeroInfo(item: item, style: content.info)
                    .padding(.leading, Theme.Space.edge).padding(.top, Theme.Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let text = content.status {
                // Task 4.1a (F-A-4): the hero frame stays; the reason stands where the info would be.
                Text(text).textRole(.rowDetail)
                    .padding(.leading, Theme.Space.edge).padding(.top, Theme.Space.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
