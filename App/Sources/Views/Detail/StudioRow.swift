import SwiftUI
import PlayerCore

/// Build 5 device test 1 (item 5): studios and networks of a title (TMDB), each as its logo or as its name when TMDB
/// has no logo. Review N6: the logos (dark, white or coloured PNGs) are drawn as one-colour shapes on the row plate,
/// so every one stays readable; at most `maxShown` plates (one line).
/// Build 7: every plate with a TMDB ID is a focusable tile (`ThemeTileButtonStyle`, as the cast portraits above) and
/// opens the studio page (`StudioPage`: a synthetic folder, shown by `GenrePageView`, pushed on the same navigation
/// stack as the person page). A plate without `logo_path` looks up the company / network image list once per app
/// run (`StudioLogoLookup`); without any logo it shows the name in the row typography at the logo height (never an
/// empty plate). The logo shape is white at rest and black on the white focus plate.
struct StudioRow: View {
    let studios: [StudioLogo]
    /// TMDB ID of the title (log line once per title and app run).
    let titleID: Int
    @EnvironmentObject var model: AppModel
    @Environment(\.navigate) private var navigate
    /// The shown plates with the missing logos filled in, once the lookups answered.
    @State private var filled: [StudioLogo]?

    static let maxShown = 5

    private var shown: [StudioLogo] { filled ?? Array(studios.prefix(Self.maxShown)) }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Space.m) {
                ForEach(shown, id: \.rowID) { s in plate(s) }
            }
            // Tile style lifts by `focus.tileScale` (as `CastRow`); the vertical room keeps tile and shadow clear.
            .padding(.vertical, Theme.Focus.tileRowPadding)
        }
        .scrollClipDisabled()
        .task(id: studios) {
            let first = Array(studios.prefix(Self.maxShown))
            // Other studios (same view, new title): no plates of the previous title meanwhile.
            if let f = filled, f.map(\.rowID) != first.map(\.rowID) { filled = nil }
            let result = await StudioLogoLookup.fill(first, tmdb: model.tmdb)
            guard !Task.isCancelled else { return }
            filled = result
            StudioRowLog.note(titleID: titleID, studios: result)
        }
    }

    @ViewBuilder private func plate(_ s: StudioLogo) -> some View {
        if let folder = StudioPage.folder(for: s) {
            Button {
                RemoteLog.info("detail", "Studio: \(s.name) (\(s.kind.rawValue) \(s.id ?? 0)) gewählt")
                navigate(.folder(folder))
            } label: {
                StudioPlate(studio: s)
            }
            .buttonStyle(ThemeTileButtonStyle())
            .accessibilityLabel(s.name)
            .accessibilityHint("Zeigt, was dieses Studio noch produziert hat.")
        } else {
            // No TMDB ID: the same plate, but nothing to open.
            StudioPlate(studio: s)
                .padding(Theme.Space.s)
                .background(Theme.Palette.row, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        }
    }
}

/// Content of one studio plate: the logo shape (white, black when focused) or the name.
private struct StudioPlate: View {
    let studio: StudioLogo
    @Environment(\.isFocused) private var focused
    @Environment(\.theme) private var theme
    /// Logo address that could not be loaded: the name instead.
    @State private var failedLogo: String?

    static let logoHeight: CGFloat = 56
    static let logoMaxWidth: CGFloat = 220

    var body: some View {
        content
            .padding(.horizontal, theme.space.m)
            .padding(.vertical, theme.space.s)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(studio.name)
    }

    @ViewBuilder private var content: some View {
        if let logo = studio.logo, failedLogo != logo {
            RemoteImage(url: logo, maxPixels: 600, fit: true, placeholder: AnyView(Color.clear),
                        onFailure: { failedLogo = $0 })
                // Template tint: the logo's shape in one colour, readable on the plate whatever its own colours.
                .saturation(0)
                .brightness(focused ? -1 : 1)
                .frame(maxWidth: Self.logoMaxWidth, maxHeight: Self.logoHeight)
        } else {
            Text(studio.name)
                .textRoleInRow(.rowTitleEmphasis)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: Self.logoMaxWidth, minHeight: Self.logoHeight, maxHeight: Self.logoHeight)
        }
    }
}

private extension StudioLogo {
    /// Identity in the row: stays the same when the logo gets filled in (the focus stays on the plate).
    var rowID: String { key ?? "name:\(name)" }
}

/// Build 7: logos for plates without `logo_path` (`/company|network/{id}/images`), at most once per studio and app
/// run (a found logo and "none" are kept; a failed request is tried again on the next detail page).
@MainActor enum StudioLogoLookup {
    private static var known: [String: String?] = [:]

    static func fill(_ studios: [StudioLogo], tmdb: TMDBClient?) async -> [StudioLogo] {
        var found: [String: String] = [:]
        var open: [StudioLogo] = []
        for s in StudioLogoFill.lookups(studios) {
            guard let k = s.key else { continue }
            if let hit = known[k] {
                if let l = hit { found[k] = l }
            } else {
                open.append(s)
            }
        }
        if let tmdb, !open.isEmpty {
            let answers = await lookUp(open, tmdb: tmdb)
            for a in answers {
                guard a.ok else { continue }   // request failed: not remembered
                known.updateValue(a.logo, forKey: a.key)
                if let l = a.logo { found[a.key] = l }
            }
        }
        return StudioLogoFill.apply(studios, found: found)
    }

    private struct Answer: Sendable {
        var key: String
        var logo: String?
        var ok: Bool
    }

    private static func lookUp(_ open: [StudioLogo], tmdb: TMDBClient) async -> [Answer] {
        await withTaskGroup(of: Answer.self) { group -> [Answer] in
            for s in open {
                guard let k = s.key else { continue }
                group.addTask {
                    do {
                        let l = try await tmdb.studioLogo(s)
                        return Answer(key: k, logo: l, ok: true)
                    } catch {
                        return Answer(key: k, logo: nil, ok: false)
                    }
                }
            }
            var out: [Answer] = []
            for await a in group { out.append(a) }
            return out
        }
    }
}

/// Review N6: the studios line once per title and app run (Build 7: after the logo lookups, with the text plates).
@MainActor enum StudioRowLog {
    private static var noted = Set<Int>()

    static func note(titleID: Int, studios: [StudioLogo]) {
        guard noted.insert(titleID).inserted else { return }
        RemoteLog.info("detail", StudioLogoFill.logLine(studios))
    }
}
