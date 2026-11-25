import SwiftUI
import PlayerCore

/// Task 5.6 (D-19): settings layout `liste`. One centred column (`LookChrome.listWidth`): title „Einstellungen“,
/// the phone entry, then every category under its own header with its rows (`SettingsLayoutTree.entries(.liste)`).
/// The category pages are the ones of the other layouts, drawn without their own scroll view and page title
/// (`\.settingsEmbedded`). Menu leaves the settings (`leave`, N2); subpages go back by themselves.
/// Position across a layout switch (review I1): on entry the list scrolls to `selected` and offers it the default
/// focus; while it is shown, the category the focus is in (or, failing that, the topmost one on screen) becomes
/// `selected`, so the other two layouts open on the same category.
struct SettingsListView<Header: View, Content: View>: View {
    @Binding var selected: SettingsCategory
    let leave: () -> Void
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: (SettingsCategory) -> Content
    @Environment(\.theme) private var theme
    @FocusState private var focused: SettingsCategory?
    @State private var top: SettingsCategory?

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
                        .focusSection()
                        .focused($focused, equals: c)
                        .id(c)
                }
            }
            .scrollTargetLayout()
            .frame(width: LookChrome.listWidth, alignment: .leading)
            .padding(.vertical, theme.space.m)
            .frame(maxWidth: .infinity)
        }
        .scrollClipDisabled()
        .scrollPosition(id: $top, anchor: .top)
        .defaultFocus($focused, selected)
        .onAppear { top = selected }
        .onChange(of: focused) { _, c in take(c, "Fokus") }
        .onChange(of: top) { _, c in if focused == nil { take(c, "Bildlauf") } }
        .onExitCommand(perform: leave)
    }

    private func take(_ c: SettingsCategory?, _ why: String) {
        guard let c, c != selected else { return }
        RemoteLog.info("nav", "Einstellungen (Liste): \(c.title) per \(why)")
        selected = c
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
