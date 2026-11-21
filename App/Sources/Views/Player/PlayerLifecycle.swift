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
    /// Inaktiv/Hintergrund: pausieren, Fortschritt speichern, Scrobble-Pause. Zurück: pausiert lassen; hat die Engine
    /// das Bild freigegeben, baut erst der Play-Druck neu auf. Zu lange weg: schließen.
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
        case .returnedFromBackground:
            // Kein Neuaufbau jetzt: AetherEngine spielt danach von selbst weiter. Erst Play baut neu auf
            // (restoreAndPlay); Fehlerzustand regelt recover bzw. die Fehlerkarte.
            restorePending = engine.errorText == nil && engine.needsForegroundVideoRestore
            RemoteLog.info("player", "Zurück aus dem Hintergrund · Neuaufbau \(restorePending ? "beim nächsten Play" : "nicht nötig")")
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

    /// Play nach dem Hintergrund: Sitzung an der Stelle neu aufbauen; der Neuaufbau spielt los.
    /// Läuft schon ein Neuaufbau (Play-Taste und Play von außen kurz nacheinander), passiert nichts.
    func restoreAndPlay() {
        guard !leaving, !restoring else { return }
        restoring = true
        restorePending = false
        life.userResumed()
        recoverTask?.cancel()
        recoverTask = Task {
            defer { restoring = false }
            do { try await engine.recover() } catch {
                guard !Task.isCancelled, !leaving else { return }
                RemoteLog.error("player", "Neuaufbau nach Hintergrund fehlgeschlagen: \(error)")
                // Nicht blind play(): die Fehlerleiter entscheidet. Meldet die Engine selbst einen Fehler, ruft
                // onChange(errorText) recover auf (bricht diese Aufgabe ab); sonst nach 1,5 s escalate → recover.
                guard engine.errorText == nil else { return }
                restoring = false
                await escalate(after: error)
                return
            }
            guard !Task.isCancelled, !leaving else { return }
            // Wie playUnlessHeld: ging die App während des Neuaufbaus wieder weg (TV aus), pausiert bleiben.
            if life.holdsPlayback { engine.pause() } else if !engine.isPlaying { engine.play() }
            RemoteLog.info("player", "Nach Hintergrund neu aufgebaut · \(engine.stateText) bei \(Int(engine.currentTime))s")
            // Sicherheitsnetz: Addon-Untertitel gemerkt, aber keine externe Spur mehr da → neu holen.
            if !addonTrackURLs.isEmpty, !engine.subtitleTracks.contains(where: \.isExternal) {
                RemoteLog.info("player", "Addon-Untertitel nach Neuaufbau weg → neu holen")
                addonTrackURLs = [:]
                let audioLanguage = engine.audioTracks.first { $0.id == engine.activeAudioID }?.language
                addonSubTask?.cancel()
                addonSubTask = Task { await loadAddonSubtitles(audioLanguage: audioLanguage) }
            }
        }
    }

    private func closeAfterBackground() {
        guard !leaving else { return }
        RemoteLog.info("player", "Länger als \(Int(life.closeAfter / 60)) min im Hintergrund → Player schließt")
        leave { saveProgress(); engine.stop(); dismiss() }
    }
}
