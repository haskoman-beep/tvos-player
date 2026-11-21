import SwiftUI

/// Welle C-d: Spoilerschutz. Nur das Standbild wird weichgezeichnet, die Beschriftung daneben bleibt scharf.
/// Der Weichzeichner ist vorberechnet (`RemoteImage(blur:)`, ein Bitmap je Variante, kein Live-Effekt je Zeile).
enum SpoilerStill {
    /// Radius in Punkten für `RemoteImage(blur:)`.
    static let blurRadius: CGFloat = 18
}

extension View {
    /// Augen-Symbol über einem weichgezeichneten Standbild.
    func spoilerMark(_ active: Bool) -> some View {
        overlay {
            if active {
                Image(systemName: "eye.slash").font(.title2).foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}
