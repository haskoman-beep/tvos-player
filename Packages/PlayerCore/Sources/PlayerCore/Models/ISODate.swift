import Foundation

/// Ein gemeinsamer Datumsleser für ISO-8601-Texte aus APIs (Trakt, TMDB, Stremio, GitHub, TVmaze), einmal angelegt
/// statt je Aufruf neue Formatierer. ISO8601DateFormatter ist laut Apple threadsicher.
public enum ISODate {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    nonisolated(unsafe) private static let internet: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    nonisolated(unsafe) private static let fullDate: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; return f
    }()

    /// Zeitpunkt mit Uhrzeit (mit oder ohne Sekundenbruchteile); nil sonst.
    public static func dateTime(_ s: String) -> Date? { fractional.date(from: s) ?? internet.date(from: s) }

    /// Zeitpunkt mit Uhrzeit, sonst reines Datum "JJJJ-MM-TT" (Mitternacht UTC, auch mit angehängter Uhrzeit).
    public static func parse(_ s: String) -> Date? { dateTime(s) ?? fullDate.date(from: String(s.prefix(10))) }

    /// "2024-03-05" → "05.03.2024"; anderes bleibt unverändert.
    public static func germanDay(_ s: String) -> String {
        let p = s.prefix(10).split(separator: "-")
        guard p.count == 3, p[0].count == 4, p.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return s }
        return "\(p[2]).\(p[1]).\(p[0])"
    }
}
