import Foundation

/// Task 5.4 (`player.timeDisplay`): the two time texts under the timeline of the control bar.
/// `rest` → ("42:10", "−1:25:50"); `gesamt` → ("42:10", "2:08:00"); `ende` → ("42:10", "Endet um 21:41").
/// Without a known duration (still loading) the trailing text stays empty in every mode.
public enum PlayerTimeText {
    public static func make(position: TimeInterval, duration: TimeInterval, now: Date, mode: LookTimeDisplay,
                            timeZone: TimeZone = .current) -> (leading: String, trailing: String) {
        let pos = clamp(position)
        let leading = clock(pos)
        guard duration.isFinite, duration > 0 else { return (leading, "") }
        let remaining = max(0, duration - pos)
        let trailing: String = switch mode {
        case .rest: "−" + clock(remaining)
        case .gesamt: clock(duration)
        // At the very end the end time is "now" (MediaLabels.endTime gives nil for nothing left).
        case .ende: MediaLabels.endTime(remaining: max(remaining, 0.001), now: now, timeZone: timeZone) ?? ""
        }
        return (leading, trailing)
    }

    /// "42:10" below an hour, "1:25:50" from an hour on (same as the scrub preview's `PlayerClock`).
    public static func clock(_ seconds: TimeInterval) -> String {
        let t = Int(clamp(seconds))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
                         : String(format: "%d:%02d", t / 60, t % 60)
    }

    private static func clamp(_ s: TimeInterval) -> TimeInterval { s.isFinite ? max(0, s) : 0 }
}
