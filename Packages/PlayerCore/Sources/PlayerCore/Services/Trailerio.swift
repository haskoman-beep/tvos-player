import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Ein Trailer von trailerio.cc: direkte Videodatei (HLS-Playlist oder MP4), kein YouTube-Umweg.
public struct TrailerioTrailer: Sendable, Equatable {
    public var url: URL
    /// Anbieter-Text wie „⭐ Apple TV 4K DV Atmos“, „Plex 1080p“ (ohne Stern).
    public var provider: String
    /// Vom Dienst mit ⭐ markierte Empfehlung.
    public var isRecommended: Bool
    public var isHLS: Bool
    /// Höhe aus dem Anbieter-Text (4K → 2160, „1080p“ → 1080), sonst nil.
    public var height: Int?

    /// Für den bestehenden Trailer-Weg (Player bekommt dieselbe Struktur wie bei YouTube).
    public var stream: YouTubeStream {
        YouTubeStream(url: url, isHLS: isHLS, height: height, client: "trailerio", headers: [:])
    }
}

/// Trailer-Quelle trailerio.cc (Stremio-Addon mit nur `meta` für `tt…`).
/// `GET <basis>/<sprache>/meta/<movie|series>/<tt…>.json` → `meta.links[]` mit `{trailers: URL, provider: Text}`.
/// Englisch liegt ohne Sprachpfad an der Wurzel. Fremder Dienst ohne Zusage: hart begrenzte Wartezeit, Fehler → leere Liste
/// (Aufrufer fällt auf YouTube zurück).
public struct TrailerioClient: Sendable {
    public static let base = "https://trailerio.cc"
    /// Sprachen mit eigenem Pfad (am 21.11.2026 geprüft: diese liefern ein Manifest, andere 404).
    public static let languages: Set<String> = ["de", "fr", "es", "it", "pt", "ja", "ko", "ru", "tr", "hi", "ar", "cs"]
    /// Wartezeit, nach der ohne Ergebnis auf YouTube zurückgefallen wird.
    public static let defaultTimeout: Duration = .milliseconds(2500)

    let http: HTTPFetching
    let timeout: Duration

    public init(http: HTTPFetching = URLSessionFetcher(), timeout: Duration = TrailerioClient.defaultTimeout) {
        self.http = http; self.timeout = timeout
    }

    /// Adresse der Meta-Antwort; `language` darf auch „de-DE“ sein. Unbekannte Sprache/Englisch → Wurzel (englische Trailer).
    public static func metaURL(imdb: String, series: Bool, language: String) -> URL? {
        let id = imdb.split(separator: ":").first.map(String.init) ?? imdb
        guard id.hasPrefix("tt"), id.count > 2, id.dropFirst(2).allSatisfy(\.isNumber) else { return nil }
        let lang = String(language.lowercased().prefix(2))
        let path = languages.contains(lang) ? "/\(lang)" : ""
        return URL(string: "\(base)\(path)/meta/\(series ? "series" : "movie")/\(id).json")
    }

    /// Links in Abspiel-Reihenfolge: ⭐-Empfehlung zuerst, sonst Reihenfolge des Dienstes. Nur http(s)-Adressen.
    public static func parse(_ data: Data) -> [TrailerioTrailer] {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let meta = obj["meta"] as? [String: Any],
              let links = meta["links"] as? [[String: Any]] else { return [] }
        var out: [TrailerioTrailer] = []
        for l in links {
            guard let s = (l["trailers"] as? String)?.trimmingCharacters(in: .whitespaces),
                  let u = URL(string: s), let scheme = u.scheme?.lowercased(), scheme == "https" || scheme == "http",
                  u.host != nil else { continue }
            let raw = (l["provider"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let star = raw.hasPrefix("⭐")
            let provider = star ? String(raw.dropFirst()).trimmingCharacters(in: .whitespaces) : raw
            let isHLS = u.path.lowercased().hasSuffix(".m3u8")
            if out.contains(where: { $0.url == u }) { continue }
            out.append(TrailerioTrailer(url: u, provider: provider, isRecommended: star, isHLS: isHLS, height: height(provider)))
        }
        // Stabil: Empfehlung nach vorn, Rest in Dienst-Reihenfolge.
        return out.filter(\.isRecommended) + out.filter { !$0.isRecommended }
    }

    static func height(_ provider: String) -> Int? {
        let up = provider.uppercased()
        if up.contains("4K") || up.contains("2160") { return 2160 }
        for token in up.split(whereSeparator: { !$0.isNumber && $0 != "P" }) where token.hasSuffix("P") {
            if let h = Int(token.dropLast()), h >= 144 { return h }
        }
        return nil
    }

    /// Trailer für die Profilsprache; leer bei Fehler, Zeitüberschreitung oder ohne Treffer.
    /// Bei einer Sprache mit eigenem Pfad ohne Treffer wird nicht auf Englisch ausgewichen (das übernimmt YouTube).
    public func trailers(imdb: String, series: Bool, language: String,
                         log: @Sendable (String) -> Void = { _ in }) async -> [TrailerioTrailer] {
        guard let u = Self.metaURL(imdb: imdb, series: series, language: language) else { log("keine IMDb-ID"); return [] }
        let http = self.http, timeout = self.timeout
        let data: Data? = await withTaskGroup(of: Data?.self) { g in
            g.addTask { try? await http.data(from: u) }
            g.addTask { try? await Task.sleep(for: timeout); return nil }
            let first = await g.next() ?? nil
            g.cancelAll()
            return first
        }
        guard let data else { log(Task.isCancelled ? "abgebrochen" : "keine Antwort (Fehler oder Zeitüberschreitung)"); return [] }
        let list = Self.parse(data)
        log("\(list.count) Trailer" + (list.first.map { " · erster: \($0.provider)" } ?? ""))
        return list
    }
}
