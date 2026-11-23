import Foundation

/// Task 1.8: fixed measuring points for the remote log (names from the system design, analysis 04 §6), so builds can
/// be compared line by line. The app logs them in the category `metric` as
/// `<name> <ms>[ · <field> <value>]…`, e.g. `metric: start.usable 812` or `metric: start.catalog 140 · reihen 6`.
public enum Metric: String, CaseIterable, Sendable, Hashable {
    /// App start until the first focus on the home page is set (`LaunchFocus`); once per start.
    case startUsable = "start.usable"
    /// Reading the profiles (and the progress of the active profile) in `AppModel.init`.
    case startProfiles = "start.profiles"
    /// App start until the catalogue snapshot from disk is in the cache (or known to be missing).
    case startCatalog = "start.catalog"
    /// Detail page appeared until the first visible badge.
    case detailBadges = "detail.badges"
    /// Source list opened until its first row is shown.
    case streamsFirstRow = "streams.firstRow"
    /// Deduplicating and ordering the source list.
    case streamsOrder = "streams.order"
    /// Press on a source until the player starts loading.
    case playerLoadBegins = "player.loadBegins"
    /// Player starts loading until the first frame.
    case playerFirstFrame = "player.firstFrame"
    /// Second session build at the start because the audio choice differs from the engine's (0 ms = none).
    case playerAudioReload = "player.audioReload"
    /// Merging the remote progress (Trakt/Simkl) into the local book.
    case syncMerged = "sync.merged"

    /// Log category of all measuring points.
    public static let category = "metric"

    /// The message part of a measuring line: name, milliseconds (never negative), then the fields in their order.
    public static func line(_ metric: Metric, ms: Int, fields: KeyValuePairs<String, String> = [:]) -> String {
        var out = "\(metric.rawValue) \(max(0, ms))"
        for (name, value) in fields { out += " · \(name) \(value)" }
        return out
    }

    /// Whole milliseconds of a duration (rounded, never negative).
    public static func ms(_ d: Duration) -> Int {
        let c = d.components
        let value = Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
        return max(0, Int(value.rounded()))
    }
}
