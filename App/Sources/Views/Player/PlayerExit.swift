import SwiftUI
import PlayerCore

/// Geordneter Ausstieg (Welle C-c, #26) und schwarze Abdeckung nach dem Hintergrund (#20).
/// Die Engine setzt beim Start die Anzeige-Kriterien (Bildrate, HDR/Dolby Vision) und gibt sie bei `stop()` frei;
/// der Fernseher schaltet dann zurück. Schließt der Player sofort, sieht man das Menü während des Umschaltens
/// grau oder verzerrt, manche Fernseher bleiben hängen. Deshalb: Abdeckung → kurz warten → stoppen → den Wechsel
/// abwarten (Plan in PlayerCore `ModeSwitchExit`, höchstens 6 s) → schließen.
/// Während des Ablaufs ist `leaving` gesetzt: alle Fernbedienungs-Befehle sind gesperrt (PlayerScreen).
extension PlayerControls {
    /// Menü/„Andere Quelle“/zu lange im Hintergrund: Fortschritt speichern und geordnet schließen.
    func leaveWithModeSwitch() {
        guard !leaving else { return }
        leave {
            saveProgress()
            orderlyExit { dismiss() }
        }
    }

    /// Ende der Datei. Startet gleich die nächste Folge und ist „HDMI-Modus zwischen Folgen halten“ an, bleibt
    /// der Modus stehen; sonst (Film, letzte Folge, „Noch da?“, Autoplay aus, Up-next abgebrochen) geordnet
    /// schließen. `autoplay` geht unverändert an den Aufrufer (er zeigt z. B. „Noch da?“).
    func finishAtEnd(autoplay: Bool) {
        guard !leaving else { return }
        if prefs.display?.keepsMode(nextStarts: autoplay, hasNext: nextTitle != nil) == true {
            engine.stopKeepingDisplayMode()
            leave { onEnded(autoplay) }
        } else {
            leave { orderlyExit { onEnded(autoplay) } }
        }
    }

    /// „Nächste Folge“ (Karte/Countdown): Modus halten, wenn eingestellt; sonst normaler Stopp (die nächste
    /// Wiedergabe schaltet ohnehin gleich wieder um).
    func stopBeforeNext(_ nextStarts: Bool) {
        if prefs.display?.keepsMode(nextStarts: nextStarts, hasNext: nextTitle != nil) == true {
            engine.stopKeepingDisplayMode()
        } else {
            engine.stop()
        }
    }

    /// Kern des Ausstiegs (nur innerhalb von `leave` aufrufen): laufende Aufgaben abbrechen, Ton aus, Abdeckung,
    /// stoppen, Moduswechsel abwarten, dann `close`.
    func orderlyExit(then close: @escaping @MainActor () -> Void) {
        loadTask?.cancel(); recoverTask?.cancel(); addonSubTask?.cancel()
        // Wartezeit auf den Wechsel nach Quellformat (vor dem Stopp lesen, danach ist es zurückgesetzt).
        let grace = ModeSwitchExit.startGrace(sourceFormat: engine.sourceVideoFormatName)
        engine.pause()   // Ton sofort aus; gestoppt wird nach der Abdeckung
        blackCover = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(ModeSwitchExit.coverDelay))
            engine.stop()
            // „Inhalt anpassen“ aus: tvOS schaltet nie um, nichts abzuwarten.
            guard AetherBackend.systemMatchesContent != false else { close(); return }
            let clock = { ProcessInfo.processInfo.systemUptime }
            var plan = ModeSwitchExit(stoppedAt: clock(), startGrace: grace)
            while true {
                switch plan.observe(switching: AetherBackend.displayModeSwitchInProgress, now: clock()) {
                case .wait:
                    try? await Task.sleep(for: .seconds(ModeSwitchExit.pollInterval))
                case .close(let reason):
                    RemoteLog.info("player", "Ausstieg: \(reason) (Wartezeit \(grace) s)")
                    close()
                    return
                }
            }
        }
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
