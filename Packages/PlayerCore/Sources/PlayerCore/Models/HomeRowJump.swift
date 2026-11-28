import Foundation

// Phase 0a.1 device test (28.11., 4 of 79 row changes in the `Reihe fokussiert` lines jumped over rows):
//
// 1. Stale row frames. The home page keeps each row's frame in the list content (`HomeTopEdgeWatch.rowSpans`) for
//    the focus scroll target, the heading checks and the rescue of dropped presses. A frame is written only when a
//    built row's frame changes; rows the lazy list has not built keep the frame they had. Before this, a changed row
//    order only dropped rows that left the page, so after "Reihe verschoben 5→8: Preise" (09:33:08.663) the focus
//    scroll at 09:33:12.501 still found Genres at its old place 3930…4362 while Netflix Top 10 sat at 3930…4556:
//    `Fokus-Scroll auf Reihenoberkante: Ziel 4035 → 3930 (Reihe 3930…4362)` picked the wrong row (Netflix then got no
//    "Fokus-Scroll übernimmt"). `keptFrames` names the frames a change cannot have moved; every other frame stays
//    but is unconfirmed until the row writes it again. `onGeometryChange` only writes a frame that changed, so a
//    built row the change did not move (a row between two swapped rows of equal height, a row behind a row of zero
//    height) never confirms it: dropping those frames would leave a built, visible row without one (review of
//    51392a0). `usableSpans` therefore ignores an unconfirmed frame only where a confirmed frame overlaps it (the
//    place now belongs to another row, as Genres' at 09:33:12.501).
//
// 2. Diagnosis: the log cannot tell whether the focus engine really jumped over rows or passed through rows that
//    did not report their focus (jumps 3 and 4 came at the remote's repeat speed, ~140 ms per row, and jump 3 had a
//    "Fokus außerhalb der Reihen" in between). The home page now maps every vertical UIKit focus update in the list
//    to its rows (`skipped`) and logs the jumps, and logs a row that held the UIKit focus but did not report it.

public enum HomeRowJump {
    /// Rows whose stored frame is certainly still valid after the shown rows changed from `old` to `new` (both in
    /// page order). Positions before the first changed index stay; a pure reorder (same rows) also keeps the rows
    /// after the last changed index (the heights in front of them sum up the same). Every other row may have moved
    /// (its frame becomes unconfirmed, see `usableSpans`).
    public static func keptFrames(old: [UUID], new: [UUID]) -> Set<UUID> {
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var keep = Set(new.prefix(prefix))
        guard old.count == new.count, Set(old) == Set(new) else { return keep }
        var suffix = 0
        while suffix < new.count - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        keep.formUnion(new.suffix(suffix))
        return keep
    }

    /// The stored row frames the focus scroll target, the heading checks and the rescue may use: every confirmed
    /// frame, and an unconfirmed one (`unconfirmed`: not written since an order change may have moved it) unless a
    /// confirmed frame overlaps it. Frames that only touch do not overlap.
    public static func usableSpans(_ spans: [UUID: HomeRowSpan], unconfirmed: Set<UUID>) -> [UUID: HomeRowSpan] {
        guard !unconfirmed.isEmpty else { return spans }
        let confirmed = spans.filter { !unconfirmed.contains($0.key) }.map(\.value)
        return spans.filter { id, span in
            !unconfirmed.contains(id) || !confirmed.contains { $0.minY < span.maxY && span.minY < $0.maxY }
        }
    }

    /// The rows between `from` and `to` (page order `order`) when one focus update passed over them; empty for
    /// neighbours, the same row or rows not on the page.
    public static func skipped(from: UUID, to: UUID, order: [UUID]) -> [UUID] {
        guard let a = order.firstIndex(of: from), let b = order.firstIndex(of: to), abs(a - b) > 1 else { return [] }
        return Array(order[(min(a, b) + 1)..<max(a, b)])
    }

    /// How long a row may take to report a focus UIKit gave it (seconds; the report is immediate, a SwiftUI update
    /// later).
    public static let reportWait: Double = 0.25

    /// The row reported the focus UIKit gave it at `enteredAt`: a report at or after that moment (seconds, same
    /// clock), or one shortly before (the row's report can come in the update before the UIKit notification).
    public static func reported(enteredAt: Double, lastReport: Double?) -> Bool {
        guard let lastReport else { return false }
        return lastReport >= enteredAt - reportWait
    }

    // MARK: Log lines ("nav")

    /// One skipped row: its title and stored frame ("ohne Rahmen": the lazy list had not built it since the last
    /// layout change).
    public struct SkippedRow: Hashable, Sendable {
        public var title: String
        public var span: HomeRowSpan?

        public init(title: String, span: HomeRowSpan?) {
            self.title = title
            self.span = span
        }
    }

    /// "Fokus sprang über Reihen (UIKit): Trending → Genres · runter · übersprungen 2: In Theaters 2248…2874,
    /// Studios ohne Rahmen · Versatz 1702 · Scrollziel 1557 · 142 ms nach dem letzten Schritt".
    public static func jumpLine(from: String, to: String, down: Bool, skipped: [SkippedRow], offset: Double?,
                                flightTarget: Double?, sinceLastMs: Int?) -> String {
        let rows = skipped.map { s in
            s.span.map { "\(s.title) \(pt($0.minY))…\(pt($0.maxY))" } ?? "\(s.title) ohne Rahmen"
        }
        var parts = ["Fokus sprang über Reihen (UIKit): \(from) → \(to)", down ? "runter" : "hoch",
                     "übersprungen \(skipped.count): \(rows.joined(separator: ", "))"]
        if let offset { parts.append("Versatz \(pt(offset))") }
        if let flightTarget { parts.append("Scrollziel \(pt(flightTarget))") }
        if let sinceLastMs { parts.append("\(sinceLastMs) ms nach dem letzten Schritt") }
        return parts.joined(separator: " · ")
    }

    /// "Reihe In Theaters hatte den Fokus (UIKit), meldete ihn nicht binnen 250 ms · jetzt in Studios".
    public static func unreportedLine(title: String, now: String?) -> String {
        "Reihe \(title) hatte den Fokus (UIKit), meldete ihn nicht binnen \(Int((reportWait * 1000).rounded())) ms"
            + " · jetzt in \(now ?? "keiner Reihe")"
    }

    private static func pt(_ v: Double) -> String { "\(Int(v.rounded()))" }
}
