import SwiftUI
import PlayerCore

/// Task 5.3 (D-10): the action button of the redesigned screens, as a button style:
/// `.buttonStyle(ThemeButton(.primary))`. One main button per screen is `.primary` („Abspielen“); every other
/// action is `.secondary`. Labels use SF Symbols (`ThemeButtonLabel`), no Unicode signs.
///
/// - `primary`: resting in the accent (`color.accent`, text `color.onAccent`; the accent marks the main button).
/// - `secondary`: resting on `bg.row`; `selected` (e.g. the chosen season) on `badgeFill`.
/// - Focused: both white with dark text (the focus never depends on the accent), lifted by `focus.tileScale`
///   with the focus shadow. All values from the runtime theme.
struct ThemeButton: ButtonStyle {
    enum Role { case primary, secondary }

    let role: Role
    var selected = false

    init(_ role: Role, selected: Bool = false) {
        self.role = role
        self.selected = selected
    }

    func makeBody(configuration: Configuration) -> some View {
        ThemeButtonBody(configuration: configuration, role: role, selected: selected)
    }
}

private struct ThemeButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let role: ThemeButton.Role
    let selected: Bool
    @Environment(\.isFocused) private var focused
    @Environment(\.theme) private var theme

    private var fill: Color {
        if focused { return theme.color.rowFocused }
        switch role {
        case .primary: return theme.color.accent
        case .secondary: return selected ? theme.color.badgeFill : theme.color.row
        }
    }

    private var foreground: Color {
        if focused { return theme.color.primaryOnFocus }
        return role == .primary ? theme.color.onAccent : theme.color.primary
    }

    private var scale: CGFloat {
        if configuration.isPressed { return theme.focus.pressedScale }
        return focused ? theme.focus.tileScale : 1
    }

    var body: some View {
        let shadow = theme.elevation.focus
        configuration.label
            .font(theme.type.font(.rowTitleEmphasis))
            .foregroundStyle(foreground)
            .padding(.horizontal, theme.space.l)
            .padding(.vertical, theme.space.s)
            .frame(minHeight: Theme.Layout.rowMinHeight)
            .background(fill, in: RoundedRectangle(cornerRadius: theme.radius.row, style: .continuous))
            .scaleEffect(scale)
            .shadow(color: .black.opacity(focused ? shadow.opacity : 0),
                    radius: focused ? shadow.radius : 0, y: focused ? shadow.y : 0)
            .animation(theme.motion.focusAnimation, value: focused)
            .animation(theme.motion.pressAnimation, value: configuration.isPressed)
    }
}

/// Label of a `ThemeButton`: SF Symbol plus text in one line (the symbol inherits the button's colour).
struct ThemeButtonLabel: View {
    let title: String
    var symbol: String? = nil

    init(_ title: String, symbol: String? = nil) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
            Text(title).lineLimit(1)
        }
    }
}
