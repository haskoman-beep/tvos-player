import Foundation

/// Lade- und Puffer-Wächter (ohne Engine, ohne Zeitgeber): Die App fragt ihn jede Sekunde mit dem aktuellen
/// Zustand. Er entscheidet nichts über Neuladen oder Quellenwechsel, er meldet nur eine Zeitüberschreitung;
/// die Fehlerleiter (`RecoveryPlanner`) ordnet sie als `.timeout` ein und wählt den Schritt.
///
/// Regeln:
/// - Start: Zeitüberschreitung nach `startLimit` ohne neuen Startschritt; ein langsamer, aber fortschreitender
///   Start läuft weiter, höchstens bis `startHardLimit` insgesamt.
/// - Nachpuffern im laufenden Film: nach `stallLimit` am Stück.
/// - Nach einem Sprung: nach `seekLimit` ohne Ankunft.
/// - Ausgesetzt (Hintergrund, Neuaufbau ausstehend, Fehlermeldung, Fernseher schaltet um): alle Uhren auf null.
///   Pausiert lädt nichts, zählt also nie.
public struct LoadWatchdog: Sendable {
    /// Ohne neuen Startschritt (Engine-Startstand) bis zum Abbruch.
    public static let startLimit: TimeInterval = 30
    /// Start insgesamt, auch wenn er noch fortschreitet (großer Remux über einen langsamen Dienst).
    public static let startHardLimit: TimeInterval = 120
    /// Nachpuffern am Stück im laufenden Film.
    public static let stallLimit: TimeInterval = 25
    /// Sprung ohne Ankunft. Über Plattencache-Lesegrenze + Ursprung-Leerlauf (14 + 6 s), damit dessen eigener
    /// Rückfall auf den direkten Link nach einem Sprung in eine Cache-Lücke zuerst greift (Test pinnt das).
    public static let seekLimit: TimeInterval = 25

    /// Was gerade beobachtet wird.
    public enum Phase: String, Sendable { case idle, starting, stalled, seeking }

    /// Vorsilbe der Fehlerarten des Wächters.
    public static let kindPrefix = "watchdog_"

    /// Grund der Zeitüberschreitung; `kind` geht als Fehlerart an die Fehlerleiter.
    public enum Verdict: String, Sendable, Equatable {
        case start, stall, seek
        public var kind: String { LoadWatchdog.kindPrefix + rawValue }
        public var logText: String {
            switch self {
            case .start: "Start hängt"
            case .stall: "Puffern hängt"
            case .seek: "Sprung hängt"
            }
        }
    }

    /// Zustand je Takt.
    public struct Observation: Sendable, Equatable {
        /// Laden läuft (eigener Ladeauftrag unterwegs oder Engine im Ladezustand).
        public var starting: Bool
        /// Kennung des Startstands (Schritt + Anteil); jede Änderung zählt als Fortschritt.
        public var progressMark: String?
        /// Engine springt gerade.
        public var seeking: Bool
        /// Engine puffert im laufenden Film nach.
        public var buffering: Bool
        /// Nicht beobachten (Gründe siehe Typ-Doku).
        public var suspended: Bool

        public init(starting: Bool = false, progressMark: String? = nil, seeking: Bool = false,
                    buffering: Bool = false, suspended: Bool = false) {
            self.starting = starting; self.progressMark = progressMark; self.seeking = seeking
            self.buffering = buffering; self.suspended = suspended
        }
    }

    public private(set) var phase: Phase = .idle
    public private(set) var since: Date?
    public private(set) var lastProgress: Date?
    private var mark: String?

    public init() {}

    /// Ein Takt. Liefert höchstens einmal je Phase eine Zeitüberschreitung; danach beginnt die Uhr von vorn.
    public mutating func observe(_ o: Observation, now: Date = Date()) -> Verdict? {
        if o.suspended { reset(); return nil }
        let next: Phase = o.starting ? .starting : o.seeking ? .seeking : o.buffering ? .stalled : .idle
        if next != phase {
            phase = next
            since = next == .idle ? nil : now
            lastProgress = since
            mark = o.progressMark
            return nil
        }
        guard let start = since else { return nil }
        switch phase {
        case .idle:
            return nil
        case .starting:
            if o.progressMark != mark { mark = o.progressMark; lastProgress = now }
            let quiet = now.timeIntervalSince(lastProgress ?? start)
            if quiet >= Self.startLimit || now.timeIntervalSince(start) >= Self.startHardLimit { return fire(now) ? .start : nil }
        case .stalled:
            if now.timeIntervalSince(start) >= Self.stallLimit { return fire(now) ? .stall : nil }
        case .seeking:
            if now.timeIntervalSince(start) >= Self.seekLimit { return fire(now) ? .seek : nil }
        }
        return nil
    }

    /// Alle Uhren auf null (z. B. nach einem Neustart durch die Fehlerleiter).
    public mutating func reset() { phase = .idle; since = nil; lastProgress = nil; mark = nil }

    private mutating func fire(_ now: Date) -> Bool {
        since = now; lastProgress = now
        return true
    }
}

/// Routenwechsel der Tonausgabe (HDMI-Handshake, Fernseher schaltet um, Tonsitzung unterbrochen).
/// Ein Fehler innerhalb von `window` Sekunden danach (und nach dem ersten Bild) gilt als Folge davon: einmal an
/// der Stelle neu laden statt die Quelle zu wechseln. Jeder Wechsel wird höchstens einmal verbraucht.
public struct RouteChangeWindow: Sendable {
    public static let window: TimeInterval = 10
    /// `AVAudioSession.RouteChangeReason.categoryChange`: kommt bei jedem eigenen Kategoriewechsel, kein Gerätewechsel.
    public static let ignoredReasonRaw: UInt = 3

    public private(set) var lastChange: Date?

    public init() {}

    /// Routenwechsel (Grund als Rohwert) oder Unterbrechung (`reasonRaw` nil) merken.
    public mutating func note(reasonRaw: UInt?, at now: Date = Date()) {
        if reasonRaw == Self.ignoredReasonRaw { return }
        lastChange = now
    }

    /// true = Fehler fällt in das Fenster nach einem Wechsel; der Wechsel ist damit verbraucht.
    public mutating func consume(now: Date = Date(), afterFirstFrame: Bool) -> Bool {
        guard afterFirstFrame, let t = lastChange, now.timeIntervalSince(t) <= Self.window, now >= t else { return false }
        lastChange = nil
        return true
    }
}

/// Zeitstempel eines Wiedergabestarts: t0 Auswahl (Tastendruck), t1 Link aufgelöst (Player lädt),
/// t2 erstes Bild, t3 spielt. Ergibt genau eine Logzeile, sobald t3 da ist.
public struct StartTiming: Sendable, Equatable {
    /// Ein Druck, der länger zurückliegt, gehört nicht mehr zu diesem Start.
    public static let maxTapAge: TimeInterval = 180

    public private(set) var tap: Date?
    public private(set) var resolved: Date?
    public private(set) var firstFrame: Date?
    public private(set) var playing: Date?
    public private(set) var logged = false
    /// Task 1.8: the same points on a monotonic clock (`ProcessInfo.systemUptime`, seconds) for the `metric:` lines;
    /// they follow `tap`, `resolved` and `firstFrame` (set and dropped together).
    public private(set) var tapUptime: TimeInterval?
    public private(set) var resolvedUptime: TimeInterval?
    public private(set) var firstFrameUptime: TimeInterval?

    public init() {}

    public mutating func markTap(_ now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self = StartTiming(); tap = now; tapUptime = uptime
    }

    /// Player beginnt zu laden. Ein alter Druck (oder keiner, z. B. nächste Folge) zählt ab hier.
    public mutating func markResolved(_ now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if let t = tap, now.timeIntervalSince(t) > Self.maxTapAge || now < t { tap = nil; tapUptime = nil }
        if let u = tapUptime, uptime - u > Self.maxTapAge || uptime < u { tap = nil; tapUptime = nil }
        resolved = now; resolvedUptime = uptime
        firstFrame = nil; firstFrameUptime = nil; playing = nil; logged = false
    }

    public mutating func markFirstFrame(_ now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard resolved != nil, firstFrame == nil else { return }
        firstFrame = now; firstFrameUptime = uptime
    }

    /// Task 1.8: whole milliseconds between two monotonic points (nil when one is missing; never negative).
    public static func ms(_ from: TimeInterval?, _ to: TimeInterval?) -> Int? {
        guard let from, let to else { return nil }
        return max(0, Int(((to - from) * 1000).rounded()))
    }

    /// Spielt: liefert die Logzeile genau einmal (nil = schon gemeldet oder kein Start erfasst).
    public mutating func markPlaying(_ now: Date = Date()) -> String? {
        guard let r = resolved, !logged else { return nil }
        if firstFrame == nil { firstFrame = now }
        playing = now
        logged = true
        let text = Self.line(tap: tap, resolved: r, firstFrame: firstFrame ?? now, playing: now)
        // Der Druck gehört zu diesem Start; die nächste Folge (ohne Druck) misst ab dem Laden.
        tap = nil; tapUptime = nil
        return text
    }

    static func line(tap: Date?, resolved: Date, firstFrame: Date, playing: Date) -> String {
        func ms(_ a: Date, _ b: Date) -> String { "\(Int((b.timeIntervalSince(a) * 1000).rounded())) ms" }
        let origin = tap ?? resolved
        var parts: [String] = []
        if let tap { parts.append("Auswahl→Link \(ms(tap, resolved))") }
        parts.append("Link→Bild \(ms(resolved, firstFrame))")
        parts.append("Bild→spielt \(ms(firstFrame, playing))")
        return "Startzeit: " + parts.joined(separator: " · ") + " · gesamt \(ms(origin, playing))"
            + (tap == nil ? " (ohne Tastendruck)" : "")
    }
}
