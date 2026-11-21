import Foundation

/// Spur-Wahl je Serie bzw. Film (Welle D-a): Tonsprache, Untertitel (Sprache oder Aus) und Untertitel-Versatz.
/// Gemerkt wird nur, was der Nutzer selbst im Spur-Panel wählt; jedes Feld einzeln (nil = nichts gemerkt).
/// Wiedergabe-Tempo gibt es im Player nicht, deshalb wird es nicht gemerkt.
public struct TrackMemory: Codable, Sendable, Equatable {
    /// Normalisierter Sprachcode der Tonspur ("de", "en", …).
    public var audioLanguage: String?
    /// Untertitel: nil = nichts gemerkt.
    public var subtitle: SubtitleChoice?
    /// Untertitel-Versatz in Sekunden; nil = nichts gemerkt.
    public var subtitleOffset: Double?
    public var updated: Date

    public enum SubtitleChoice: Codable, Sendable, Equatable {
        case off
        /// Sprache (normalisiert), dazu, ob es eine erzwungene bzw. SDH-Spur war.
        case language(String, forced: Bool, hearingImpaired: Bool)
    }

    public init(audioLanguage: String? = nil, subtitle: SubtitleChoice? = nil, subtitleOffset: Double? = nil,
                updated: Date = Date()) {
        self.audioLanguage = audioLanguage; self.subtitle = subtitle; self.subtitleOffset = subtitleOffset
        self.updated = updated
    }

    enum CodingKeys: String, CodingKey { case audioLanguage, subtitle, subtitleOffset, updated }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        audioLanguage = (try? c.decodeIfPresent(String.self, forKey: .audioLanguage)) ?? nil
        subtitle = (try? c.decodeIfPresent(SubtitleChoice.self, forKey: .subtitle)) ?? nil
        subtitleOffset = (try? c.decodeIfPresent(Double.self, forKey: .subtitleOffset)) ?? nil
        updated = (try? c.decodeIfPresent(Date.self, forKey: .updated)) ?? nil ?? .distantPast
    }

    public var isEmpty: Bool { audioLanguage == nil && subtitle == nil && subtitleOffset == nil }

    public var logText: String {
        let sub: String
        switch subtitle {
        case nil: sub = "-"
        case .off: sub = "aus"
        case .language(let l, let f, let h): sub = l + (f ? " erzwungen" : "") + (h ? " SDH" : "")
        }
        return "Ton \(audioLanguage ?? "-") · UT \(sub) · Versatz \(subtitleOffset.map { SubtitleOffset.label($0) } ?? "-")"
    }
}

/// Alle gemerkten Wahlen eines Profils; höchstens `limit` Titel (die ältesten fallen heraus).
public struct TrackMemoryBook: Codable, Sendable, Equatable {
    public static let limit = 300
    public var entries: [String: TrackMemory]

    public init(entries: [String: TrackMemory] = [:]) { self.entries = entries }

    /// Schlüssel: ID der Serie bzw. des Films (`MetaPreview.id`, z. B. "tt0903747", "tmdb:1396").
    /// Bei Folgen-IDs ("tt0903747:1:2", "tmdb:1396:1:2") nur der Serienteil; andere IDs ("torbox:…") bleiben ganz.
    public static func key(itemID: String) -> String {
        let parts = itemID.split(separator: ":", omittingEmptySubsequences: false)
        if itemID.hasPrefix("tt"), let first = parts.first { return String(first) }
        if parts.count == 4, seriesPrefixes.contains(String(parts[0])) { return parts.prefix(2).joined(separator: ":") }
        return itemID
    }

    static let seriesPrefixes: Set<String> = ["tmdb", "tvdb", "kitsu", "mal", "anilist"]

    public func memory(for key: String) -> TrackMemory? {
        guard let m = entries[key], !m.isEmpty else { return nil }
        return m
    }

    /// Ändert den Eintrag (legt ihn an) und kürzt die Liste.
    public mutating func update(_ key: String, now: Date = Date(), _ change: (inout TrackMemory) -> Void) {
        var m = entries[key] ?? TrackMemory(updated: now)
        change(&m)
        m.updated = now
        entries[key] = m
        prune()
    }

    mutating func prune() {
        guard entries.count > Self.limit else { return }
        let drop = entries.sorted { $0.value.updated < $1.value.updated }.prefix(entries.count - Self.limit)
        for (k, _) in drop { entries[k] = nil }
    }
}

/// Was die gemerkte Wahl beim Start bewirkt. Nur vorhandene Spuren; sonst gilt die Automatik.
public enum TrackMemoryPlan {
    /// Tonspur in der gemerkten Sprache (beste nach den üblichen Regeln, nie Kommentar); nil = Automatik.
    public static func audio(_ m: TrackMemory?, tracks: [AudioTrackInfo]) -> AudioTrackInfo? {
        guard let lang = m?.audioLanguage else { return nil }
        let matching = tracks.filter { MediaLabels.languageCode($0.language) == lang && !$0.isCommentary }
        guard !matching.isEmpty else { return nil }
        return preferredAudioTrack(matching, priority: [lang])
    }

    public enum SubtitleDecision: Equatable, Sendable {
        /// Nichts gemerkt oder Spur fehlt: Automatik (SubtitlePicker) entscheidet.
        case automatic
        case off
        case track(Int)
    }

    /// Untertitel nach der gemerkten Wahl: gleiche Sprache, möglichst gleiche Art (erzwungen, SDH), nie Kommentar,
    /// Textspur vor Bildspur, eingebettet vor Addon.
    public static func subtitle(_ m: TrackMemory?, tracks: [AudioTrackInfo]) -> SubtitleDecision {
        guard let choice = m?.subtitle else { return .automatic }
        switch choice {
        case .off:
            return .off
        case .language(let lang, let forced, let sdh):
            let matching = tracks.filter { MediaLabels.languageCode($0.language) == lang && !$0.isCommentary }
            guard !matching.isEmpty else { return .automatic }
            func score(_ t: AudioTrackInfo) -> Int {
                (t.isForced == forced ? 8 : 0) + (t.isHearingImpaired == sdh ? 4 : 0) + (t.isImage ? 0 : 2) + (t.isExternal ? 0 : 1)
            }
            // Bei gleicher Wertung die erste Spur (stabile Wahl).
            var best = matching[0]
            for t in matching.dropFirst() where score(t) > score(best) { best = t }
            return .track(best.id)
        }
    }

    /// Gemerkte Untertitel-Wahl aus einer Spur (nil = Aus).
    public static func choice(for track: AudioTrackInfo?) -> TrackMemory.SubtitleChoice? {
        guard let track else { return .off }
        guard let lang = MediaLabels.languageCode(track.language) else { return nil }   // ohne Sprache nichts merken
        return .language(lang, forced: track.isForced, hearingImpaired: track.isHearingImpaired)
    }
}
