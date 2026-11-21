import Foundation
import AetherEngine
import PlayerCore

extension PlaybackEngine {
    /// Backends ohne Fehlerarten: nur der Text (Einordnung „unbekannt“, bisheriges Verhalten).
    var playbackFailure: PlaybackFailure? { errorText.map { PlaybackFailure(message: $0) } }
}

extension AetherBackend {
    /// `errorInfo` der Engine (Art, Domäne, Code) für die Fehlerleiter. Die Engine setzt es vor `state = .error`.
    var playbackFailure: PlaybackFailure? {
        if let i = engine.errorInfo {
            return PlaybackFailure(kind: i.kind.rawValue, domain: i.underlyingDomain, code: i.underlyingCode,
                                   ffmpegCode: i.ffmpegErrorCode, message: i.message)
        }
        return errorText.map { PlaybackFailure(message: $0) }
    }
}
