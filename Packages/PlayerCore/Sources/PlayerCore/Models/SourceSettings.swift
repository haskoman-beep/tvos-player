import Foundation

/// Einstellungen rund um Quellen und Extras (Welle C-d). Alle Felder mit Standardwert, alte Profile laden.
public struct SourceSettings: Codable, Sendable, Equatable {
    /// Welle E-b: Anzeige der Quellenliste „Wie Addon“ (Standard) oder „Smart (App)“ (Ordnung aus Welle C-d).
    /// Das frühere Feld `smartOrder` wird bewusst nicht übernommen: der Standard wechselt auf Wunsch des Nutzers.
    public var order: StreamOrderMode
    /// Welle E-b: eigene Plaketten in der Quellenliste (Standard kompakt: nur „sofort“ und Größe).
    public var appBadges: StreamListBadgeMode
    /// Standbilder ungesehener Folgen weichzeichnen (Spoilerschutz, Standard aus).
    public var blurUnwatchedStills: Bool
    /// Adresse eines Bewertungs-Icon-Satzes (JSON `[{name, url}]`); nil = eingebaute Plaketten.
    public var ratingIconSetURL: String?
    /// Kalender: Sendetag und -zeit aus TVmaze statt nur dem TMDB-Datum (Standard an).
    public var tvmazeAirtimes: Bool

    public init(order: StreamOrderMode = .addon, appBadges: StreamListBadgeMode = .compact, blurUnwatchedStills: Bool = false,
                ratingIconSetURL: String? = nil, tvmazeAirtimes: Bool = true) {
        self.order = order; self.appBadges = appBadges
        self.blurUnwatchedStills = blurUnwatchedStills; self.ratingIconSetURL = ratingIconSetURL
        self.tvmazeAirtimes = tvmazeAirtimes
    }

    enum CodingKeys: String, CodingKey { case order, appBadges, blurUnwatchedStills, ratingIconSetURL, tvmazeAirtimes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SourceSettings()
        order = (try? c.decodeIfPresent(StreamOrderMode.self, forKey: .order)) ?? nil ?? d.order
        appBadges = (try? c.decodeIfPresent(StreamListBadgeMode.self, forKey: .appBadges)) ?? nil ?? d.appBadges
        blurUnwatchedStills = (try? c.decodeIfPresent(Bool.self, forKey: .blurUnwatchedStills)) ?? nil ?? d.blurUnwatchedStills
        ratingIconSetURL = (try? c.decodeIfPresent(String.self, forKey: .ratingIconSetURL)) ?? nil
        tvmazeAirtimes = (try? c.decodeIfPresent(Bool.self, forKey: .tvmazeAirtimes)) ?? nil ?? d.tvmazeAirtimes
    }
}
