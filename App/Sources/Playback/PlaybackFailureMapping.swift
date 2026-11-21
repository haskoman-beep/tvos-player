import Foundation
import AetherFEL
import PlayerCore

extension PlaybackEngine {
    /// Backends ohne Fehlerarten: nur der Text (Einordnung „unbekannt“, bisheriges Verhalten).
    var playbackFailure: PlaybackFailure? { errorText.map { PlaybackFailure(message: $0) } }
    /// Backends ohne Hintergrund-Abbau müssen nie neu aufbauen.
    var needsForegroundVideoRestore: Bool { false }
}

extension AetherBackend {
    /// `errorInfo` der Engine (Art, Domäne, Code) für die Fehlerleiter. Die Engine setzt es vor `state = .error`.
    var playbackFailure: PlaybackFailure? {
        // Nur im Fehlerzustand: ein altes errorInfo nach erfolgreichem Neuaufbau zählt nicht.
        if case .error = engine.state, let i = engine.errorInfo {
            return PlaybackFailure(kind: i.kind.rawValue, domain: i.underlyingDomain, code: i.underlyingCode,
                                   ffmpegCode: i.ffmpegErrorCode, message: i.message)
        }
        return errorText.map { PlaybackFailure(message: $0) }
    }

    /// AetherEngine: Bild im Hintergrund freigegeben, Quelle/Stelle/Spurwahl behalten („rebuild before play()“).
    var needsForegroundVideoRestore: Bool { engine.needsForegroundVideoRestore }
}
