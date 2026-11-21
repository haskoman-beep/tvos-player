import Foundation

/// Hält eine gerade sichtbare Untertitelzeile bis zu ihrem Ende stehen, wenn die Engine ein neues
/// Cue-Fenster veröffentlicht, in dem sie (kurz) fehlt. Sonst flackert die Zeile beim Umbau des Fensters.
/// Beim Spurwechsel leert der Aufrufer den Halt (`carry = []`).
public enum SubtitleCueHold {
    /// Neue Halteliste beim Wechsel des Fensters: sichtbare Cues, die zur Zeit `t` noch laufen und im
    /// neuen Fenster fehlen, plus ältere gehaltene, die noch laufen.
    public static func carry<C>(visible: [C], newWindow: [C], at t: Double,
                                id: (C) -> Int, start: (C) -> Double, end: (C) -> Double) -> [C] {
        var seen = Set(newWindow.map(id))
        return visible.filter {
            SubtitleGeometry.isActive(start: start($0), end: end($0), at: t) && seen.insert(id($0)).inserted
        }
    }

    /// Aktive Cues zur Zeit `t`: aus dem Fenster und aus dem Halt (ohne Doppelte), nach Start und ID sortiert.
    /// Gibt den bereinigten Halt mit zurück (abgelaufene fallen heraus).
    public static func active<C>(window: [C], carry: [C], at t: Double,
                                 id: (C) -> Int, start: (C) -> Double, end: (C) -> Double) -> (active: [C], carry: [C]) {
        let live = window.filter { SubtitleGeometry.isActive(start: start($0), end: end($0), at: t) }
        let ids = Set(live.map(id))
        let kept = carry.filter { SubtitleGeometry.isActive(start: start($0), end: end($0), at: t) }
        let all = (live + kept.filter { !ids.contains(id($0)) })
            .sorted { (start($0), id($0)) < (start($1), id($1)) }
        return (all, kept)
    }
}

/// Text-Untertitel bereinigen: ASS-Reste, die bis zur Anzeige durchrutschen.
public enum SubtitleText {
    /// Entfernt `{\…}`-Override-Blöcke, macht aus `\N`/`\n` Zeilenumbrüche und aus `\h` ein festes Leerzeichen,
    /// vereinheitlicht CRLF und schneidet (bei `trim`) Leerraum an den Rändern ab. Für einzelne Läufe
    /// eines RichText-Cues `trim: false`, sonst gehen Leerzeichen zwischen den Läufen verloren.
    public static func clean(_ raw: String, trim: Bool = true) -> String {
        var s = raw.replacingOccurrences(of: "\\{\\\\[^}]*\\}", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\N", with: "\n").replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\h", with: "\u{00A0}").replacingOccurrences(of: "\r\n", with: "\n")
        return trim ? s.trimmingCharacters(in: .whitespacesAndNewlines) : s
    }
}
