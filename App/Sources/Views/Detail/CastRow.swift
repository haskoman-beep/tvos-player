import SwiftUI
import PlayerCore

/// Task 5.3 (`detail.cast`): the cast of a title.
/// - `kreise`: round portrait 150×150, the name below (meta), 26 apart.
/// - `karten`: card 170 wide with a portrait 170×220 (rounded), name and role.
/// - `text`: one line „Mit A, B, C“ (meta, not focusable; the people stay reachable through the other styles).
/// - `aus`: nothing (the caller drops the header too).
/// A portrait or card opens the person's page, as before.
struct CastRow: View {
    let cast: [CastMember]
    let style: LookCast
    @Environment(\.navigate) private var navigate
    @Environment(\.theme) private var theme

    var body: some View {
        switch style {
        case .kreise: portraits(circles: true)
        case .karten: portraits(circles: false)
        case .text: line
        case .aus: EmptyView()
        }
    }

    @ViewBuilder private var line: some View {
        if let text = DetailLook.castLine(cast.map(\.name)) {
            Text(text)
                .textRole(.rowDetail)
                .lineLimit(1)
                .frame(maxWidth: Theme.Layout.contentMaxWidth, alignment: .leading)
        }
    }

    private func portraits(circles: Bool) -> some View {
        let spacing: CGFloat = circles ? 26 : theme.space.m
        return ScrollView(.horizontal) {
            // Tile style lifts by `focus.tileScale`; the vertical room keeps tile and shadow out of the next row.
            LazyHStack(alignment: .top, spacing: spacing) {
                ForEach(cast) { c in
                    Button { navigate(.person(id: c.id, name: c.name)) } label: {
                        CastPortrait(member: c, circle: circles)
                    }
                    .buttonStyle(ThemeTileButtonStyle())
                }
            }
            .padding(.vertical, Theme.Focus.tileRowPadding)
        }
        .scrollClipDisabled()
    }
}

/// One portrait of `CastRow` (circle or card).
private struct CastPortrait: View {
    let member: CastMember
    let circle: Bool

    private static let circleSide: CGFloat = 150
    private static let cardWidth: CGFloat = 170
    private static let cardHeight: CGFloat = 220
    private static let cardRadius: CGFloat = 12

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            picture
            Text(member.name).textRoleInRow(.rowDetail).lineLimit(1)
            if !circle, let role = member.role {
                Text(role).font(.caption2).opacity(0.7).lineLimit(1)
            }
        }
        .frame(width: circle ? Self.circleSide : Self.cardWidth)
    }

    @ViewBuilder private var picture: some View {
        if circle {
            RemoteImage(url: member.photo, maxPixels: 320)
                .frame(width: Self.circleSide, height: Self.circleSide)
                .clipShape(Circle())
                .overlay { initial }
        } else {
            RemoteImage(url: member.photo, maxPixels: 460)
                .frame(width: Self.cardWidth, height: Self.cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous))
                .overlay { initial }
        }
    }

    @ViewBuilder private var initial: some View {
        if member.photo == nil { Text(String(member.name.prefix(1))).font(.title) }
    }
}
