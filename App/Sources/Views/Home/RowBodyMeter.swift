import Foundation
import PlayerCore

/// Build 4 follow-up S4: one line `metric: home.rowBody <n> · karten <k> · fokus <m>` per 5 s window in which focus
/// moved between home row tiles (home page only): n = body passes of `HomeRowView` (all rows together), k = body passes of `PosterCard`
/// (the cards the stable anchor action lets `.equatable()` skip), m = focus moves onto a row tile; b5r: `zellen` = body
/// passes of the equatable `HomeRowCard` (about two per focus move expected). Build 6 (redraw): the row body no longer
/// reads its focus state, so n should stay near 0 for moves inside a row (one pass of the left row per row change,
/// plus data changes and programmatic focus moves).
/// Silent while nothing moves. Counting is integer adds; a window costs one sleeping task and one log line.
@MainActor
enum RowBodyMeter {
    private static var counter = BodyPassCounter()

    // S4 review: `onHome` = the view sits on the home page (`homeRowFocusMemory` set in both layouts; `HomeFocus`
    // exists only with the hero). Folder pages, Library and detail pages use the same views and are not counted.

    /// `HomeRowView.body`.
    static func pass(onHome: Bool) { if onHome, counter.pass() { closeLater() } }

    /// `PosterCard.body`.
    static func cardPass(onHome: Bool) { if onHome, counter.cardPass() { closeLater() } }

    /// b5r: `HomeRowCard.body`.
    static func cellPass(onHome: Bool) { if onHome, counter.cellPass() { closeLater() } }

    /// Focus landed on a tile of a row.
    static func focusMoved(onHome: Bool) { if onHome, counter.focusMoved() { closeLater() } }

    private static func closeLater() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(BodyPassCounter.window))
            guard let w = RowBodyMeter.counter.close() else { return }
            RemoteLog.metric(.homeRowBody, ms: w.passes,
                             fields: ["karten": "\(w.cards)", "zellen": "\(w.cells)", "fokus": "\(w.focusMoves)"])
        }
    }
}
