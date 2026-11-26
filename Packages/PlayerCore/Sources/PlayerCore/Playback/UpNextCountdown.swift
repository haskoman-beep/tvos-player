import Foundation

/// Up-next countdown (Task 5.4, user decision 26.11.: 20 s as in the plan, Build 198 had 10 s). The card appears at
/// the credits (`skip.upNextAt`) or 20 s before the end; when the countdown runs out the next episode starts.
public enum UpNextCountdown {
    public static let seconds = 20

    /// Heading of the up-next surfaces.
    public static func line(seconds: Int) -> String { "Nächste Folge in \(seconds) s" }
}
