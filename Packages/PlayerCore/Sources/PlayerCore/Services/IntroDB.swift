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
/// Antwort: `intro`, `recap`, `outro`, `post_credits` (and `preview`, if the service ever sends it) je `{start_sec, end_sec}` oder null.
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

    /// Späteste angenommene Endmarke (ein Tag); größere Werte sind keine echten Marken (SEC-10).
    static let maxEndSeconds: Double = 86_400

    /// Bereiche aus der Antwort (ungültige/fehlende Marken fallen weg, ebenso Marken nach `maxEndSeconds`).
    public static func parse(_ data: Data) -> [SkipSegment] {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        let map: [(String, SkipSegment.Kind)] = [("intro", .intro), ("recap", .recap), ("outro", .credits),
                                                  ("post_credits", .postCredits), ("preview", .preview)]
        var out: [SkipSegment] = []
        for (key, kind) in map {
            guard let m = obj[key] as? [String: Any] else { continue }
            let start = seconds(m["start_sec"]) ?? seconds(m["start_ms"]).map { $0 / 1000 }
            let end = seconds(m["end_sec"]) ?? seconds(m["end_ms"]).map { $0 / 1000 }
            guard let start, let end, start >= 0, end - start >= 1, end - start <= 1200,
                  end <= maxEndSeconds else { continue }
            out.append(SkipSegment(kind: kind, start: start, end: end, source: .introDB))
        }
        return out.sorted { $0.start < $1.start }
    }

    /// Zahl, Zahl als Text oder „mm:ss“ / „hh:mm:ss“ (auch mit Nachkommastellen) → Sekunden.
    static func seconds(_ v: Any?) -> Double? {
        if let n = v as? NSNumber {
            // JSON true/false kommt als NSNumber an (Darwin) und wäre sonst 1/0 Sekunden.
            #if canImport(Darwin)
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            #else
            if String(cString: n.objCType) == "c" { return nil }   // corelibs: Bool-NSNumber hat Typ „c“
            #endif
            let d = n.doubleValue; return d.isFinite ? d : nil
        }
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

    /// Ganze Sekunden für die Logzeile; „?“ statt Laufzeitfehler, falls je ein Wert außerhalb von `Int` ankommt.
    static func logSeconds(_ d: Double) -> String {
        SafeNumber.int(d).map(String.init) ?? "?"
    }

    /// Bereiche für Film/Folge; leer bei Fehler, Zeitüberschreitung oder ohne Treffer.
    public func segments(_ q: IntroDBQuery, log: @Sendable (String) -> Void = { _ in }) async -> [SkipSegment] {
        await lookup(q, log: log) ?? []
    }

    /// Wie `segments`, unterscheidet aber: nil = keine verwertbare Antwort (Netz, Zeitüberschreitung, Serverfehler,
    /// kein JSON), leer = der Dienst kennt keine Marken (JSON ohne Bereiche oder HTTP 404).
    public func lookup(_ q: IntroDBQuery, log: @Sendable (String) -> Void = { _ in }) async -> [SkipSegment]? {
        guard let u = Self.url(q) else { log("keine IMDb-ID"); return nil }
        let http = self.http, timeout = self.timeout
        enum Outcome: Sendable { case data(Data), notFound, failed }
        let outcome: Outcome = await withTaskGroup(of: Outcome.self) { g in
            g.addTask {
                do { return .data(try await http.data(from: u)) } catch AddonError.http(404) { return .notFound } catch { return .failed }
            }
            g.addTask { try? await Task.sleep(for: timeout); return .failed }
            let first = await g.next() ?? .failed
            g.cancelAll()
            return first
        }
        switch outcome {
        case .failed:
            log(Task.isCancelled ? "abgebrochen" : "keine Antwort (Fehler oder Zeitüberschreitung)"); return nil
        case .notFound:
            log("keine Marken (404)"); return []
        case .data(let data):
            guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { log("keine verwertbare Antwort"); return nil }
            let list = Self.parse(data)
            log(list.isEmpty ? "keine Marken" : list.map { "\($0.kind.rawValue) \(Self.logSeconds($0.start))–\(Self.logSeconds($0.end))s" }.joined(separator: ", "))
            return list
        }
    }
}
