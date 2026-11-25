import SwiftUI
import PlayerCore

/// Task 5.6 (D-19): settings layout `liste`. One centred column (`LookChrome.listWidth`): title „Einstellungen“,
/// the phone entry, then every category under its own header with its rows (`SettingsLayoutTree.entries(.liste)`).
/// The category pages are the ones of the other layouts, drawn without their own scroll view and page title
/// (`\.settingsEmbedded`). Menu leaves the settings (`leave`, N2); subpages go back by themselves.
struct SettingsListView<Header: View, Content: View>: View {
    let leave: () -> Void
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: (SettingsCategory) -> Content
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView(.vertical) {
            // Lazy per category: a category builds (and starts its own tasks) only when it scrolls near.
            LazyVStack(alignment: .leading, spacing: theme.space.xl) {
                VStack(alignment: .leading, spacing: theme.space.m) {
                    Text("Einstellungen").textRole(.pageTitle).accessibilityAddTraits(.isHeader)
                    header()
                }
                ForEach(SettingsCategory.allCases) { c in
                    content(c)
                        .environment(\.settingsEmbedded, true)
                }
            }
            .frame(width: LookChrome.listWidth, alignment: .leading)
            .padding(.vertical, theme.space.m)
            .frame(maxWidth: .infinity)
        }
        .scrollClipDisabled()
        .onExitCommand(perform: leave)
    }
}

/// Task 5.6: true while a category page is drawn inside `SettingsListView` (no own scroll view, no page title).
private struct SettingsEmbeddedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var settingsEmbedded: Bool {
        get { self[SettingsEmbeddedKey.self] }
        set { self[SettingsEmbeddedKey.self] = newValue }
    }
}
