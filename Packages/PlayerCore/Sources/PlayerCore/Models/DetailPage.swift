import Foundation

/// Wave F-n: pure rules of the detail page hero.
///
/// - „Sofort abspielen“ (best choice card, wave G-a) only for movies and only with the setting
///   `PlayerComfortSettings.instantPlay` (default off). Off: no card, no best choice is built, „Abspielen“ is the
///   main button and has the entry focus (F-c rule §3.2).
/// - The title's poster sits left of the info block (meta line, badges, tagline, description). It is exactly as
///   tall as that block, at the poster aspect ratio 2:3.
public enum DetailPage {
    /// Main action of a movie detail page that takes the entry and return focus.
    public enum MainAction: String, Sendable, Equatable {
        /// „Sofort abspielen“ / „Weiter mit letzter Quelle“ card.
        case instantPlay
        /// „Abspielen“ / „Fortsetzen ab …“.
        case play
    }

    /// Build 5 device test 1 (item 3): the page's backdrop is the image the tile and the hero showed (already in the
    /// image cache); the meta image only fills a gap. Meta first had shown another picture, loaded again.
    public static func backdrop(tile: String?, meta: String?) -> String? {
        func usable(_ s: String?) -> String? { s.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } }
        return usable(tile) ?? usable(meta)
    }

    /// Whether the page shows the „Sofort abspielen“ card and builds a best choice at all.
    public static func showsInstantPlay(setting: Bool, isSeries: Bool) -> Bool {
        setting && !isSeries
    }

    /// Entry and return focus of a movie page: the card when it is shown and has a pick, else „Abspielen“.
    /// (The „Keine Quelle gefunden“ button never takes the entry focus.)
    public static func mainAction(setting: Bool, isSeries: Bool, hasPick: Bool) -> MainAction {
        showsInstantPlay(setting: setting, isSeries: isSeries) && hasPick ? .instantPlay : .play
    }

    /// Seconds after the entry focus during which a card that arrives late (sources were still loading) takes the
    /// focus over from „Abspielen“ (wave G-a).
    public static let lateCardWindow: TimeInterval = 2

    /// Whether a card that just arrived takes the focus: only with the card shown, while the focus is still on
    /// „Abspielen“ and at most `lateCardWindow` after the entry.
    public static func lateCardTakesFocus(setting: Bool, isSeries: Bool, focusOnPlay: Bool,
                                          sinceEntry: TimeInterval?) -> Bool {
        guard showsInstantPlay(setting: setting, isSeries: isSeries), focusOnPlay, let t = sinceEntry else { return false }
        return t >= 0 && t <= lateCardWindow
    }

    // MARK: Poster left of the info block

    /// Poster aspect ratio (width / height), as the poster tiles.
    public static let posterAspect: Double = 2.0 / 3.0
    /// Below this block height the poster would be a thumbnail next to two short lines: it is left out.
    public static let minPosterHeight: Double = 120
    /// Gap between the poster and the info block in points.
    public static let posterGap: Double = 40

    /// Poster size for a measured info block. `blockHeight` is the laid-out block; `bottomInset` is empty room below
    /// the last text line inside it (the description's focus highlight padding), so the poster ends with the text.
    /// nil = no poster (block too small or not measured yet).
    public static func posterSize(blockHeight: Double, bottomInset: Double = 0) -> (width: Double, height: Double)? {
        guard blockHeight.isFinite, bottomInset.isFinite else { return nil }
        let h = (blockHeight - max(0, bottomInset)).rounded()
        guard h >= minPosterHeight else { return nil }
        return ((h * posterAspect).rounded(), h)
    }

    /// Whether a new measurement should replace the stored one: ignores sub-point jitter, so the layout does not
    /// keep re-measuring itself.
    public static func shouldUpdate(measured: Double, stored: Double) -> Bool {
        abs(measured - stored) >= 1
    }
}
