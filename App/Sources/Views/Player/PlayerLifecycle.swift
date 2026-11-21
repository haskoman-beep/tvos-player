import SwiftUI
import UIKit
import PlayerCore

/// TV aus (HDMI-CEC), Home-Taste, Bildschirmschoner: Szenenwechsel an den Player melden.
/// scenePhase und zusätzlich die UIApplication-Meldungen (willResignActive kommt sofort); doppelte Meldungen
/// sind harmlos, `PlaybackLifecycle` wertet nur echte Wechsel aus.
struct PlayerLifecycleObserver: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let onPhase: (AppPhase) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, p in
                switch p {
                case .active: onPhase(.active)
                case .inactive: onPhase(.inactive)
                case .background: onPhase(.background)
                @unknown default: break
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in onPhase(.inactive) }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in onPhase(.background) }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in onPhase(.active) }
    }
}

extension View {
    func onPlayerLifecycle(_ onPhase: @escaping (AppPhase) -> Void) -> some View {
        modifier(PlayerLifecycleObserver(onPhase: onPhase))
    }
}

extension PlayerControls {
    /// Inaktiv/Hintergrund: pausieren, Fortschritt speichern, Scrobble-Pause. Zurück: pausiert lassen; nach echtem
    /// Hintergrund die Sitzung neu aufbauen (die Engine gibt Video und Verbindungen frei). Zu lange weg: schließen.
    func handlePhase(_ phase: AppPhase) {
        guard !leaving else { return }
        let action = life.phaseChanged(to: phase, isActiveMedia: engine.isPlaying || engine.isLoading)
        if action != .none { RemoteLog.info("player", "App \(phase.rawValue) → \(action) · \(engine.stateText) bei \(Int(engine.currentTime))s") }
        switch action {
        case .none: break
        case .pause:
            engine.pause(); saveProgress(); onPause()
        case .close:
            closeAfterBackground()
        case .reloadPaused:
            // Fehlerzustand: das regelt recover bzw. die Fehlerkarte.
            guard engine.errorText == nil else { break }
            recoverTask?.cancel()
            recoverTask = Task {
                do { try await engine.recover() } catch {
                    RemoteLog.error("player", "Neuaufbau nach Hintergrund fehlgeschlagen: \(error)"); return
                }
                guard !Task.isCancelled, !leaving else { return }
                if life.holdsPlayback { engine.pause() }
                RemoteLog.info("player", "Nach Hintergrund neu aufgebaut · \(engine.stateText) bei \(Int(engine.currentTime))s")
            }
        }
        // Zeitgeber nur für den Fall, dass die App im Hintergrund nicht ausgesetzt wird; sonst prüft die Rückkehr.
        lifeTask?.cancel()
        guard phase == .background else { return }
        lifeTask = Task {
            try? await Task.sleep(for: .seconds(life.closeAfter))
            guard !Task.isCancelled, life.shouldClose() else { return }
            closeAfterBackground()
        }
    }

    private func closeAfterBackground() {
        guard !leaving else { return }
        RemoteLog.info("player", "Länger als \(Int(life.closeAfter / 60)) min im Hintergrund → Player schließt")
        leave { saveProgress(); engine.stop(); dismiss() }
    }
}
