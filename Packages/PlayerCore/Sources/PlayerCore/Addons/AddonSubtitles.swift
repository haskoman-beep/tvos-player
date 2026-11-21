import Foundation

/// Ein Untertitel aus einem Stremio-Addon (Ressource `subtitles`, z. B. OpenSubtitles v3).
public struct AddonSubtitle: Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var url: String
    /// Sprachcode wie vom Addon geliefert ("ger", "eng", "pob").
    public var lang: String?
    public var addonName: String
    /// Dateiname, falls das Addon ihn nennt (`subtitleFileName`), für den Formathinweis.
    public var fileName: String?

    public init(id: String, url: String, lang: String?, addonName: String, fileName: String? = nil) {
        self.id = id; self.url = url; self.lang = lang; self.addonName = addonName; self.fileName = fileName
    }

    /// Normalisierter Code ("ger" → "de", "pob" → "pt-BR").
    public var languageCode: String? { MediaLabels.languageCode(lang) }

    /// Format für die Engine: Endung der URL, sonst des Dateinamens, sonst "srt"
    /// (OpenSubtitles-v3-Adressen haben keine Endung und liefern SRT).
    public var formatHint: String {
        let known: Set<String> = ["srt", "vtt", "ass", "ssa", "sup"]
        let urlExt = URL(string: url)?.pathExtension.lowercased() ?? ""
        if known.contains(urlExt) { return urlExt }
        let fileExt = (fileName.map { URL(fileURLWithPath: $0).pathExtension } ?? "").lowercased()
        if known.contains(fileExt) { return fileExt }
        return "srt"
    }
}

/// Antwort `{"subtitles":[…]}`; kaputte Einträge werden übersprungen.
struct SubtitlesResponse: Decodable {
    var subtitles: [Item]

    struct Item: Decodable {
        var id: String?
        var url: String
        var lang: String?
        var fileName: String?

        enum CodingKeys: String, CodingKey { case id, url, lang, subtitleFileName }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            url = try c.decode(String.self, forKey: .url)
            if let s = try? c.decode(String.self, forKey: .id) { id = s }
            else if let n = try? c.decode(Int.self, forKey: .id) { id = String(n) }
            else { id = nil }
            lang = try? c.decodeIfPresent(String.self, forKey: .lang)
            fileName = try? c.decodeIfPresent(String.self, forKey: .subtitleFileName)
        }
    }

    private struct Lenient: Decodable {
        var item: Item?
        init(from decoder: Decoder) throws { item = try? Item(from: decoder) }
    }

    enum CodingKeys: String, CodingKey { case subtitles }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subtitles = ((try? c.decode([Lenient].self, forKey: .subtitles)) ?? []).compactMap(\.item)
    }
}

private struct SubtitleTimeout: Error {}

extension AddonClient {
    /// Ob mindestens ein Addon die Ressource `subtitles` anbietet (egal für welchen Typ).
    public static func hasSubtitleAddon(_ addons: [InstalledAddon]) -> Bool {
        addons.contains { $0.manifest.resources.contains { $0.name == "subtitles" } }
    }

    /// `GET {base}/subtitles/{type}/{id}[/{extra}].json` eines Addons.
    public func subtitles(_ addon: InstalledAddon, type: String, id: String,
                          extra: [String: String] = [:]) async throws -> [AddonSubtitle] {
        let url = try resourceURL(addon, "subtitles", type: type, id: id, extra: extra)
        let resp = try JSONDecoder().decode(SubtitlesResponse.self, from: try await http.data(from: url))
        return resp.subtitles.compactMap { s in
            guard URL(string: s.url) != nil else { return nil }
            return AddonSubtitle(id: s.id ?? s.url, url: s.url, lang: s.lang, addonName: addon.manifest.name, fileName: s.fileName)
        }
    }

    /// Untertitel aller passenden Addons parallel, je Addon höchstens `timeout` Sekunden; Fehler werden übersprungen.
    /// Reihenfolge wie die Addons, gleiche URL nur einmal. `extra` z. B. `OpenSubtitlesHash.extras(...)`.
    public func subtitles(from addons: [InstalledAddon], type: String, id: String,
                          extra: [String: String] = [:], timeout: Double = 8) async -> [AddonSubtitle] {
        let lists = await withTaskGroup(of: (Int, [AddonSubtitle])?.self) { group in
            for (i, a) in addons.enumerated() where a.manifest.supports("subtitles", type: type, id: id) {
                group.addTask {
                    guard let s = try? await Self.withTimeout(timeout, { try await self.subtitles(a, type: type, id: id, extra: extra) })
                    else { return nil }
                    return (i, s)
                }
            }
            var out: [(Int, [AddonSubtitle])] = []
            for await r in group { if let r { out.append(r) } }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return AddonSubtitlePlan.dedupe(lists.flatMap { $0 })
    }

    /// Ergebnis von `op` oder Fehler nach `seconds` (die Arbeit wird dann abgebrochen).
    public static func withTimeout<T: Sendable>(_ seconds: Double, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                throw SubtitleTimeout()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw SubtitleTimeout() }
            return first
        }
    }
}

/// Auswahl der Addon-Untertitel für den Player (reine Logik, getestet).
public enum AddonSubtitlePlan {
    /// Gleiche URL nur einmal (erste gewinnt).
    public static func dedupe(_ subs: [AddonSubtitle]) -> [AddonSubtitle] {
        var seen = Set<String>()
        return subs.filter { seen.insert($0.url).inserted }
    }

    /// Gewünschte Sprachen, normalisiert und ohne Dubletten: UT-Sprache des Profils, Tonsprache, Englisch.
    public static func languages(subtitleLanguage: String?, audioLanguage: String?) -> [String] {
        var out: [String] = []
        for raw in [subtitleLanguage, audioLanguage, "en"] {
            if let c = MediaLabels.languageCode(raw), !out.contains(c) { out.append(c) }
        }
        return out
    }

    /// Höchstens `perLanguage` Spuren je Sprache, sortiert nach `languages`, innerhalb einer Sprache in Addon-Reihenfolge.
    public static func select(_ subs: [AddonSubtitle], languages: [String], perLanguage: Int = 3) -> [AddonSubtitle] {
        let unique = dedupe(subs)
        return languages.flatMap { lang in unique.filter { $0.languageCode == lang }.prefix(perLanguage) }
    }

    /// Addon-Name ohne angehängte Versionsnummer ("OpenSubtitles v3" → "OpenSubtitles").
    public static func displayAddonName(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count > 1, let last = parts.last, last.count > 1, last.first == "v" || last.first == "V",
           last.dropFirst().allSatisfy({ $0.isNumber || $0 == "." }) {
            return parts.dropLast().joined(separator: " ")
        }
        return name
    }

    /// Spurname: "Deutsch · OpenSubtitles", ab der zweiten Spur derselben Sprache mit Nummer ("… 2").
    public static func trackName(_ sub: AddonSubtitle, number: Int) -> String {
        let base = "\(MediaLabels.languageName(sub.lang)) · \(displayAddonName(sub.addonName))"
        return number > 1 ? "\(base) \(number)" : base
    }

    /// Namen für die ausgewählten Spuren (Nummer zählt je Sprache und Addon).
    public static func trackNames(_ subs: [AddonSubtitle]) -> [String] {
        var counts: [String: Int] = [:]
        return subs.map { s in
            let key = "\(s.languageCode ?? "?")|\(s.addonName)"
            counts[key, default: 0] += 1
            return trackName(s, number: counts[key]!)
        }
    }

    /// Ob eine eingebettete, vollständige Spur (nicht erzwungen, kein Kommentar, nicht extern) in `language` existiert.
    /// Erzwungen/Kommentar wie bei `SubtitlePicker`, also auch nach Spurname ("Forced", "Commentary").
    public static func hasEmbeddedTrack(in language: String?, tracks: [AudioTrackInfo]) -> Bool {
        guard let want = MediaLabels.languageCode(language) else { return false }
        return tracks.contains {
            !$0.isExternal && !SubtitlePicker.isForced($0) && !SubtitlePicker.isCommentary($0)
                && MediaLabels.languageCode($0.language) == want
        }
    }

    /// Ob die automatische Wahl nach dem Hinzufügen von Addon-Spuren neu bewertet werden soll
    /// (`reconsiderSubtitles`, die Entscheidung trifft dann `SubtitlePicker`). Nicht bei „Aus“ und nicht,
    /// wenn eine volle eingebettete Spur in der Wunschsprache da ist: die bleibt vor jeder Addon-Spur.
    public static func shouldReconsider(mode: SubtitleMode, wishLanguage: String?, embedded: [AudioTrackInfo]) -> Bool {
        mode != .off && !hasEmbeddedTrack(in: wishLanguage, tracks: embedded)
    }
}

/// Vor einem Neuladen gemerkte externe (Addon-)UT-Spur. Die Spur-ID wird beim Neuanlegen neu vergeben,
/// darum zählt zuerst die Addon-URL, nur ohne URL-Treffer Name und Sprache.
public struct ExternalSubtitleRestore: Equatable, Sendable {
    /// Eine bekannte Spur: ID, Addon-URL (falls bekannt), Spurname, Sprache.
    public typealias Candidate = (id: Int, url: String?, name: String?, language: String?)

    public let url: String?
    public let name: String?
    public let language: String?
    public let byUser: Bool

    /// nil, wenn keine oder keine externe Spur aktiv war. `url` ist die Addon-URL der Spur, falls bekannt.
    public init?(track: AudioTrackInfo?, url: String?, byUser: Bool) {
        guard let track, track.isExternal else { return nil }
        self.url = url; name = track.name; language = track.language; self.byUser = byUser
    }

    /// ID der passenden Spur: erst gleiche URL, sonst gleicher Name und gleiche Sprache; nil ohne Treffer.
    public func match(_ candidates: [Candidate]) -> Int? {
        if let url, let hit = candidates.first(where: { $0.url == url }) { return hit.id }
        guard let name else { return nil }
        let want = MediaLabels.languageCode(language)
        return candidates.first { $0.name == name && MediaLabels.languageCode($0.language) == want }?.id
    }
}

/// OpenSubtitles-Datei-Hash: Dateigröße plus Summe der ersten und letzten 64 KiB als Little-Endian-UInt64
/// (Überlauf erlaubt), 16 Hex-Zeichen. Als Stremio-Extra `videoHash`/`videoSize` sortiert OpenSubtitles v3
/// die zur Veröffentlichung passenden Untertitel nach vorn.
public enum OpenSubtitlesHash {
    public static let chunkSize = 65_536

    /// nil bei falscher Blockgröße oder zu kleiner Datei.
    public static func compute(size: Int64, head: Data, tail: Data) -> String? {
        guard size >= Int64(chunkSize), head.count == chunkSize, tail.count == chunkSize else { return nil }
        var sum = UInt64(size)
        for block in [head, tail] {
            block.withUnsafeBytes { raw in
                for i in stride(from: 0, to: chunkSize, by: 8) {
                    sum &+= UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: i, as: UInt64.self))
                }
            }
        }
        let hex = String(sum, radix: 16)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }

    /// Gesamtgröße aus `Content-Range: bytes 0-65535/123456`; nil bei "*" oder Unsinn.
    public static func totalSize(contentRange: String?) -> Int64? {
        guard let s = contentRange?.trimmingCharacters(in: .whitespaces), s.lowercased().hasPrefix("bytes "),
              let slash = s.lastIndex(of: "/"), let n = Int64(s[s.index(after: slash)...]), n > 0 else { return nil }
        return n
    }

    /// Start aus `Content-Range: bytes 934464-999999/1000000`; nil bei Unsinn.
    public static func rangeStart(contentRange: String?) -> Int64? {
        guard let s = contentRange?.trimmingCharacters(in: .whitespaces), s.lowercased().hasPrefix("bytes "),
              let dash = s.firstIndex(of: "-") else { return nil }
        return Int64(s[s.index(s.startIndex, offsetBy: 6)..<dash].trimmingCharacters(in: .whitespaces))
    }

    /// Nur einzelne HTTP(S)-Dateien: kein HLS/DASH, kein Loopback, kein YouTube.
    public static func isHashable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else { return false }
        if ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host) { return false }
        if host.contains("youtube.") || host.contains("youtu.be") || host.contains("googlevideo.") { return false }
        return !["m3u8", "m3u", "mpd"].contains(url.pathExtension.lowercased())
    }

    /// Stremio-Extras für die Untertitel-Abfrage.
    public static func extras(hash: String, size: Int64) -> [String: String] {
        ["videoHash": hash, "videoSize": String(size)]
    }
}
