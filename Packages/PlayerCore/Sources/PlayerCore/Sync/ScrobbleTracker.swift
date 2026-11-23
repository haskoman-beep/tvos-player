import Foundation

/// Eine Scrobble-Meldung an Trakt/Simkl.
public struct ScrobbleEvent<Item> {
    public var action: ScrobbleAction
    public var item: Item
    /// 0…1
    public var fraction: Double

    /// A `stop` from 80 % on: the services count the title as watched, so the app marks it watched locally too.
    public var watched: Bool { action == .stop && fraction >= ScrobbleTracker<Item>.watchedThreshold }
}

extension ScrobbleEvent: Sendable where Item: Sendable {}

/// Scrobble-Regeln für eine laufende Wiedergabe (eine Sitzung zur Zeit):
/// - `start` nur unter 80 % (sonst entstünde beim Weiterschauen von fast Gesehenem ein doppelter Verlaufseintrag).
/// - `pause` nur, wenn gerade eine Sitzung läuft; erst ein Fortschritt über die Pausenstelle hinaus schickt wieder
///   `start` (Speichern während der Pause startet nichts).
/// - Je Sitzung und Titel genau ein `stop`.
/// - `stop` beim Verlassen/Titelwechsel, wenn eine Sitzung läuft oder ab 80 %; ab `finishedAt` genau einmal.
public struct ScrobbleTracker<Item> {
    public static var startLimit: Double { 0.8 }
    /// Same threshold as the services: a stop from here on is a history entry.
    public static var watchedThreshold: Double { 0.8 }

    struct Session {
        var item: Item
        var id: String
        var fraction: Double
        var active: Bool
        var completed: Bool
        /// Fraction at which playback was paused; nil = not paused.
        var pausedAt: Double? = nil
    }

    private(set) var session: Session?
    public let finishedAt: Double

    public init(finishedAt: Double) { self.finishedAt = finishedAt }

    public var currentID: String? { session?.id }
    public var isActive: Bool { session?.active == true }

    public mutating func progress(_ item: Item, id: String, fraction: Double) -> [ScrobbleEvent<Item>] {
        var out: [ScrobbleEvent<Item>] = []
        if let s = session, s.id != id { out += close(s); session = nil }
        var s = session ?? Session(item: item, id: id, fraction: fraction, active: false, completed: false)
        s.item = item; s.fraction = fraction
        if !s.completed {
            if fraction >= finishedAt {
                out.append(ScrobbleEvent(action: .stop, item: item, fraction: fraction))
                s.active = false; s.completed = true
            } else if let p = s.pausedAt, fraction <= p {
                // Still paused (a save while paused): no start.
            } else if !s.active && fraction < Self.startLimit {
                s.pausedAt = nil
                out.append(ScrobbleEvent(action: .start, item: item, fraction: fraction))
                s.active = true
            }
        }
        session = s
        return out
    }

    public mutating func pause(id: String) -> [ScrobbleEvent<Item>] {
        guard var s = session, s.id == id, s.active, !s.completed else { return [] }
        s.active = false
        s.pausedAt = s.fraction
        session = s
        return [ScrobbleEvent(action: .pause, item: s.item, fraction: s.fraction)]
    }

    public mutating func end(id: String) -> [ScrobbleEvent<Item>] {
        guard let s = session, s.id == id else { return [] }
        session = nil
        return close(s)
    }

    func close(_ s: Session) -> [ScrobbleEvent<Item>] {
        guard !s.completed, s.active || s.fraction >= Self.startLimit else { return [] }
        return [ScrobbleEvent(action: .stop, item: s.item, fraction: s.fraction)]
    }
}

extension ProgressBook {
    /// One watched rule for the progress save and the scrobble stop: with a sync service the services' 80 %,
    /// else the local 92 %.
    public static func finishedThreshold(syncConnected: Bool) -> Double {
        syncConnected ? ScrobbleTracker<String>.watchedThreshold : finishedAt
    }
}
