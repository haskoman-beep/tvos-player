import Foundation

/// Einstellung „Plattencache“: der laufende Film wird blockweise unter Caches/ zwischengespeichert
/// (lokaler Proxy in der App). Standard AUS; aus = Wiedergabe genau wie ohne Cache.
public struct DiskCacheSettings: Codable, Sendable, Hashable {
    public var enabled: Bool
    /// Obergrenze in GB; der freie Platz begrenzt zusätzlich (siehe `DiskCacheBudget`).
    public var limitGB: Int

    public static let sizeChoices = [4, 8, 16, 32]

    public init(enabled: Bool = false, limitGB: Int = 8) {
        self.enabled = enabled; self.limitGB = limitGB
    }

    /// Nächste angebotene Größe (bei Gleichstand die kleinere): fremde Werte aus alten/bearbeiteten Profilen.
    public static func nearestChoice(_ gb: Int) -> Int {
        sizeChoices.min { abs($0 - gb) < abs($1 - gb) } ?? 8
    }

    public var limitBytes: Int64 { Int64(Self.nearestChoice(limitGB)) * 1_000_000_000 }

    enum CodingKeys: String, CodingKey { case enabled, limitGB }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DiskCacheSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        limitGB = Self.nearestChoice(try c.decodeIfPresent(Int.self, forKey: .limitGB) ?? d.limitGB)
    }
}
