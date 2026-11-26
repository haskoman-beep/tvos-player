import SwiftUI
import PlayerCore

/// Build 5 (b5r): one film/series card of a home list row (`HomeRowView.listCard`). Device test 2: `metric:
/// home.rowBody` up to 24 per 5 s while pressing right. The row owns the `@FocusState` of its cards, so each focus
/// move (old card → nothing → new card: two changes) runs the row body, and before this every built card of the row
/// ran its link, tile menu, accessibility and title line again. Equatable over the values it draws: on a focus move
/// only the cards whose `focused` flag changed run their body, the others are skipped (`.equatable()`).
/// The closures (activation, row menu actions, neighbour focus) are not compared: they reach the row's and the page's
/// state through its storage, so an older copy acts the same; `menu.canMoveUp` is its only value and is compared.
struct HomeRowCard<Label: View>: View, Equatable {
    let route: Route
    /// Accessibility label (Top 10: with the rank) and value (year, progress).
    let name: String
    let accessibilityText: String
    let titles: CardTitleSlot?
    let focused: Bool
    let inContinueRow: Bool
    let inWatchlistRow: Bool
    /// What decides `label` (item, rank, card form, title room, row style, upcoming row).
    let labelKey: HomeRowCardKey
    let focus: FocusState<Route?>.Binding
    let onActivate: (Route) -> Route?
    let menu: HomeRowMenu?
    let onLeave: () -> Void
    let label: Label
    /// Home page only (`metric: home.rowBody` field `zellen`).
    @Environment(\.homeRowFocusMemory) private var homeMemory

    nonisolated static func == (a: HomeRowCard, b: HomeRowCard) -> Bool {
        // Split into single checks (CI type checker: keep each expression short).
        guard a.focused == b.focused, a.route == b.route, a.labelKey == b.labelKey else { return false }
        guard a.name == b.name, a.accessibilityText == b.accessibilityText, a.titles == b.titles else { return false }
        guard a.inContinueRow == b.inContinueRow, a.inWatchlistRow == b.inWatchlistRow else { return false }
        let moveA: Bool? = a.menu?.canMoveUp
        let moveB: Bool? = b.menu?.canMoveUp
        return moveA == moveB
    }

    var body: some View {
        let _ = RowBodyMeter.cellPass(onHome: homeMemory != nil)
        // Same modifiers in the same order as `HomeRowView.card` + `listCard` before (focus, Wave L menu, VoiceOver).
        let link = NavigationLinkish(route: route, onActivate: onActivate, label: label)
            .focused(focus, equals: route)
            .tileMenu(route.tileItem, inContinueRow: inContinueRow, inWatchlistRow: inWatchlistRow, row: menu,
                      onLeave: onLeave)
            .accessibilityLabel(name)
            .accessibilityValue(accessibilityText)
        ThemeCard(title: labelKey.item.name, titleMode: titles?.mode ?? .aus, focused: focused,
                  width: titles?.width ?? 0, shift: titles?.shift ?? 0) { link }
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
}
