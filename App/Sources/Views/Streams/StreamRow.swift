import SwiftUI
import Combine
import PlayerCore

/// Welle E-b: Zeile wie vom Formatter des Addons gebaut: links `name`, rechts `description`/`title`, Umbrüche und
/// Emoji bleiben. Welle F-i: ganzer Text (StreamRowText, Kürzung erst ab 12 Zeilen, Cache-Zeilen dann zuerst), die
/// Zeile wächst mit; links unter dem Namen der Cache-Zustand als Plakette („Sofort bereit“ / „Nicht gecacht“,
/// unbekannt: keine). Rechts kompakt nur die Größe (StreamListBadges). Addon-Name nur bei gemischter Liste.
struct StreamRow: View {
    @EnvironmentObject var model: AppModel
    let addon: String?
    let stream: StreamItem
    /// Fokussierte Zeile ist weiß: Texte über `textRoleInRow` dunkel, Plaketten auf der Fokus-Tönung.
    @Environment(\.isFocused) private var focused
    var body: some View {
        let text = StreamRowText(stream)
        let badges = StreamListBadges.badges(stream, mode: model.profile.sources.appBadges, settings: model.profile.appearance.badges)
        let cache = StreamListBadges.cacheBadge(stream, settings: model.profile.appearance.badges)
        HStack(alignment: .top, spacing: Theme.Space.m) {
            if !text.name.isEmpty || cache != nil {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    if !text.name.isEmpty {
                        Text(text.name).textRoleInRow(.rowTitleEmphasis)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let cache { ThemeBadge(cache, size: .sources, surface: focused ? .focusedRow : .plain) }
                }
                .frame(width: 330, alignment: .leading)
            }
            // Keine Zeilengrenze: StreamRowText kürzt selbst (Cache-Zeilen zuerst); die Zeile wächst mit dem Text.
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(text.body).textRoleInRow(.rowDetail)
                    .fixedSize(horizontal: false, vertical: true)
                // Wave Q: full file name, wrapped, when the formatter text does not carry it.
                if let file = text.fileName {
                    Text(file).textRoleInRow(.rowDetail).opacity(0.75)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !badges.isEmpty || addon != nil {
                VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                    if !badges.isEmpty {
                        HStack(spacing: Theme.Space.xs) {
                            ForEach(badges) { ThemeBadge($0, size: .sources, surface: focused ? .focusedRow : .plain) }
                        }
                    }
                    if let addon { Text(addon).textRoleInRow(.rowDetail).lineLimit(1) }
                }
                .fixedSize()
            }
        }
        .multilineTextAlignment(.leading)
    }
}
