import Foundation

/// Einstellungen rund um Quellen und Extras (Welle C-d). Alle Felder mit Standardwert, alte Profile laden.
public struct SourceSettings: Codable, Sendable, Equatable {
    /// Quellenliste nach Sprache, Cache-Status, AV1-Dekoder und TorBox-Vorrang ordnen (Standard an).
    public var smartOrder: Bool
    /// Standbilder ungesehener Folgen weichzeichnen (Spoilerschutz, Standard aus).
    public var blurUnwatchedStills: Bool
    /// Adresse eines Bewertungs-Icon-Satzes (JSON `[{name, url}]`); nil = eingebaute Plaketten.
    public var ratingIconSetURL: String?
    /// Kalender: Sendetag und -zeit aus TVmaze statt nur dem TMDB-Datum (Standard an).
    public var tvmazeAirtimes: Bool

    public init(smartOrder: Bool = true, blurUnwatchedStills: Bool = false, ratingIconSetURL: String? = nil, tvmazeAirtimes: Bool = true) {
        self.smartOrder = smartOrder; self.blurUnwatchedStills = blurUnwatchedStills; self.ratingIconSetURL = ratingIconSetURL
        self.tvmazeAirtimes = tvmazeAirtimes
    }

    enum CodingKeys: String, CodingKey { case smartOrder, blurUnwatchedStills, ratingIconSetURL, tvmazeAirtimes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SourceSettings()
        smartOrder = (try? c.decodeIfPresent(Bool.self, forKey: .smartOrder)) ?? nil ?? d.smartOrder
        blurUnwatchedStills = (try? c.decodeIfPresent(Bool.self, forKey: .blurUnwatchedStills)) ?? nil ?? d.blurUnwatchedStills
        ratingIconSetURL = (try? c.decodeIfPresent(String.self, forKey: .ratingIconSetURL)) ?? nil
        tvmazeAirtimes = (try? c.decodeIfPresent(Bool.self, forKey: .tvmazeAirtimes)) ?? nil ?? d.tvmazeAirtimes
    }
}
