import Foundation

/// Build 5 device test 1 (items 2 and 7): an up or down press in the home rows that the focus engine dropped
/// (`UIFocusSystem.movementDidFailNotification`): the target above or below was not built (lazy list) or lay outside
/// the list after the heading snap. Up from the first row could then never reach the hero buttons (and the tab bar
/// above them), other presses were swallowed and the next one seemed to skip a row. The page moves the focus itself.
public enum HomeMoveRescue: Equatable, Sendable {
    /// Scroll to the very top and focus „Abspielen“ (from there up reaches the tab bar).
    case heroButtons
    /// Focus the row at this index (its remembered or first card), scrolled to the list's top edge.
    case row(Int)

    /// - `up`: direction of the failed press (false = down).
    /// - `focusedRow`: index of the row that holds the focus among the shown rows; nil = focus not in a row.
    /// - `edge`: the page's top edge (`.heroButtons` only with a hero).
    public static func decide(up: Bool, focusedRow: Int?, rowCount: Int, edge: HomeTopEdge) -> HomeMoveRescue? {
        guard let i = focusedRow, i >= 0, i < rowCount else { return nil }
        if up {
            if i > 0 { return .row(i - 1) }
            return edge == .heroButtons ? .heroButtons : nil   // without a hero the tab bar is the system's job
        }
        return i + 1 < rowCount ? .row(i + 1) : nil
    }

    /// Log line: "Hoch|Runter verschluckt in Reihe <n> (<title>) → Knopfzeile|Reihe <m> (<title>)".
    public func line(up: Bool, from: Int, fromTitle: String, toTitle: String?) -> String {
        let target: String
        switch self {
        case .heroButtons: target = "Knopfzeile"
        case .row(let i): target = "Reihe \(i + 1) (\(toTitle ?? "?"))"
        }
        return "\(up ? "Hoch" : "Runter") verschluckt in Reihe \(from + 1) (\(fromTitle)) → \(target) fokussiert"
    }
}
