import SwiftUI
import PlayerCore

/// Task 5.1: diagnosis switch „alte Karte“ (Einstellungen › System › Diagnose). On: the home rows draw cards as in
/// Build 4 (form from the row style, system card focus, no titles below, 350 ms expand rest), so a focus problem of
/// the new cards can be told apart on the device without going back a build. Kept for one build (plan Task 5.1).
enum CardDiagnostics {
    static let oldCardKey = "diagnose.alteKarte"
}

/// Task 5.1: how the cards of one strip look, resolved once per strip from the theme (`ThemeValues.cards`) and the
/// diagnosis switch, and handed to the cards through the environment. Equatable, so a strip pass with unchanged
/// options leaves every card's environment equal (`.equatable()` cards keep skipping).
/// The default (outside a strip: detail, person, genre pages) is `legacy`, today's system card.
struct CardStyle: Equatable {
    /// Build 4 cards (switch „alte Karte“, or outside the home rows).
    var legacy = true
    /// System card style `.buttonStyle(.card)` (glow, or legacy).
    var glow = true
    var titles: LookCardTitles = .aus
    var shape: LookCardShape = .poster
    var size: LookCardSize = .mittel
    var rowTitle: LookRowTitle = .standard
    var rowSpacing: LookRowSpacing = .normal
    /// Custom focus effect (only without glow).
    var scale: CGFloat = 1
    var border: LookFocusBorder = .keiner
    var shadow: LookShadow? = nil
    var radius: CGFloat = 0
    /// Focus rest before a poster expands, and the expand transition (seconds).
    var expandRest: Double = 0.35
    var expandDuration: Double = 0.25
    var focusDuration: Double = Theme.Focus.duration

    static let legacyStyle = CardStyle()

    static func resolve(_ theme: ThemeValues, oldCard: Bool) -> CardStyle {
        guard !oldCard else { return .legacyStyle }
        let h = theme.cards.home
        var s = CardStyle()
        s.legacy = false
        s.glow = h.focusGlow
        s.titles = h.cardTitles
        s.shape = h.cardShape
        s.size = h.cardSize
        s.rowTitle = h.rowTitle
        s.rowSpacing = h.rowSpacing
        s.scale = LookMetrics.focusScale(h.focusScale)
        s.border = FocusHeadroom.effectiveBorder(h)
        s.shadow = LookMetrics.focusShadow(h.focusShadow)
        s.radius = LookMetrics.cornerRadius(h.corners)
        s.expandRest = LookMetrics.rest.expand
        s.expandDuration = theme.motion.expand
        s.focusDuration = theme.motion.focus
        return s
    }

    /// One `karten` line naming the options in effect (logged when it changes, `CardStyleLog`).
    var logLine: String {
        guard !legacy else { return "Karten: alte Karte (Diagnose)" }
        let focus = glow ? "Glanz" : "Skalierung \(scale), Rahmen \(border.rawValue), Schatten \(shadow == nil ? "keiner" : "an")"
        return "Karten: Form \(shape.rawValue), Größe \(size.rawValue), Titel \(titles.rawValue), "
            + "Abstände \(rowSpacing.rawValue), Reihentitel \(rowTitle.rawValue), Fokus \(focus)"
    }
}

private struct CardStyleKey: EnvironmentKey { static let defaultValue = CardStyle.legacyStyle }

extension EnvironmentValues {
    /// Task 5.1: set by `Strip` for its cards.
    var cardStyle: CardStyle {
        get { self[CardStyleKey.self] }
        set { self[CardStyleKey.self] = newValue }
    }
}

/// Task 5.1: one `karten` line per change of the card options (many strips resolve the same style).
@MainActor
enum CardStyleLog {
    private static var last: String?

    static func note(_ style: CardStyle) {
        let line = style.logLine
        guard line != last else { return }
        last = line
        RemoteLog.info("home", line)
    }
}

/// Task 5.1: the button style of a card. Glow (and legacy): the system card style. Otherwise `ThemeCardButtonStyle`
/// with scale, border, shadow and radius of the look. The branch only changes when the option changes (on the
/// settings page), never while the card holds the focus.
struct CardButtonStyleModifier: ViewModifier {
    @Environment(\.cardStyle) private var style

    @ViewBuilder func body(content: Content) -> some View {
        if style.glow {
            content.buttonStyle(.card)
        } else {
            content.buttonStyle(ThemeCardButtonStyle(style: style))
        }
    }
}

/// Task 5.1 (D-16): focus effect of a card without glow: `focusScale` around the centre, `focusBorder` 4 pt at
/// 4 pt distance (white or accent; white when the look shows no other focus sign), `focusShadow`, `corners`.
struct ThemeCardButtonStyle: ButtonStyle {
    let style: CardStyle

    func makeBody(configuration: Configuration) -> some View {
        ThemeCardBody(label: configuration.label, pressed: configuration.isPressed, style: style)
    }
}

private struct ThemeCardBody<Label: View>: View {
    let label: Label
    let pressed: Bool
    let style: CardStyle
    /// Focus of the button this style draws.
    @Environment(\.isFocused) private var focused
    @Environment(\.theme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.radius, style: .continuous)
        let lifted: CGFloat = focused ? style.scale : 1
        let scale: CGFloat = pressed ? lifted * theme.focus.pressedScale : lifted
        label
            .clipShape(shape)
            .overlay { border }
            .shadow(color: .black.opacity(focused ? (style.shadow?.opacity ?? 0) : 0),
                    radius: style.shadow?.radius ?? 0, y: style.shadow?.y ?? 0)
            .scaleEffect(scale)
            .animation(style.focusDuration > 0 ? .easeOut(duration: style.focusDuration) : nil, value: focused)
            .animation(theme.motion.pressAnimation, value: pressed)
    }

    @ViewBuilder private var border: some View {
        if focused, style.border != .keiner {
            let width: CGFloat = LookMetrics.focusBorderWidth
            let out: CGFloat = LookMetrics.focusBorderGap + width / 2
            RoundedRectangle(cornerRadius: style.radius + out, style: .continuous)
                .stroke(style.border == .akzent ? theme.color.accent : Color.white, lineWidth: width)
                .padding(-out)
        }
    }
}

/// Task 5.1 (D-6, D-24): a home card with its title below (`cardTitles`): „immer“ shows it, „fokus“ keeps the room
/// and fades it in on the focused card (`motion.fade`), „aus“ drops the room for the whole row. `content` is the
/// focusable card itself (focus and menu modifiers already applied), so the title never takes part in focus.
/// While the card is lifted the title moves down by the card's growth (`CardRowGeometry.titleShift`), so the lifted
/// card never covers it.
struct ThemeCard<Content: View>: View {
    let kind: TileKind
    let title: String
    let titleMode: LookCardTitles
    let focused: Bool
    let width: CGFloat
    let shift: CGFloat
    @ViewBuilder let content: Content
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: CardLayout.titleGap) {
            content
            if titleMode != .aus {
                CardTitleLine(title: title, width: width,
                              opacity: CardLayout.titleOpacity(titleMode, focused: focused),
                              shift: focused ? shift : 0, fade: theme.motion.fade)
            }
        }
    }
}

/// The title line below a card. Own view: only the two cards whose focus changed redraw it.
private struct CardTitleLine: View {
    let title: String
    let width: CGFloat
    let opacity: Double
    let shift: CGFloat
    let fade: Double

    var body: some View {
        Text(title).textRole(.rowTitle).lineLimit(1)
            .frame(width: width, alignment: .leading)
            .opacity(opacity)
            .offset(y: shift)
            .animation(fade > 0 ? .easeInOut(duration: fade) : nil, value: opacity)
            .animation(fade > 0 ? .easeOut(duration: min(fade, 0.22)) : nil, value: shift)
            .accessibilityHidden(true)
    }
}

/// Task 5.1: line height of the card title font (`TextRole.rowTitle`), for the title strip of `CardLayout.row`.
enum CardTitleMetrics {
    static func line(_ type: ThemeValues.TypeScale) -> CGFloat {
        let font: UIFont
        if type.isToday {
            font = UIFont.preferredFont(forTextStyle: .body)
        } else {
            let r = LookTheme.type(ThemeValues.TypeScale.tableRole(.rowTitle), scale: type.scale,
                                   character: type.character)
            font = UIFont.systemFont(ofSize: r.size)
        }
        return font.lineHeight.rounded(.up)
    }
}

/// Task 5.1: title room of one row's cards (from `CardLayout.row`), handed from `HomeRowView` to `ThemeCard`.
struct CardTitleSlot: Equatable {
    var mode: LookCardTitles
    /// Width of the title line (the card's width).
    var width: CGFloat
    /// Downward move of the title while its card is lifted.
    var shift: CGFloat
    /// Gap + one line (placeholders keep the same room).
    var strip: CGFloat
}

/// Task 5.1 (`rowTitle`): heading of a home row. „standard“ keeps today's section role (the hero collapse estimates
/// the heading from it); „dezent“ 27 pt and „groß“ 44 pt semibold per the plan's table (LookMetrics).
struct RowHeading: View {
    let title: String
    let size: LookRowTitle

    var body: some View {
        heading.lineLimit(1).accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var heading: some View {
        if size == .standard {
            Text(title).textRole(.sectionTitle)
        } else {
            Text(title).font(.system(size: RowHeading.points(size), weight: .semibold))
        }
    }

    static func points(_ size: LookRowTitle) -> CGFloat {
        switch size {
        case .dezent: 27
        case .standard: 34
        case .gross: 44
        }
    }
}
