import SwiftUI
import PlayerCore

/// Build 5 device test 1 (item 5): studios and networks of a title (TMDB), each as its logo or as its name when TMDB
/// has no logo. Not focusable: the page scrolls past it. Review N6: the logos (dark, white or coloured PNGs) are
/// drawn as white shapes on the row plate, so every one stays readable; at most `maxShown` plates (one line).
struct StudioRow: View {
    let studios: [StudioLogo]
    @Environment(\.theme) private var theme

    private static let logoHeight: CGFloat = 56
    private static let logoMaxWidth: CGFloat = 220
    static let maxShown = 5

    var body: some View {
        HStack(spacing: theme.space.m) {
            ForEach(Array(studios.prefix(Self.maxShown)), id: \.self) { s in plate(s) }
        }
    }

    @ViewBuilder private func plate(_ s: StudioLogo) -> some View {
        if let logo = s.logo {
            RemoteImage(url: logo, maxPixels: 600, fit: true)
                .saturation(0).brightness(1)   // template tint: the logo's shape in white
                .frame(maxWidth: Self.logoMaxWidth, maxHeight: Self.logoHeight)
                .padding(.horizontal, theme.space.m).padding(.vertical, theme.space.s)
                .background(theme.color.row, in: RoundedRectangle(cornerRadius: theme.radius.row, style: .continuous))
                .accessibilityLabel(s.name)
        } else {
            Text(s.name).textRole(.rowDetail).lineLimit(1)
                .padding(.horizontal, theme.space.m).padding(.vertical, theme.space.s)
                .background(theme.color.row, in: RoundedRectangle(cornerRadius: theme.radius.row, style: .continuous))
        }
    }
}

/// Review N6: the studios line once per title and app run.
@MainActor enum StudioRowLog {
    private static var noted = Set<Int>()

    static func note(_ info: LocalizedMeta) {
        guard noted.insert(info.tmdbID).inserted else { return }
        RemoteLog.info("detail", "Studios \(info.studioLogos.count), mit Logo \(info.studioLogos.filter { $0.logo != nil }.count)")
    }
}
