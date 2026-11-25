import Foundation
import PlayerCore

/// Build 4 follow-up S4: one line `metric: home.rowBody <n> · karten <k> · fokus <m>` per 5 s window in which focus
/// moved between row tiles: n = body passes of `HomeRowView` (all rows together), k = body passes of `PosterCard`
/// (the cards the stable anchor action lets `.equatable()` skip), m = focus moves onto a row tile.
/// Silent while nothing moves. Counting is integer adds; a window costs one sleeping task and one log line.
@MainActor
enum RowBodyMeter {
    private static var counter = BodyPassCounter()

    /// `HomeRowView.body`.
    static func pass() { if counter.pass() { closeLater() } }

    /// `PosterCard.body`.
    static func cardPass() { if counter.cardPass() { closeLater() } }

    /// Focus landed on a tile of a row.
    static func focusMoved() { if counter.focusMoved() { closeLater() } }

    private static func closeLater() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(BodyPassCounter.window))
            guard let w = RowBodyMeter.counter.close() else { return }
            RemoteLog.metric(.homeRowBody, ms: w.passes, fields: ["karten": "\(w.cards)", "fokus": "\(w.focusMoves)"])
        }
    }
}
