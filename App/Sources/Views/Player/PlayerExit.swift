import SwiftUI
import PlayerCore

/// Geordneter Ausstieg (Welle C-c, #26) und schwarze Abdeckung nach dem Hintergrund (#20).
/// Die Engine setzt beim Start die Anzeige-Kriterien (Bildrate, HDR/Dolby Vision) und gibt sie bei `stop()` frei;
/// der Fernseher schaltet dann zurück. Schließt der Player sofort, sieht man das Menü während des Umschaltens
/// grau oder verzerrt, manche Fernseher bleiben hängen. Deshalb: Abdeckung → kurz warten → stoppen → den Wechsel
/// abwarten (Plan in PlayerCore `ModeSwitchExit`, höchstens 6 s) → schließen.
extension PlayerControls {
    /// Menü/„Andere Quelle“/zu lange im Hintergrund: Fortschritt speichern und geordnet schließen.
    func leaveWithModeSwitch() {
        guard !leaving else { return }
        leave {
            saveProgress()
            engine.pause()   // Ton sofort aus; gestoppt wird nach der Abdeckung
            blackCover = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(ModeSwitchExit.coverDelay))
                engine.stop()
                // „Inhalt anpassen“ aus: tvOS schaltet nie um, nichts abzuwarten.
                guard AetherBackend.systemMatchesContent != false else { dismiss(); return }
                let clock = { ProcessInfo.processInfo.systemUptime }
                var plan = ModeSwitchExit(stoppedAt: clock())
                while true {
                    switch plan.observe(switching: AetherBackend.displayModeSwitchInProgress, now: clock()) {
                    case .wait:
                        try? await Task.sleep(for: .seconds(ModeSwitchExit.pollInterval))
                    case .close(let reason):
                        RemoteLog.info("player", "Ausstieg: \(reason)")
                        dismiss()
                        return
                    }
                }
            }
        }
    }

    /// Ende der Datei / „Nächste Folge“: startet gleich die nächste Wiedergabe, bleibt der HDMI-Modus stehen
    /// (Einstellung „HDMI-Modus zwischen Folgen halten“), sonst normaler Stopp.
    func stopBeforeNext(_ nextStarts: Bool) {
        if nextStarts, prefs.display?.keepModeBetweenEpisodes == true { engine.stopKeepingDisplayMode() } else { engine.stop() }
    }

    /// Zurück aus dem Hintergrund: 0,6 s schwarz, damit keine Bildreste der alten Sitzung zu sehen sind.
    func coverAfterBackground() {
        blackCover = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(ModeSwitchExit.backgroundReturnCover))
            // Inzwischen verlassen: Abdeckung bleibt bis zum Schließen.
            guard !leaving else { return }
            blackCover = false
        }
    }
}
