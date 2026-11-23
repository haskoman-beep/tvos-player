import Foundation

/// Umwandlung von `Double` in Ganzzahlen ohne Laufzeitfehler: Fremddaten (Addon-Text, Netzantworten) können NaN,
/// unendlich oder riesige Werte liefern, bei denen `Int64(_:)` / `Int(_:)` das Programm abbrechen.
/// Im gültigen Bereich verhalten sich beide wie die Standard-Initialisierer (Nachkommastellen werden abgeschnitten).
public enum SafeNumber {
    /// nil bei NaN, unendlich oder außerhalb von `Int64`.
    public static func int64(_ d: Double) -> Int64? {
        // 2^63 ist als Double exakt; alles darunter (bis −2^63 einschließlich) passt nach dem Abschneiden in Int64.
        guard d.isFinite, d >= -9_223_372_036_854_775_808.0, d < 9_223_372_036_854_775_808.0 else { return nil }
        return Int64(d)
    }

    /// nil bei NaN, unendlich oder außerhalb von `Int`.
    public static func int(_ d: Double) -> Int? {
        guard d.isFinite, d >= Double(Int.min), d < -Double(Int.min) else { return nil }
        return Int(d)
    }
}
