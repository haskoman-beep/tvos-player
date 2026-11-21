import SwiftUI
import AetherEngine
import PlayerCore

/// Welle C-a: Was der Lade-Wächter von der Engine braucht.
struct LoadActivity: Equatable {
    /// Erstes Bild liegt zur Anzeige bereit.
    var hasFirstFrame: Bool
    /// Nachpuffern mitten in der Wiedergabe (Zustand bleibt „spielt“).
    var buffering: Bool
    /// Sprung läuft.
    var seeking: Bool
}

/// Standard für Backends ohne diese Angaben: kein Nachpuffern/Sprung bekannt, Bild = spielt.
extension PlaybackEngine {
    var loadActivity: LoadActivity { LoadActivity(hasFirstFrame: isPlaying, buffering: false, seeking: false) }
}

/// AetherEngine 7.71.2: `hasFirstFrameReadyForDisplay`, `isBuffering`, `state == .seeking`.
extension AetherBackend {
    var loadActivity: LoadActivity {
        LoadActivity(hasFirstFrame: engine.hasFirstFrameReadyForDisplay, buffering: engine.isBuffering,
                     seeking: engine.state == .seeking)
    }
}

/// Zustand des Players für Wächter, Netz-Warten, Startzeiten und „Quelle stabil“.
struct PlayerStabilityState {
    var watchdog = LoadWatchdog()
    /// `engine.load` des Starts läuft (loadAndStart).
    var loadInFlight = false
    /// Start wurde für das Netz-Warten abgebrochen: nach dem Netz den ganzen Start wiederholen.
    var startPending = false
    /// Erstes Bild dieser Wiedergabe gesehen (Routenwechsel zählen erst danach).
    var firstFrameSeen = false
    /// Hinweis, solange auf das Netz gewartet wird (nil = kein Warten).
    var networkNotice: String?
    /// Fehlerfrei gespielte Sekunden dieser Quelle; bei `FailedLinkBook.healthySeconds` einmal „stabil“ melden.
    var healthySeconds = 0.0
    var healthyReported = false
}

extension PlayerControls {
    /// Start beginnt (loadAndStart): Zeitstempel t1, Wächter frisch.
    func stabilityLoadBegins() {
        stab.loadInFlight = true
        stab.firstFrameSeen = false   // wiederholter Start: t2 und Routenfenster neu
        stab.watchdog.reset()
        PlaybackStability.shared.timing.markResolved()
    }

    func stabilityLoadEnded() { stab.loadInFlight = false }

    /// Umstände für die Fehlerleiter (offline, Routenwechsel kurz vorher).
    func stabilityContext() -> RecoveryContext {
        PlaybackStability.shared.recoveryContext(afterFirstFrame: stab.firstFrameSeen)
    }

    /// Fehlerleiter sagt „warten“: Hinweis zeigen, Wächter ruht, nach dem Netz geht es weiter (onChange isOnline).
    func stabilityWaitForNetwork(_ message: String, startAborted: Bool) {
        if startAborted { stab.startPending = true }
        stab.watchdog.reset()
        guard stab.networkNotice == nil else { return }
        stab.networkNotice = message
        RemoteLog.info("player", "Warte auf Netz\(startAborted ? " (Start abgebrochen)" : "")")
    }

    /// Leiter macht weiter (neu laden): Netz-Hinweis weg. Liefert true, wenn der ganze Start zu wiederholen ist.
    func stabilityResumes(startAborted: Bool) -> Bool {
        stab.networkNotice = nil
        stab.watchdog.reset()
        let restart = startAborted || stab.startPending
        stab.startPending = false
        return restart
    }

    /// Netz zurück: wartet die Leiter, geht es weiter.
    func stabilityNetworkChanged(_ online: Bool) {
        guard online, stab.networkNotice != nil, !leaving else { return }
        RemoteLog.info("player", "Netz wieder da → weiter")
        recover("Netz wieder da", networkBack: true)
    }

    /// Jede Sekunde: Wächter prüfen, „stabil“ zählen. `blocked`: Fehlermeldung oder Ladefehler steht.
    func stabilityTick(blocked: Bool) {
        let a = engine.loadActivity
        if a.hasFirstFrame { stabilityFirstFrame() }
        if engine.isPlaying, engine.errorText == nil, !a.buffering {
            stab.healthySeconds += 1
            if !stab.healthyReported, stab.healthySeconds >= FailedLinkBook.healthySeconds {
                stab.healthyReported = true
                onSourceVerdict(.healthy)
            }
        }
        let status = engine.startupStatus
        let suspended = blocked || leaving || restorePending || restoring || life.holdsPlayback
            || stab.networkNotice != nil || status?.awaitingDisplaySwitch == true || engine.errorText != nil
        let o = LoadWatchdog.Observation(
            starting: stab.loadInFlight || (engine.isLoading && !a.seeking),
            progressMark: status.map { String(describing: $0.step) + "-\(Int($0.fraction * 100))" },
            seeking: a.seeking, buffering: a.buffering, suspended: suspended)
        guard let v = stab.watchdog.observe(o) else { return }
        RemoteLog.error("player", "Lade-Wächter: \(v.logText) · \(engine.stateText) · bei \(Int(engine.currentTime))s")
        recover(v.logText, failure: PlaybackFailure(kind: v.kind))
    }

    /// Erstes Bild (t2).
    func stabilityFirstFrame() {
        guard !stab.firstFrameSeen else { return }
        stab.firstFrameSeen = true
        PlaybackStability.shared.timing.markFirstFrame()
    }

    /// Spielt (t3): eine Logzeile je Start.
    func stabilityPlaying() {
        if let line = PlaybackStability.shared.timing.markPlaying() { RemoteLog.info("player", line) }
    }
}

/// Hinweis im Player, solange die Fehlerleiter auf das Netz wartet (nicht modal, Fokus bleibt auf der Fläche).
struct PlayerNetworkBanner: View {
    let text: String?

    var body: some View {
        if let text {
            VStack {
                Label(text, systemImage: "wifi.slash")
                    .font(.headline)
                    .padding(.horizontal, 30).padding(.vertical, 18)
                    .background(.orange.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.top, 60)
                Spacer()
            }
            .allowsHitTesting(false)
        }
    }
}
