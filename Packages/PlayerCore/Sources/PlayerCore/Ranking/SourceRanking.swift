import Foundation

/// Eingaben für die Sortierung der Quellenliste (aus Profil und Gerät).
public struct SourceRankContext: Equatable, Sendable {
    /// Erste Sprache aus dem Tonspur-Vorrang ("de"); nil = keine Sprach-Gewichtung (Vorrang beginnt mit "orig").
    public var primaryLanguage: String?
    /// VideoToolbox dekodiert AV1 in Hardware.
    public var av1Hardware: Bool

    public init(primaryLanguage: String?, av1Hardware: Bool) {
        self.primaryLanguage = primaryLanguage.flatMap { MediaLabels.languageCode($0) ?? $0 }
        self.av1Hardware = av1Hardware
    }

    /// Erste Sprache des Tonspur-Vorrangs; beginnt er mit "orig", wird nicht nach Sprache gewichtet.
    public init(audioPriority: [String], av1Hardware: Bool) {
        let first = audioPriority.first.map { $0.lowercased() }
        self.init(primaryLanguage: first == "orig" ? nil : first, av1Hardware: av1Hardware)
    }
}

/// Sortierung der Quellenliste für die erste automatische Wahl, den Rückfall und die nächste Folge.
/// Die Reihenfolge des Addons bleibt die Grundlage; verschoben wird nur nach diesen Stufen (stabil):
/// 1. sicher nicht gecachte Quellen ("lädt erst") nach hinten,
/// 2. Sprache: Wunschsprache genannt > Multi/Dual > keine Sprache oder nur Zweitsprachen > nur fremde Sprachen
///    (Englisch als Wunschsprache: Quellen ohne Angabe zählen wie Englisch, englische Releases nennen sie selten),
/// 3. 4K-AV1 ohne Hardware-Dekoder nach hinten (Software-Dekodierung ruckelt),
/// 4. innerhalb eines Blocks gleicher Auflösung: AV1 bei Dolby Vision bzw. ohne Hardware hinter die anderen,
///    TorBox vor anderen Diensten, wenn die Liste mehr als einen Dienst enthält.
public enum SourceRanking {
    /// Sprachklasse einer Quelle, höher = besser.
    public enum LanguageClass: Int, Comparable, Sendable {
        case otherOnly = 0, unknown = 1, multi = 2, wanted = 3
        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    public static func languageClass(_ t: StreamTraits, primary: String?) -> LanguageClass {
        guard let primary else { return .unknown }
        let named = Set(t.languages).subtracting(["multi"])
        if named.contains(primary) { return .wanted }
        if t.languages.contains("multi") { return .multi }
        if named.isEmpty { return primary == "en" ? .wanted : .unknown }
        // Nur andere Sprachen genannt. Englisch neben einer deutschen Wahl ist meist auch die Originalspur:
        // bleibt „unbekannt“, nicht abgewertet, solange nur Englisch genannt ist.
        if primary != "en", named == ["en"] { return .unknown }
        return .otherOnly
    }

    /// AV1 in 4K ohne Hardware-Dekoder: stark abwerten (hinter alle gleichsprachigen Quellen).
    public static func isHeavyAV1(_ t: StreamTraits, av1Hardware: Bool) -> Bool {
        t.videoCodec == "AV1" && !av1Hardware && t.resolution == "2160p"
    }

    /// AV1 innerhalb gleicher Auflösung hinten: ohne Hardware oder bei Dolby Vision (der Fernseher braucht HEVC-DV).
    public static func isWeakAV1(_ t: StreamTraits, av1Hardware: Bool) -> Bool {
        t.videoCodec == "AV1" && (!av1Hardware || t.hdr.contains("DV"))
    }

    /// Sortiert beliebige Einträge nach den Stufen oben; `traits` liefert die Merkmale eines Eintrags.
    public static func order<T>(_ items: [T], context: SourceRankContext, traits: (T) -> StreamTraits) -> [T] {
        let t = items.map(traits)
        let multiService = Set(t.compactMap(\.service)).count > 1
        // Stufen 1–3: stabile Sortierung nach Schlüssel.
        let primary = items.indices.sorted { a, b in
            let ka = key(t[a], context), kb = key(t[b], context)
            return ka != kb ? ka.lexicographicallyPrecedes(kb) : a < b
        }
        // Stufe 4: aufeinanderfolgende Blöcke gleicher Grundstufe und gleicher Auflösung.
        var out: [Int] = []
        var run: [Int] = []
        func flush() {
            out += run.enumerated().sorted { x, y in
                let kx = runKey(t[x.element], context, multiService), ky = runKey(t[y.element], context, multiService)
                return kx != ky ? kx.lexicographicallyPrecedes(ky) : x.offset < y.offset
            }.map(\.element)
            run = []
        }
        for i in primary {
            if let last = run.last, key(t[last], context) != key(t[i], context) || t[last].resolution != t[i].resolution { flush() }
            run.append(i)
        }
        flush()
        return out.map { items[$0] }
    }

    public static func order(_ streams: [StreamItem], context: SourceRankContext) -> [StreamItem] {
        order(streams, context: context, traits: StreamTraits.parse)
    }

    public static func order(_ entries: [(addon: String, stream: StreamItem)], context: SourceRankContext) -> [(addon: String, stream: StreamItem)] {
        order(entries, context: context) { StreamTraits.parse($0.stream) }
    }

    /// Kleiner = weiter vorn.
    private static func key(_ t: StreamTraits, _ c: SourceRankContext) -> [Int] {
        [t.cached == false ? 1 : 0,
         LanguageClass.wanted.rawValue - languageClass(t, primary: c.primaryLanguage).rawValue,
         isHeavyAV1(t, av1Hardware: c.av1Hardware) ? 1 : 0]
    }

    private static func runKey(_ t: StreamTraits, _ c: SourceRankContext, _ multiService: Bool) -> [Int] {
        [isWeakAV1(t, av1Hardware: c.av1Hardware) ? 1 : 0,
         multiService && t.service != "TB" ? 1 : 0]
    }
}
