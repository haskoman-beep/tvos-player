import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Abfrage an IntroDB: Film (`season`/`episode` nil) oder Folge.
public struct IntroDBQuery: Sendable, Equatable, Hashable {
    public var imdb: String
    public var season: Int?
    public var episode: Int?

    public init(imdb: String, season: Int? = nil, episode: Int? = nil) {
        self.imdb = imdb; self.season = season; self.episode = episode
    }

    public var isMovie: Bool { season == nil || episode == nil }
}

/// Sprungmarken von api.introdb.app (Gemeinschaftsdatenbank, ohne Schlüssel).
/// `GET /segments?imdb_id=tt…&season=1&episode=2` bzw. `?imdb_id=tt…&is_movie=true`.
/// Antwort: `intro`, `recap`, `outro`, `post_credits` je `{start_sec, end_sec}` oder null.
/// Fremder Dienst ohne Zusage: hart begrenzte Wartezeit, jeder Fehler → leere Liste.
public struct IntroDBClient: Sendable {
    public static let base = "https://api.introdb.app"
    public static let defaultTimeout: Duration = .seconds(4)

    let http: HTTPFetching
    let timeout: Duration

    public init(http: HTTPFetching = URLSessionFetcher(), timeout: Duration = IntroDBClient.defaultTimeout) {
        self.http = http; self.timeout = timeout
    }

    /// Adresse der Abfrage; nil ohne gültige IMDb-ID. Folgen-IDs „tt…:1:2“ werden auf die Serien-ID gekürzt.
    public static func url(_ q: IntroDBQuery) -> URL? {
        let id = q.imdb.split(separator: ":").first.map(String.init) ?? q.imdb
        guard id.hasPrefix("tt"), id.count > 2, id.dropFirst(2).allSatisfy(\.isNumber) else { return nil }
        var c = URLComponents(string: "\(base)/segments")
        var items = [URLQueryItem(name: "imdb_id", value: id)]
        if let s = q.season, let e = q.episode, s >= 0, e > 0 {
            items += [URLQueryItem(name: "season", value: "\(s)"), URLQueryItem(name: "episode", value: "\(e)")]
        } else {
            items.append(URLQueryItem(name: "is_movie", value: "true"))
        }
        c?.queryItems = items
        return c?.url
    }

    /// Bereiche aus der Antwort (ungültige/fehlende Marken fallen weg).
    public static func parse(_ data: Data) -> [SkipSegment] {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        let map: [(String, SkipSegment.Kind)] = [("intro", .intro), ("recap", .recap), ("outro", .credits),
                                                  ("post_credits", .postCredits)]
        var out: [SkipSegment] = []
        for (key, kind) in map {
            guard let m = obj[key] as? [String: Any] else { continue }
            let start = seconds(m["start_sec"]) ?? seconds(m["start_ms"]).map { $0 / 1000 }
            let end = seconds(m["end_sec"]) ?? seconds(m["end_ms"]).map { $0 / 1000 }
            guard let start, let end, start >= 0, end - start >= 1, end - start <= 1200 else { continue }
            out.append(SkipSegment(kind: kind, start: start, end: end, source: .introDB))
        }
        return out.sorted { $0.start < $1.start }
    }

    /// Zahl, Zahl als Text oder „mm:ss“ / „hh:mm:ss“ (auch mit Nachkommastellen) → Sekunden.
    static func seconds(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { let d = n.doubleValue; return d.isFinite ? d : nil }
        guard let s = (v as? String)?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if let d = Double(s) { return d.isFinite ? d : nil }
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return nil }
        var total = 0.0
        for (i, p) in parts.enumerated() {
            guard let d = Double(p), d >= 0, d.isFinite else { return nil }
            if i > 0, d >= 60 { return nil }
            total = total * 60 + d
        }
        return total
    }

    /// Bereiche für Film/Folge; leer bei Fehler, Zeitüberschreitung oder ohne Treffer.
    public func segments(_ q: IntroDBQuery, log: @Sendable (String) -> Void = { _ in }) async -> [SkipSegment] {
        guard let u = Self.url(q) else { log("keine IMDb-ID"); return [] }
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
        log(list.isEmpty ? "keine Marken" : list.map { "\($0.kind.rawValue) \(Int($0.start))–\(Int($0.end))s" }.joined(separator: ", "))
        return list
    }
}
