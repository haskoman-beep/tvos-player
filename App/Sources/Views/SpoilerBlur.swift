import SwiftUI

/// Welle C-d: Spoilerschutz. Nur das Standbild wird weichgezeichnet, die Beschriftung daneben bleibt scharf.
extension View {
    func spoilerBlur(_ active: Bool) -> some View {
        // Weichzeichner innerhalb des Rahmens halten (opaque), damit kein heller Rand entsteht.
        blur(radius: active ? 18 : 0, opaque: true)
            .overlay {
                if active {
                    Image(systemName: "eye.slash").font(.title2).foregroundStyle(.white.opacity(0.8))
                }
            }
    }
}
