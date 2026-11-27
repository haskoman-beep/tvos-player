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
    /// Build 7 review: opened from a series, the studio page opens on Serien.
    var fromSeries = false
    @EnvironmentObject var model: AppModel
    @Environment(\.navigate) private var navigate
    /// The shown plates with the missing logos filled in, once the lookups answered.
    @State private var filled: [StudioLogo]?

    static let maxShown = 5

    private var shown: [StudioLogo] { filled ?? Array(studios.prefix(Self.maxShown)) }

    private var entries: [StudioRowEntry] {
        let list = shown
        return zip(StudioLogoFill.rowIDs(list), list).map { StudioRowEntry(id: $0, studio: $1) }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Space.m) {
                ForEach(entries) { e in plate(e.studio) }
            }
            // Tile style lifts by `focus.tileScale` (as `CastRow`); the vertical room keeps tile and shadow clear.
            .padding(.vertical, Theme.Focus.tileRowPadding)
        }
        .scrollClipDisabled()
        .task(id: studios) {
            let first = Array(studios.prefix(Self.maxShown))
            // Other studios (same view, new title): no plates of the previous title meanwhile.
            if let f = filled, StudioLogoFill.rowIDs(f) != StudioLogoFill.rowIDs(first) { filled = nil }
            let result = await StudioLogoLookup.fill(first, tmdb: model.tmdb) { now in
                if !Task.isCancelled { filled = now }
            }
            guard !Task.isCancelled else { return }
            StudioRowLog.note(titleID: titleID, studios: result)
        }
    }

    @ViewBuilder private func plate(_ s: StudioLogo) -> some View {
        if let folder = StudioPage.folder(for: s, preferSeries: fromSeries) {
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

/// One plate of the row with its unique ForEach ID (`StudioLogoFill.rowIDs`: stays the same when the logo gets
/// filled in, so the focus stays on the plate).
private struct StudioRowEntry: Identifiable {
    let id: String
    let studio: StudioLogo
}

/// Build 7: logos for plates without `logo_path` (`/company|network/{id}/images`), at most once per studio and app
/// run (a found logo and "none" are kept). Review: a failed request waits `retryAfter` before it is tried again;
/// each answer is applied as it arrives (`update`).
@MainActor enum StudioLogoLookup {
    private static var known: [String: String?] = [:]
    private static var failedAt: [String: Date] = [:]
    static let retryAfter: TimeInterval = 600

    static func fill(_ studios: [StudioLogo], tmdb: TMDBClient?,
                     update: @MainActor ([StudioLogo]) -> Void) async -> [StudioLogo] {
        var found: [String: String] = [:]
        var open: [StudioLogo] = []
        let now = Date()
        for s in StudioLogoFill.lookups(studios) {
            guard let k = s.key else { continue }
            if let hit = known[k] {
                if let l = hit { found[k] = l }
            } else if let t = failedAt[k], now.timeIntervalSince(t) < retryAfter {
                continue   // failed a moment ago: text plate for now
            } else {
                open.append(s)
            }
        }
        var current = StudioLogoFill.apply(studios, found: found)
        update(current)
        guard let tmdb, !open.isEmpty else { return current }
        await withTaskGroup(of: Answer.self) { group in
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
            for await a in group {
                guard a.ok else { failedAt[a.key] = Date(); continue }
                failedAt[a.key] = nil
                known.updateValue(a.logo, forKey: a.key)
                guard let l = a.logo else { continue }
                found[a.key] = l
                current = StudioLogoFill.apply(studios, found: found)
                update(current)
            }
        }
        return current
    }

    private struct Answer: Sendable {
        var key: String
        var logo: String?
        var ok: Bool
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
