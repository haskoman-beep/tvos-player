import Foundation

/// Phase 0a.1 (part 3): the one place that decides which numbers may enter `ProgressBook` and `FileProgressBook`
/// and how a bad stored number is repaired. Two kinds of rules:
///
/// - A new report (player → book, sync service → book) with an unusable number is ignored as a whole, so a glitch of
///   the player or a broken answer of a service never damages an existing entry.
/// - A stored entry (file, backup, an entry written directly into `entries`) is repaired field by field, so one bad
///   number never costs the entry, let alone the whole book; its other fields stay.
///
/// Every number that leaves a book (fraction, remaining time, resume position, JSON) goes through the stored rules,
/// so JSONEncoder never sees a non-finite value and the UI never gets one.
enum ProgressNumbers {
    /// A player report is usable: finite position ≥ 0 and a finite length > 0. A length of 0 or less (stream without a
    /// known length, player not ready) and a negative position (glitch while seeking) are not clamped, because that
    /// would overwrite real progress with 0.
    static func isUsableReport(position: Double, duration: Double) -> Bool {
        duration.isFinite && duration > 0 && position.isFinite && position >= 0
    }

    /// Stored length: finite and > 0, else 0 (= length unknown, as next-up markers and remote-only entries use it).
    static func storedDuration(_ d: Double) -> Double { d.isFinite && d > 0 ? d : 0 }

    /// Stored position: non-finite or negative → 0; beyond a known length → the length. With an unknown length a
    /// finite position stays as it is.
    static func storedPosition(_ p: Double, duration: Double) -> Double {
        guard p.isFinite, p > 0 else { return 0 }
        return duration > 0 ? min(p, duration) : p
    }

    /// A fraction for use (0…1): non-finite → 0, else clamped.
    static func unit(_ f: Double) -> Double { f.isFinite ? min(1, max(0, f)) : 0 }

    /// Stored `remoteFraction`: non-finite → nil (= no remote fraction), else clamped to 0…1.
    static func storedFraction(_ f: Double?) -> Double? {
        guard let f, f.isFinite else { return nil }
        return min(1, max(0, f))
    }

    /// A remote fraction from a sync service is usable: finite and ≥ 0. Above 1 (a service reporting 105 %) it is
    /// clamped to 1 by the caller; negative or non-finite the remote entry is ignored like a bad player report.
    static func isUsableRemoteFraction(_ f: Double) -> Bool { f.isFinite && f >= 0 }

    /// Dates: a non-finite time (only possible through `Date(timeIntervalSinceReferenceDate: .nan)`) → `.distantPast`,
    /// so the entry loses every "newer wins" comparison; a finite time outside `.distantPast`…`.distantFuture` is
    /// clamped into it, so the ISO 8601 form (4-digit year) of `ProgressStore` stays readable.
    static func date(_ d: Date) -> Date {
        guard d.timeIntervalSinceReferenceDate.isFinite else { return .distantPast }
        return min(max(d, .distantPast), .distantFuture)
    }
}
