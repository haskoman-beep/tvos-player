import Foundation

/// Manueller Untertitel-Versatz (Welle D-a). Positiv = Untertitel später, negativ = früher.
/// Die Engine verschiebt ihre Cue-Vorräte passend (`setSoftwareSubtitleDelay`), das Overlay zeichnet
/// gegen `Quellzeit - Versatz`. Gilt für eingebettete und Addon-Untertitel im eigenen Overlay.
public enum SubtitleOffset {
    /// Schritte im Spur-Panel (Sekunden), in Anzeigereihenfolge.
    public static let steps: [Double] = [-0.5, -0.1, 0.1, 0.5]
    /// Größter Betrag. Weiter verschobene Untertitel passen sicher nicht mehr zur Datei.
    public static let limit: Double = 30

    /// Auf 0,1 s gerundet und auf ±`limit` begrenzt; nicht endliche Werte → 0.
    public static func normalized(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        let clamped = min(max(seconds, -limit), limit)
        let rounded = (clamped * 10).rounded() / 10
        return rounded == 0 ? 0 : rounded   // kein „-0,0“
    }

    /// Neuer Versatz nach einem Schritt.
    public static func adjusted(_ current: Double, by step: Double) -> Double {
        normalized(normalized(current) + step)
    }

    /// „+0,3 s“, „−1,5 s“, „0,0 s“ (deutsches Komma, echtes Minuszeichen).
    public static func label(_ seconds: Double) -> String {
        let v = normalized(seconds)
        let body = String(format: "%.1f", abs(v)).replacingOccurrences(of: ".", with: ",")
        if v > 0 { return "+\(body) s" }
        if v < 0 { return "\u{2212}\(body) s" }
        return "\(body) s"
    }

    /// Beschriftung eines Schritt-Knopfs: „−0,5“, „+0,1“.
    public static func stepLabel(_ step: Double) -> String {
        let body = String(format: "%.1f", abs(step)).replacingOccurrences(of: ".", with: ",")
        return (step < 0 ? "\u{2212}" : "+") + body
    }

    /// Erklärung unter der Zeile.
    public static func hint(_ seconds: Double) -> String {
        let v = normalized(seconds)
        if v > 0 { return "Untertitel erscheinen \(label(v).dropFirst()) später" }
        if v < 0 { return "Untertitel erscheinen \(label(v).dropFirst()) früher" }
        return "Kein Versatz"
    }
}
