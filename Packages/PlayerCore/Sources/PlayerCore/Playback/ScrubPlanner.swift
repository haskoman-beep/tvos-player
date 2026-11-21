import Foundation

/// Spulen über die Touchfläche (testbar, ohne UIKit): Wischen mit Beschleunigung, Drehrad am Außenring,
/// Rastpunkte an Kapitel-/Intro-Kanten. Select bestätigt (`confirm`), Menü bricht ab (`cancel`).
///
/// Zeiten sind Sekunden auf der Achse von `currentTime`/`seek`, `now` monotone Sekunden des Aufrufers.
public struct ScrubPlanner: Sendable {
    /// So viele Wischpunkte entsprechen dem ganzen Film (ohne Beschleunigung).
    public static let pointsPerFilm: Double = 4800
    /// Mindestens so viele Sekunden je Wischpunkt (kurze Filme bleiben fein, aber nicht zäh).
    public static let minSecondsPerPoint: Double = 0.25
    /// Erst ab so vielen Punkten Wischweg beginnt das Spulen (ein Antippen spult nicht).
    public static let startThreshold: Double = 40
    /// Beschleunigung: ab dieser Wischgeschwindigkeit (Punkte/s) wird der Weg verlängert, bis `maxAcceleration`.
    public static let accelerationStart: Double = 600
    public static let accelerationSpan: Double = 1800
    public static let maxAcceleration: Double = 4
    /// Drehrad: Finger ruht so lange auf dem Außenring (Radius > `ringRadius`), dann zählt der Winkel.
    public static let ringRadius: Double = 0.72
    public static let ringDwell: Double = 0.15
    /// Ruhen heißt: in der Wartezeit weniger als so viel Winkel bewegt (Bogenmaß).
    public static let ringDwellTolerance: Double = 0.35
    /// Das Drehrad beginnt erst nach so viel Drehung (Bogenmaß): ein ruhender Finger am Rand vor einem
    /// ◀/▶-Klick startet kein Spulen.
    public static let wheelStartAngle: Double = 0.5
    /// Eine Umdrehung des Drehrads = so viele Sekunden (Feinsuche).
    public static let wheelSecondsPerTurn: Double = 24
    /// Nach einer Wischbewegung zählen ◀/▶ so lange nicht als ±10-s-Sprung (die Wischgeste löst sie mit aus).
    public static let moveSuppression: Double = 0.35
    /// Ohne Eingabe so lange: Spulen verwerfen (nichts springt).
    public static let idleTimeout: Double = 10
    /// Rastweite an Kanten (Sekunden).
    public static let snapTolerance: Double = 1.5
    /// Abstand zum Dateiende wie bei den ±10-s-Sprüngen (ein Sprung aufs letzte Bild beendet die Datei).
    public static let endGuard: Double = 5

    public private(set) var isActive = false
    public private(set) var origin: Double = 0
    public private(set) var target: Double = 0
    public private(set) var duration: Double = 0
    /// Kanten für das Einrasten (Kapitel, Intro, Abspann).
    public var snapEdges: [Double] = []
    public private(set) var lastInput: Double = -.greatestFiniteMagnitude
    private var lastPan: Double = -.greatestFiniteMagnitude
    /// Wischweg vor Beginn (für die Schwelle).
    private var pendingPoints: Double = 0
    /// Drehrad: Ruhebeginn, Winkel beim Ruhebeginn, letzter Winkel; `wheelOn` = Winkel zählt.
    private var dwellSince: Double?
    private var dwellAngle: Double = 0
    private var lastAngle: Double?
    public private(set) var wheelOn = false
    /// Drehung seit `wheelOn`, solange das Spulen noch nicht begonnen hat.
    private var wheelPending: Double = 0

    public init() {}

    /// Sekunden je Wischpunkt ohne Beschleunigung.
    public static func secondsPerPoint(duration: Double) -> Double {
        guard duration.isFinite, duration > 0 else { return minSecondsPerPoint }
        return max(duration / pointsPerFilm, minSecondsPerPoint)
    }

    /// Faktor für schnelles Wischen (1 = keine Beschleunigung).
    public static func acceleration(velocity: Double) -> Double {
        guard velocity.isFinite else { return 1 }
        let over = max(abs(velocity) - accelerationStart, 0) / accelerationSpan
        return 1 + min(over, 1) * (maxAcceleration - 1)
    }

    /// Zielbereich: 0 … Dauer − `endGuard` (ohne bekannte Dauer nur ≥ 0).
    public static func clamp(_ t: Double, duration: Double) -> Double {
        let upper = duration > endGuard * 2 ? duration - endGuard : Double.greatestFiniteMagnitude
        return min(max(0, t.isFinite ? t : 0), upper)
    }

    /// Nächste Kante innerhalb der Rastweite, sonst `t`.
    public static func snap(_ t: Double, edges: [Double], tolerance: Double = snapTolerance) -> Double {
        guard let best = edges.min(by: { abs($0 - t) < abs($1 - t) }), abs(best - t) <= tolerance else { return t }
        return best
    }

    /// Wischbewegung (waagrechter Weg seit dem letzten Aufruf, Geschwindigkeit in Punkten/s).
    /// Startet das Spulen nach `startThreshold` Punkten. Liefert true, wenn sich das Ziel geändert hat.
    @discardableResult
    public mutating func pan(deltaX: Double, velocityX: Double, position: Double, duration: Double, now: Double) -> Bool {
        guard deltaX.isFinite, deltaX != 0 else { return false }
        lastPan = now
        guard !wheelOn else { return false }   // Drehrad hat Vorrang (beide Eingaben kommen gleichzeitig)
        if !isActive {
            pendingPoints += deltaX
            guard abs(pendingPoints) >= Self.startThreshold else { return false }
            begin(position: position, duration: duration, now: now)
            let carried = pendingPoints
            pendingPoints = 0
            return move(by: carried * Self.secondsPerPoint(duration: duration) * Self.acceleration(velocity: velocityX), now: now)
        }
        return move(by: deltaX * Self.secondsPerPoint(duration: duration) * Self.acceleration(velocity: velocityX), now: now)
    }

    /// Wischgeste zu Ende (Finger weg): Schwelle zurücksetzen.
    public mutating func panEnded() { pendingPoints = 0 }

    /// Absolute Fingerposition auf der Touchfläche (x, y in −1…1, y nach oben). Drehrad am Außenring:
    /// im Uhrzeigersinn vor, gegen den Uhrzeigersinn zurück. Liefert true, wenn sich das Ziel geändert hat.
    @discardableResult
    public mutating func touch(x: Double, y: Double, position: Double, duration: Double, now: Double) -> Bool {
        guard x.isFinite, y.isFinite else { return false }
        let r = (x * x + y * y).squareRoot()
        guard r > Self.ringRadius else { touchEnded(); return false }
        let angle = atan2(y, x)
        defer { lastAngle = angle }
        if wheelOn {
            guard let last = lastAngle else { return false }
            let d = Self.unwrap(angle - last)
            // Uhrzeigersinn = Winkel nimmt ab (y nach oben) = vorwärts.
            var turn = d
            if !isActive {
                wheelPending += d
                guard abs(wheelPending) >= Self.wheelStartAngle else { return false }
                begin(position: position, duration: duration, now: now)
                turn = wheelPending; wheelPending = 0
            }
            return move(by: -turn / (2 * .pi) * Self.wheelSecondsPerTurn, now: now, snaps: false)
        }
        if let since = dwellSince {
            if abs(Self.unwrap(angle - dwellAngle)) > Self.ringDwellTolerance {
                dwellSince = now; dwellAngle = angle      // bewegt: Ruhe beginnt neu
            } else if now - since >= Self.ringDwell {
                wheelOn = true; wheelPending = 0
            }
        } else {
            dwellSince = now; dwellAngle = angle
        }
        return false
    }

    /// Finger weg oder in der Mitte: Drehrad aus (das Ziel bleibt bis Select/Menü).
    public mutating func touchEnded() {
        dwellSince = nil; lastAngle = nil; wheelOn = false; wheelPending = 0
    }

    /// ◀/▶-Klick während des Spulens: Ziel um `seconds` verschieben (ohne Rasten).
    @discardableResult
    public mutating func nudge(_ seconds: Double, now: Double) -> Bool {
        guard isActive else { return false }
        return move(by: seconds, now: now, snaps: false)
    }

    /// ◀/▶ kurz nach einer Wischbewegung oder während des Spulens nicht als normalen Sprung werten.
    public func suppressesMove(now: Double) -> Bool {
        now - lastPan < Self.moveSuppression
    }

    /// Lange keine Eingabe: abbrechen.
    public func idleExpired(now: Double) -> Bool {
        isActive && now - lastInput >= Self.idleTimeout
    }

    /// Select: Ziel übernehmen (nil = es lief kein Spulen oder das Ziel ist die Ausgangsstelle).
    public mutating func confirm() -> Double? {
        guard isActive else { return nil }
        let t = target, moved = abs(target - origin) >= 0.5
        reset()
        return moved ? t : nil
    }

    /// Menü: verwerfen. true = es lief ein Spulen (Taste verbraucht).
    @discardableResult
    public mutating func cancel() -> Bool {
        let was = isActive
        reset()
        return was
    }

    private mutating func begin(position: Double, duration: Double, now: Double) {
        isActive = true
        self.duration = duration
        origin = Self.clamp(position, duration: duration)
        target = origin
        lastInput = now
    }

    private mutating func move(by seconds: Double, now: Double, snaps: Bool = true) -> Bool {
        guard isActive, seconds.isFinite else { return false }
        lastInput = now
        var t = Self.clamp(target + seconds, duration: duration)
        if snaps { t = Self.clamp(Self.snap(t, edges: snapEdges), duration: duration) }
        guard t != target else { return false }
        target = t
        return true
    }

    private mutating func reset() {
        isActive = false; pendingPoints = 0
        dwellSince = nil; lastAngle = nil; wheelOn = false
    }

    /// Winkeldifferenz in −π…π.
    static func unwrap(_ d: Double) -> Double {
        var d = d
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }
}

/// Kleiner Zwischenspeicher für Spul-Vorschaubilder: Schlüssel = 2-s-Raster, höchstens `capacity` Bilder,
/// älteste zuerst raus. `generation` wechselt mit der Quelle (dann ist alles verworfen).
public struct ScrubPreviewCache<Value>: @unchecked Sendable {
    public static var gridSeconds: Double { 2 }
    public let capacity: Int
    public private(set) var generation: Int = 0
    private var values: [Int: Value] = [:]
    private var order: [Int] = []

    public init(capacity: Int = 48) { self.capacity = max(1, capacity) }

    /// Rasterfeld einer Zeit.
    public static func key(_ seconds: Double) -> Int {
        guard seconds.isFinite else { return 0 }
        return Int((max(0, seconds) / gridSeconds).rounded(.down))
    }

    public var count: Int { values.count }

    public mutating func value(at seconds: Double) -> Value? {
        let k = Self.key(seconds)
        guard let v = values[k] else { return nil }
        touch(k)
        return v
    }

    public mutating func store(_ v: Value, at seconds: Double) {
        let k = Self.key(seconds)
        values[k] = v
        touch(k)
        while order.count > capacity, let old = order.first {
            order.removeFirst(); values[old] = nil
        }
    }

    /// Quelle gewechselt (Neuladen, frischer Link): alles verwerfen.
    public mutating func reset() {
        values = [:]; order = []; generation &+= 1
    }

    private mutating func touch(_ k: Int) {
        if let i = order.firstIndex(of: k) { order.remove(at: i) }
        order.append(k)
    }
}
