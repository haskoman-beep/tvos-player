import SwiftUI
import PlayerCore

/// Task 5.6 (D-19): settings layout `kacheln`. Title „Einstellungen“ (`pageTitle`), below a grid of 4 columns,
/// gap 26, tiles 230 high with the radius `cornerRadius + 6` (`LookChrome`). The phone entry comes first, then the
/// nine categories (`SettingsLayoutTree.entries(.kacheln)`). A tile opens its category as a page of its own; Menu
/// there goes back to the grid, Menu on the grid leaves the settings (`leave`, N2).
struct SettingsTilesView<Content: View>: View {
    @Binding var selected: SettingsCategory
    let leave: () -> Void
    @ViewBuilder let content: (SettingsCategory) -> Content
    @Environment(\.theme) private var theme
    @FocusState private var focused: SettingsCategory?

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: LookChrome.tileSpacing), count: LookChrome.tileColumns)
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: theme.space.l) {
                Text("Einstellungen").textRole(.pageTitle).accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: columns, alignment: .leading, spacing: LookChrome.tileSpacing) {
                    phoneTile
                    ForEach(SettingsCategory.allCases) { c in
                        categoryTile(c)
                    }
                }
            }
            // 5.6-later: `theme.chrome.leadingExtra` (content from 150 in the sidebar) once the device shows what
            // `.sidebarAdaptable` reserves; until then every page starts at 80 (review I3).
            .padding(.vertical, theme.space.m)
        }
        .scrollClipDisabled()
        .defaultFocus($focused, selected)
        .onChange(of: focused) { _, c in if let c, c != selected { selected = c } }
        .onExitCommand(perform: leave)
    }

    private var phoneTile: some View {
        NavigationLink {
            PhoneInputView()
        } label: {
            SettingsTileLabel(symbol: "qrcode", tint: Theme.CategoryTint.system.color, title: "Am Handy einrichten")
        }
        .buttonStyle(SettingsTileButtonStyle(radius: theme.chrome.tileRadius))
        .accessibilityLabel("Am Handy einrichten")
        .accessibilityHint("Addons, Schlüssel, Importe")
    }

    private func categoryTile(_ c: SettingsCategory) -> some View {
        NavigationLink {
            SettingsCategoryScreen(category: c) { content(c) }
        } label: {
            SettingsTileLabel(symbol: c.symbol, tint: c.tint, title: c.title)
        }
        .buttonStyle(SettingsTileButtonStyle(radius: theme.chrome.tileRadius))
        .focused($focused, equals: c)
        .accessibilityLabel(c.title)
    }
}

/// A category opened from a tile: the same page as in the right column of `spalten`, as a page of its own.
private struct SettingsCategoryScreen<Content: View>: View {
    let category: SettingsCategory
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .settingsSurface()
            .onAppear { RemoteLog.info("nav", "Einstellungen › \(category.title) (Kachel)") }
    }
}

/// Tile content: symbol tile at the top, title at the bottom (configurator `kacheln`).
private struct SettingsTileLabel: View {
    let symbol: String
    let tint: Color
    let title: String
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.s) {
            IconTile(symbol: symbol, color: tint)
            Spacer(minLength: 0)
            Text(title)
                .textRoleInRow(.rowTitleEmphasis)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(LookChrome.tileSpacing)
        .frame(maxWidth: .infinity, minHeight: LookChrome.tileHeight, maxHeight: LookChrome.tileHeight,
               alignment: .topLeading)
    }
}

/// Focus-aware tile surface from the theme: at rest `bg.raised`, focused white with the row text colours
/// (`textRoleInRow`), lifted by `focus.scale` with the focus shadow.
private struct SettingsTileButtonStyle: ButtonStyle {
    let radius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        TileBody(configuration: configuration, radius: radius)
    }

    private struct TileBody: View {
        let configuration: Configuration
        let radius: CGFloat
        @Environment(\.isFocused) private var focused
        @Environment(\.theme) private var theme

        var body: some View {
            let shadow = theme.elevation.focus
            let scale: CGFloat = configuration.isPressed ? theme.focus.pressedScale : (focused ? theme.focus.scale : 1)
            configuration.label
                .background(focused ? theme.color.rowFocused : theme.color.raised,
                            in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .scaleEffect(scale)
                .shadow(color: .black.opacity(focused ? shadow.opacity : 0),
                        radius: focused ? shadow.radius : 0, y: focused ? shadow.y : 0)
                .animation(theme.motion.focusAnimation, value: focused)
                .animation(theme.motion.pressAnimation, value: configuration.isPressed)
        }
    }
}
