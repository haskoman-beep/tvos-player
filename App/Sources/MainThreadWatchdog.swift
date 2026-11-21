import Foundation
import QuartzCore
import PlayerCore

/// Welle C-b (#8): Hänger des Hauptthreads messen statt fühlen. Ein Beobachter am Haupt-Runloop notiert
/// jeden Schritt; liegt zwischen zwei Schritten (ohne Schlafpause) mehr als 250 ms, geht eine Log-Zeile
/// mit Dauer, letzter Notiz („Brotkrume“) und Speicherverbrauch raus (Regeln in `HitchDetector`).
/// Schalter: Einstellungen › Über › „Ruckler protokollieren“ (Standard an, kostet nur einen Zeitstempel je Schritt).
@MainActor
enum MainThreadWatchdog {
    static let settingKey = "diag.hitchLog"
    private static var observer: CFRunLoopObserver?
    private static var detector = HitchDetector()
    /// Letzte kurze Ereignisnotiz (z. B. „Fokus tt123“), erscheint in der Hänger-Zeile.
    private static var lastNote: String?

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    /// Beim Start und nach Umschalten aufrufen.
    static func apply() {
        isEnabled ? start() : stop()
    }

    static func note(_ s: String) {
        guard observer != nil else { return }
        lastNote = s
    }

    private static func start() {
        guard observer == nil else { return }
        detector = HitchDetector()
        let activities: CFRunLoopActivity = [.entry, .beforeTimers, .beforeSources, .beforeWaiting, .afterWaiting, .exit]
        let obs = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, activities.rawValue, true, 0) { _, activity in
            // Läuft auf dem Hauptthread (Beobachter am Haupt-Runloop).
            MainActor.assumeIsolated { MainThreadWatchdog.observe(activity) }
        }
        observer = obs
        CFRunLoopAddObserver(CFRunLoopGetMain(), obs, .commonModes)
        RemoteLog.info("ruckler", "Hänger-Wächter an (ab \(Int(HitchDetector.defaultThreshold * 1000)) ms)")
    }

    private static func stop() {
        guard let obs = observer else { return }
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), obs, .commonModes)
        observer = nil
        lastNote = nil
        RemoteLog.info("ruckler", "Hänger-Wächter aus")
    }

    private static func observe(_ activity: CFRunLoopActivity) {
        let now = CACurrentMediaTime()
        if let h = detector.step(at: now) {
            let mb = ImagePipeline.footprint().map { Int($0 / UInt64(ImageCacheBudget.mb)) }
            RemoteLog.info("ruckler", HitchDetector.text(h, note: lastNote, footprintMB: mb))
        }
        if activity == .beforeWaiting { detector.willSleep() }
    }
}
