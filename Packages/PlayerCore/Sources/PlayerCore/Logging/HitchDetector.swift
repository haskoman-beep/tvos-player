import Foundation

/// Erkennt Hänger des Hauptthreads aus den Zeitpunkten eines Runloop-Beobachters.
/// Ein Hänger ist die Zeit zwischen zwei Runloop-Schritten ohne Schlafpause dazwischen,
/// die über `threshold` liegt. Höchstens eine Meldung je `minInterval`; was dazwischen fällt,
/// wird gezählt und mit der nächsten Meldung ausgegeben, spätestens aber beim nächsten Schlafengehen
/// nach `minInterval` als Sammelzeile (`milliseconds == 0`), damit ein letzter Schwall nicht verschwindet.
public struct HitchDetector: Sendable {
    public struct Hitch: Sendable, Equatable {
        /// Dauer des gemeldeten Hängers in Millisekunden (0 = nur Sammelzeile der unterdrückten).
        public var milliseconds: Int
        /// Seit der letzten Meldung unterdrückte Hänger (zu dicht hintereinander).
        public var suppressed: Int
        /// Längster unterdrückter Hänger in Millisekunden (0 ohne unterdrückte).
        public var suppressedMax: Int
    }

    public static let defaultThreshold: TimeInterval = 0.25

    public var threshold: TimeInterval
    public var minInterval: TimeInterval
    private var lastStep: TimeInterval?
    private var lastReport: TimeInterval?
    private var suppressed = 0
    private var suppressedMax = 0

    public init(threshold: TimeInterval = defaultThreshold, minInterval: TimeInterval = 2) {
        self.threshold = threshold; self.minInterval = minInterval
    }

    /// Runloop geht schlafen: die Wartezeit bis zum Aufwachen zählt nicht.
    public mutating func willSleep() { lastStep = nil }

    /// Wie `willSleep()`; gibt zusätzlich die Sammelzeile der unterdrückten Hänger zurück, wenn `minInterval` um ist.
    public mutating func willSleep(at now: TimeInterval) -> Hitch? {
        lastStep = nil
        guard suppressed > 0, let r = lastReport, now - r >= minInterval else { return nil }
        lastReport = now
        let h = Hitch(milliseconds: 0, suppressed: suppressed, suppressedMax: suppressedMax)
        suppressed = 0; suppressedMax = 0
        return h
    }

    /// Ein Runloop-Schritt zum Zeitpunkt `now` (monotone Sekunden). Gibt eine Meldung zurück, falls fällig.
    public mutating func step(at now: TimeInterval) -> Hitch? {
        defer { lastStep = now }
        guard let last = lastStep else { return nil }
        let gap = now - last
        guard gap > threshold else { return nil }
        let ms = Int((gap * 1000).rounded())
        if let r = lastReport, now - r < minInterval {
            suppressed += 1
            suppressedMax = max(suppressedMax, ms)
            return nil
        }
        lastReport = now
        let h = Hitch(milliseconds: ms, suppressed: suppressed, suppressedMax: suppressedMax)
        suppressed = 0; suppressedMax = 0
        return h
    }

    /// Log-Text einer Meldung.
    public static func text(_ h: Hitch, note: String?, footprintMB: Int?) -> String {
        var s = h.milliseconds > 0 ? "Hauptthread hing \(h.milliseconds) ms" : "Hauptthread: Nachtrag"
        if let note, !note.isEmpty { s += " · zuletzt: \(note)" }
        if let mb = footprintMB { s += " · belegt \(mb) MB" }
        if h.suppressed > 0 { s += " · dazu \(h.suppressed) weitere (bis \(h.suppressedMax) ms)" }
        return s
    }
}
