import Foundation

/// Grenze des Bild-Speichercaches (ImagePipeline) nach freiem Prozess-Speicher.
/// tvOS beendet Apps über ihrem Speicherbudget; `os_proc_available_memory()` sagt, wie viel bis dahin bleibt.
/// Der Cache darf einen Bruchteil davon belegen, gedeckelt auf `maximum`; während der Wiedergabe
/// (Engine-Puffer, Dekoder) höchstens `playbackMaximum`.
public enum ImageCacheBudget {
    public static let mb = 1 << 20
    /// Obergrenze wie bisher fest eingestellt.
    public static let maximum = 160 << 20
    /// Untergrenze: eine Reihe Poster bleibt immer im Speicher.
    public static let minimum = 16 << 20
    /// Während der Wiedergabe.
    public static let playbackMaximum = 24 << 20
    /// Anteil des freien Speichers, den der Cache nutzen darf.
    public static let share = 0.25

    /// - Parameters:
    ///   - availableBytes: `os_proc_available_memory()`; 0 = unbekannt (kein Budget gemeldet).
    ///   - cachedBytes: aktuell im Cache belegte Bytes (zählen zum Prozessverbrauch, gehören aber dem Cache).
    ///   - playback: Wiedergabe läuft.
    public static func limit(availableBytes: UInt64, cachedBytes: Int = 0, playback: Bool) -> Int {
        let top = playback ? playbackMaximum : maximum
        guard availableBytes > 0 else { return top }
        let headroom = Double(availableBytes) + Double(max(0, cachedBytes))
        let wanted = Int(min(headroom * share, Double(Int.max / 2)))
        return min(top, max(minimum, wanted))
    }

    /// Lohnt ein Neusetzen der Grenze (und eine Logzeile)? Kleine Schwankungen ignorieren.
    public static func changedEnough(old: Int, new: Int) -> Bool {
        abs(old - new) >= 8 * mb || (new < old && new <= minimum)
    }
}
