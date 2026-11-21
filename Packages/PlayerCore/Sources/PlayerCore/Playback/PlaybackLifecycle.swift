import Foundation

/// App-Zustand aus Sicht des Players (SwiftUI `scenePhase`, ohne SwiftUI-Typ).
public enum AppPhase: String, Sendable {
    case active, inactive, background
}

/// Player-Verhalten bei TV aus / Home-Taste / Bildschirmschoner (testbar, ohne Engine).
/// - inaktiv oder Hintergrund: Wiedergabe pausieren (auch während des Ladens: dann nicht von selbst starten).
/// - zurück: pausiert lassen; nach echtem Hintergrund die Sitzung erst beim Play-Druck neu aufbauen.
/// - länger als `closeAfter` im Hintergrund: Player schließen.
public struct PlaybackLifecycle: Sendable {
    public enum Action: Equatable, Sendable {
        /// Pausieren, Fortschritt speichern, Scrobble-Pause senden.
        case pause
        /// Hintergrund ohne laufende Wiedergabe: nur merken.
        case none
        /// Zurück aus dem Hintergrund: pausiert lassen. Hat die Engine das Bild freigegeben, erst beim Play-Druck
        /// neu aufbauen (der Neuaufbau startet sonst von selbst).
        case returnedFromBackground
        /// Zu lange im Hintergrund: Player schließen.
        case close
    }

    /// tvOS schickt die App beim Bildschirmschoner erst nach etwa 10 min in den Hintergrund; ab dann zählt diese Zeit.
    public var closeAfter: TimeInterval = 600
    /// Vom System pausiert (nicht vom Nutzer): kein automatisches Weiterspielen, auch nicht nach dem Laden.
    public private(set) var holdsPlayback = false
    public private(set) var backgroundSince: Date?
    public private(set) var phase: AppPhase = .active

    public init(closeAfter: TimeInterval = 600) { self.closeAfter = closeAfter }

    /// Szenenwechsel. `isActiveMedia`: Wiedergabe läuft oder lädt gerade.
    public mutating func phaseChanged(to new: AppPhase, isActiveMedia: Bool, now: Date = Date()) -> Action {
        let old = phase
        phase = new
        switch new {
        case .inactive, .background:
            if new == .background, backgroundSince == nil { backgroundSince = now }
            guard old == .active else { return .none }
            guard isActiveMedia else { return .none }
            holdsPlayback = true
            return .pause
        case .active:
            defer { backgroundSince = nil }
            guard let since = backgroundSince else { return .none }
            return now.timeIntervalSince(since) >= closeAfter ? .close : .returnedFromBackground
        }
    }

    /// Noch im Hintergrund und lange genug weg (für einen Zeitgeber, falls die App nicht ausgesetzt ist).
    public func shouldClose(now: Date = Date()) -> Bool {
        guard phase == .background, let since = backgroundSince else { return false }
        return now.timeIntervalSince(since) >= closeAfter
    }

    /// Der Nutzer will spielen (Play/Pause, Erneut versuchen): Sperre aufheben.
    public mutating func userResumed() { holdsPlayback = false }
}
