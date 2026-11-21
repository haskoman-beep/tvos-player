import UIKit
import AVKit
import AetherEngine
import PlayerCore

/// Ton- und Bild-Ladeoptionen der Engine aus dem Profil (Welle C-c, #7/#13).
/// - Formung (Nachtmodus, Dialog, Lautheit) nur, wenn eingeschaltet: sonst bleibt `audioShaping` der
///   Engine-Standard und Dolby Digital/Atmos werden wie bisher durchgereicht.
/// - Ton-Versatz schon beim Laden (kein Neu-Ankern nach dem Start), Brücke für TrueHD/DTS-HD.
/// - „Inhalt anpassen“ kommt aus der Systemeinstellung (Bild > Inhalt anpassen), nie aus einem eigenen Schalter.
extension AetherBackend {
    func applyAudioOptions(_ prefs: LoadPrefs, to o: inout LoadOptions) {
        if let match = Self.systemMatchesContent { o.matchContentEnabled = match }
        Self.keptModeToken &+= 1   // eine neue Wiedergabe übernimmt einen gehaltenen HDMI-Modus
        if let v = prefs.display {
            if v.panelPresentsDolbyVision { o.panelPresentsDolbyVision = true }
            if !v.foldsDolbyVisionFEL { o.foldsDolbyVisionFEL = false }
            if v != DisplayModeSettings() { RemoteLog.info("bild", "Ladeoptionen: \(v.logText)") }
        }
        guard let a = prefs.audio else { return }
        if a.bridge == .lossless { o.audioBridgeMode = .lossless }
        if a.audioDelayMs != 0 { o.audioDelaySeconds = a.audioDelaySeconds }
        if a.shapesAudio {
            o.audioShaping = AudioShaping(maxChannels: a.maxChannels, dialogueGainDB: a.dialogueGain,
                                          compressor: a.nightMode ? .night : nil,
                                          loudnessTargetLUFS: a.loudnessTarget)
        }
        if a != AudioShapingSettings() || Self.systemMatchesContent == false {
            RemoteLog.info("ton", "Ladeoptionen: \(a.logText) · Inhalt anpassen \(Self.systemMatchesContent.map { $0 ? "an" : "aus" } ?? "?")")
        }
    }

    // MARK: HDMI-Modus zwischen Folgen halten

    /// Wechselt bei jedem Laden; der Rücksetz-Zeitgeber prüft, ob inzwischen eine Wiedergabe begonnen hat.
    private static var keptModeToken = 0
    private static var modeKept = false

    /// Stopp vor der nächsten Folge: Anzeige-Kriterien bleiben stehen, damit der Fernseher bei gleichem Format
    /// nicht über den Standardmodus umschaltet (Engine `stop(resetDisplayCriteria: false)`). Startet binnen
    /// `DisplayModeSettings.keepTimeout` keine Wiedergabe, wird der Modus doch zurückgesetzt.
    func stopKeepingDisplayMode() {
        stopped = true
        engine.stop(resetDisplayCriteria: false, finalTeardown: true)
        if let s = cacheSession { cacheSession = nil; Task { await DiskCacheProxy.shared.close(s) } }
        Self.modeKept = true
        let token = Self.keptModeToken
        RemoteLog.info("bild", "HDMI-Modus für die nächste Folge gehalten")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(DisplayModeSettings.keepTimeout))
            guard Self.modeKept, Self.keptModeToken == token else { return }
            RemoteLog.info("bild", "Keine nächste Wiedergabe → HDMI-Modus zurückgesetzt")
            Self.releaseKeptDisplayMode()
        }
    }

    /// Gehaltenen Modus freigeben (die neue Engine setzt nur zurück, was sie selbst gesetzt hat).
    static func releaseKeptDisplayMode() {
        guard modeKept else { return }
        modeKept = false
        PlayerWindow.key?.avDisplayManager.preferredDisplayCriteria = nil
    }

    /// Systemeinstellung „Inhalt anpassen“ (Bildrate/Dynamikumfang); nil = kein Fenster gefunden.
    static var systemMatchesContent: Bool? {
        PlayerWindow.key?.avDisplayManager.isDisplayCriteriaMatchingEnabled
    }

    /// tvOS schaltet gerade den Bildmodus des Fernsehers um.
    static var displayModeSwitchInProgress: Bool {
        PlayerWindow.key?.avDisplayManager.isDisplayModeSwitchInProgress ?? false
    }
}

/// Schlüsselfenster der App (für Anzeige-Kriterien und die Touchflächen-Geste).
@MainActor
enum PlayerWindow {
    static var key: UIWindow? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }
}
