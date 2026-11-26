import SwiftUI
import PlayerCore

/// Build 5 device test 1 (item 5): studios and networks of a title (TMDB), each as its logo on a light plate (the
/// logos are dark or coloured PNGs) or as its name when TMDB has no logo. Not focusable: the page scrolls past it.
struct StudioRow: View {
    let studios: [StudioLogo]
    @Environment(\.theme) private var theme

    private static let logoHeight: CGFloat = 56
    private static let logoMaxWidth: CGFloat = 220

    var body: some View {
        HStack(spacing: theme.space.m) {
            ForEach(studios, id: \.self) { s in plate(s) }
        }
    }

    @ViewBuilder private func plate(_ s: StudioLogo) -> some View {
        if let logo = s.logo {
            RemoteImage(url: logo, maxPixels: 600, fit: true)
                .frame(maxWidth: Self.logoMaxWidth, maxHeight: Self.logoHeight)
                .padding(.horizontal, theme.space.m).padding(.vertical, theme.space.s)
                .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: theme.radius.row, style: .continuous))
                .accessibilityLabel(s.name)
        } else {
            Text(s.name).textRole(.rowDetail).lineLimit(1)
                .padding(.horizontal, theme.space.m).padding(.vertical, theme.space.s)
                .background(theme.color.row, in: RoundedRectangle(cornerRadius: theme.radius.row, style: .continuous))
        }
    }
}
