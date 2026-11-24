import Foundation

/// A-B-3: how long a failed picture stays blocked. Only "the picture does not exist" (HTTP 404/410) is remembered for
/// five minutes; network errors, timeouts, other HTTP answers and undecodable data only for 20 s, so a short Wi-Fi gap
/// or a slow picture service does not grey out tiles for minutes. A cancelled load is no failure at all.
public enum ImageFailure: Sendable, Equatable {
    case gone        // 404 / 410
    case transient   // offline, timeout, connection lost, 5xx, other answers, undecodable data

    public static let goneMemory: TimeInterval = 300
    public static let transientMemory: TimeInterval = 20

    /// Failure kind of an HTTP answer outside 200..<300 (nil for a success).
    public static func classify(status: Int) -> ImageFailure? {
        if (200..<300).contains(status) { return nil }
        return status == 404 || status == 410 ? .gone : .transient
    }

    /// Failure kind of a thrown error; nil means "cancelled" (not remembered).
    public static func classify(error: Error) -> ImageFailure? {
        if error is CancellationError { return nil }
        if let u = error as? URLError, u.code == .cancelled { return nil }
        return .transient
    }

    public var memory: TimeInterval { self == .gone ? Self.goneMemory : Self.transientMemory }

    /// Still blocked `now`, given the failure was noted at `since`.
    public func blocks(since: Date, now: Date) -> Bool { now.timeIntervalSince(since) < memory }

    /// Of several candidate addresses (size variant, original) the most hopeful outcome counts: one transient failure
    /// is enough to retry soon.
    public static func combine(_ a: ImageFailure?, _ b: ImageFailure) -> ImageFailure {
        a == .transient || b == .transient ? .transient : .gone
    }
}
