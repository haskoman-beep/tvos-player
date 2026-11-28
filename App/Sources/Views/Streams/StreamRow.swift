import SwiftUI
import Combine
import PlayerCore

/// Welle E-b: Zeile wie vom Formatter des Addons gebaut: links `name`, rechts `description`/`title`, Umbrüche und
/// Emoji bleiben. Welle F-i: ganzer Text (StreamRowText, Kürzung erst ab 12 Zeilen, Cache-Zeilen dann zuerst), die
/// Zeile wächst mit; links unter dem Namen der Cache-Zustand als Plakette („Sofort bereit“ / „Nicht gecacht“,
/// unbekannt: keine). Rechts kompakt nur die Größe (StreamListBadges). Addon-Name nur bei gemischter Liste.
///
/// Task 5.3 (`detail.sourceList`):
/// - `klassisch` (default): the Build 4 row: name and cache badge left, the full addon text, size and addon right.
/// - `kompakt`: one line: name, cache badge, the first line of the addon text (cut), size and addon right.
/// - `ausfuehrlich`: „Sofort verfügbar · Name · Größe“ as the head line, the full addon text below (meta, wrapping).
/// - `karten`: head (name, size right), the badge row and the text kept apart.
struct StreamRow: View {
    @Environment(AppModel.self) var model
    let addon: String?
    let stream: StreamItem
    /// Fokussierte Zeile ist weiß: Texte über `textRoleInRow` dunkel, Plaketten auf der Fokus-Tönung.
    @Environment(\.isFocused) private var focused
    @Environment(\.theme) private var theme

    var body: some View {
        let parts = StreamRowParts(
            text: StreamRowText(stream),
            badges: StreamListBadges.badges(stream, mode: model.profile.sources.appBadges, settings: model.profile.appearance.badges),
            cache: StreamListBadges.cacheBadge(stream, settings: model.profile.appearance.badges),
            addon: addon,
            surface: focused ? .focusedRow : .plain)
        Group {
            switch theme.detail.sourceList {
            case .klassisch: StreamRowClassic(parts: parts)
            case .kompakt: StreamRowCompact(parts: parts)
            case .ausfuehrlich: StreamRowDetailed(parts: parts)
            case .karten: StreamRowCard(parts: parts)
            }
        }
        .multilineTextAlignment(.leading)
    }
}

/// What a source row shows, worked out once per row.
struct StreamRowParts {
    let text: StreamRowText
    let badges: [QualityBadge]
    let cache: QualityBadge?
    let addon: String?
    let surface: ThemeBadge.Surface

    /// „4,2 GB“ (the size badges as text), nil without.
    var sizeText: String? {
        let t = badges.map(\.text).joined(separator: " ")
        return t.isEmpty ? nil : t
    }

    /// First line of the addon text (kompakt).
    var firstLine: String {
        text.body.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
    }

    /// „Sofort verfügbar · Name · Größe“ (ausfuehrlich).
    var headLine: String {
        DesignText.metaLine([cache?.displayText, text.name.replacingOccurrences(of: "\n", with: " "), sizeText])
    }
}

/// Size badges and the addon name, right-aligned (kompakt and today's row).
private struct StreamRowTrailing: View {
    let parts: StreamRowParts
    @Environment(\.theme) private var theme

    var body: some View {
        if !parts.badges.isEmpty || parts.addon != nil {
            VStack(alignment: .trailing, spacing: theme.space.xs) {
                if !parts.badges.isEmpty {
                    HStack(spacing: theme.space.xs) {
                        ForEach(parts.badges) { ThemeBadge($0, size: .sources, surface: parts.surface) }
                    }
                }
                if let addon = parts.addon { Text(addon).textRoleInRow(.rowDetail).lineLimit(1) }
            }
            .fixedSize()
        }
    }
}

/// The full addon text plus the file name it does not carry (Wave Q), wrapping.
private struct StreamRowBody: View {
    let text: StreamRowText
    @Environment(\.theme) private var theme

    var body: some View {
        // Keine Zeilengrenze: StreamRowText kürzt selbst (Cache-Zeilen zuerst); die Zeile wächst mit dem Text.
        VStack(alignment: .leading, spacing: theme.space.xs) {
            Text(text.body).textRoleInRow(.rowDetail)
                .fixedSize(horizontal: false, vertical: true)
            if let file = text.fileName {
                Text(file).textRoleInRow(.rowDetail).opacity(0.75)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `klassisch`: the Build 4 row (before Task 5.3), unchanged: a 330 pt column with name and cache badge, the full
/// addon text growing with it, size badges and addon name right.
private struct StreamRowClassic: View {
    let parts: StreamRowParts
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: theme.space.m) {
            if !parts.text.name.isEmpty || parts.cache != nil {
                VStack(alignment: .leading, spacing: theme.space.xs) {
                    if !parts.text.name.isEmpty {
                        Text(parts.text.name).textRoleInRow(.rowTitleEmphasis)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let cache = parts.cache { ThemeBadge(cache, size: .sources, surface: parts.surface) }
                }
                .frame(width: 330, alignment: .leading)
            }
            StreamRowBody(text: parts.text)
            StreamRowTrailing(parts: parts)
        }
    }
}

/// `kompakt`: one line.
private struct StreamRowCompact: View {
    let parts: StreamRowParts
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: theme.space.m) {
            if !parts.text.name.isEmpty {
                Text(parts.text.name.replacingOccurrences(of: "\n", with: " "))
                    .textRoleInRow(.rowTitleEmphasis)
                    .lineLimit(1)
                    .frame(maxWidth: 330, alignment: .leading)
            }
            if let cache = parts.cache { ThemeBadge(cache, size: .sources, surface: parts.surface) }
            Text(parts.firstLine).textRoleInRow(.rowDetail)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            StreamRowTrailing(parts: parts)
        }
    }
}

/// `ausfuehrlich`: head line plus the full text.
private struct StreamRowDetailed: View {
    let parts: StreamRowParts
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: theme.space.m) {
                Text(parts.headLine).textRoleInRow(.rowTitleEmphasis)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let addon = parts.addon { Text(addon).textRoleInRow(.rowDetail).lineLimit(1).fixedSize() }
            }
            StreamRowBody(text: parts.text)
        }
    }
}

/// `karten`: head, badge row and text apart.
private struct StreamRowCard: View {
    let parts: StreamRowParts
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.s) {
            HStack(alignment: .firstTextBaseline, spacing: theme.space.m) {
                Text(parts.text.name).textRoleInRow(.rowTitleEmphasis)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let size = parts.sizeText { Text(size).textRoleInRow(.rowTitleEmphasis).fixedSize() }
            }
            badgeRow
            StreamRowBody(text: parts.text)
        }
        .padding(.vertical, theme.space.xs)
    }

    @ViewBuilder private var badgeRow: some View {
        if parts.cache != nil || parts.addon != nil {
            HStack(spacing: theme.space.xs) {
                if let cache = parts.cache { ThemeBadge(cache, size: .sources, surface: parts.surface) }
                if let addon = parts.addon { Text(addon).textRoleInRow(.rowDetail).lineLimit(1) }
            }
        }
    }
}
