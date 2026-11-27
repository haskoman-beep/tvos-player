import SwiftUI
import PlayerCore

/// Build 5 (b5r): one film/series card of a home list row (`HomeRowView.listCard`). Device test 2: `metric:
/// home.rowBody` up to 24 per 5 s while pressing right. The row owns the `@FocusState` of its cards, so each focus
/// move (old card → nothing → new card: two changes) runs the row body, and before this every built card of the row
/// ran its link, tile menu, accessibility and title line again. Equatable over the values it draws: on a focus move
/// only the cards whose `focused` flag changed run their body, the others are skipped (`.equatable()`).
/// Build 6 (redraw): the card no longer gets its focus flag from the row (the row body read `focusedRoute` for it and
/// ran twice per focus move). It follows its own button focus (`ButtonFocusProbe` inside the label reads
/// `isFocused`) and reports it to the row (`onFocus` → `RowFocusBox`), so a focus move runs only the two cards whose
/// focus changed and no row body. `focusSerial` (compared) runs every card once on a programmatic focus write.
/// The closures (activation, row menu actions, neighbour focus) are not compared: they reach the row's and the page's
/// state through its storage, so an older copy acts the same; `menu.canMoveUp` is compared, and the row value (which the
/// hide/delete closures capture) is part of `labelKey`.
struct HomeRowCard<Label: View>: View, Equatable {
    let route: Route
    /// Accessibility label (Top 10: with the rank) and value (year, progress).
    let name: String
    let accessibilityText: String
    let titles: CardTitleSlot?
    /// Build 6: the row's programmatic focus serial (`HomeRowView.focusCard`).
    let focusSerial: Int
    let inContinueRow: Bool
    let inWatchlistRow: Bool
    /// What decides `label` (item, rank, card form, title room, row style, upcoming row) and the row.
    let labelKey: HomeRowCardKey
    let focus: FocusState<Route?>.Binding
    let onActivate: (Route) -> Route?
    let menu: HomeRowMenu?
    let onLeave: () -> Void
    /// Build 6: this card's focus changed (to the row's `RowFocusBox`).
    let onFocus: (Bool) -> Void
    let label: Label
    /// Home page only (`metric: home.rowBody` field `zellen`).
    @Environment(\.homeRowFocusMemory) private var homeMemory
    /// Build 6: focus of this card's button (title line below: fade, shift), set by `ButtonFocusProbe`.
    @State private var focused = false

    nonisolated static func == (a: HomeRowCard, b: HomeRowCard) -> Bool {
        // Split into single checks (CI type checker: keep each expression short).
        guard a.focusSerial == b.focusSerial, a.route == b.route, a.labelKey == b.labelKey else { return false }
        guard a.name == b.name, a.accessibilityText == b.accessibilityText, a.titles == b.titles else { return false }
        guard a.inContinueRow == b.inContinueRow, a.inWatchlistRow == b.inWatchlistRow else { return false }
        let moveA: Bool? = a.menu?.canMoveUp
        let moveB: Bool? = b.menu?.canMoveUp
        return moveA == moveB
    }

    var body: some View {
        let _ = RowBodyMeter.cellPass(onHome: homeMemory != nil)
        // Same modifiers in the same order as `HomeRowView.card` + `listCard` before (focus, Wave L menu, VoiceOver).
        let report: (Bool) -> Void = onFocus
        let probed = label.background {
            ButtonFocusProbe { f in
                if focused != f { focused = f }
                report(f)
            }
        }
        let link = NavigationLinkish(route: route, onActivate: onActivate, label: probed)
            .focused(focus, equals: route)
            .tileMenu(route.tileItem, inContinueRow: inContinueRow, inWatchlistRow: inWatchlistRow, row: menu,
                      onLeave: onLeave)
            .accessibilityLabel(name)
            .accessibilityValue(accessibilityText)
        ThemeCard(title: labelKey.item.name, titleMode: titles?.mode ?? .aus, focused: focused,
                  width: titles?.width ?? 0, shift: titles?.shift ?? 0) { link }
    }
}

/// Build 6 (redraw): reports the focus of the button whose label it sits in (`isFocused` reaches the label only).
/// Empty and hidden; runs only when that focus changes. Reports "false" when it leaves the screen (a focused
/// placeholder removed by the loaded row, a removed card), as the row's focus state went nil then.
struct ButtonFocusProbe: View {
    let report: (Bool) -> Void
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
            .onChange(of: isFocused) { _, f in report(f) }
            // Re-review L3: on every appearance (not only the first, as `onChange(initial:)`), so a row that comes
            // back with this button still focused learns it again after the false of `onDisappear`.
            .onAppear { report(isFocused) }
            .onDisappear { report(false) }
    }
}

/// Build 5 (b5r): the inputs of a home card's label (`HomeRowView.cardContent`).
struct HomeRowCardKey: Equatable {
    var item: MetaPreview
    var rank: Int?
    var kind: TileKind
    var titled: Bool
    var style: RowStyle
    /// Row content „Heute neu“ (`UpcomingTodayCard`).
    var upcoming: Bool
    /// b5r review L1: the whole row value, so the row menu closures (hide/delete confirm with the row title) are
    /// rebuilt whenever the row changes, even when its cards stay the same.
    var row: HomeRow
}
