import Foundation

/// Sendezeiten aus TVmaze (`https://api.tvmaze.com`, ohne Schlüssel; Daten CC BY-SA 4.0, Nennung in den Einstellungen).
/// TMDB kennt nur das Datum im Herkunftsland: eine US-Abendfolge stünde in Europa einen Tag zu früh. TVmaze liefert
/// den genauen Zeitpunkt (`airstamp`, UTC); daraus werden Tag und Uhrzeit in der Gerätezeitzone.
public struct TVmazeClient: Sendable {
    static let base = "https://api.tvmaze.com"
    let http: APISending
    let sleep: APISleep
    let gate: TVmazeGate

    public init(http: APISending = URLSessionSender(), sleep: @escaping APISleep = defaultAPISleep) {
        self.http = http; self.sleep = sleep; self.gate = TVmazeGate(sleep: sleep)
    }

    /// TVmaze-ID zur IMDb-ID; nil = Serie dort unbekannt (404).
    public func showID(imdb: String) async throws -> Int? {
        guard imdb.hasPrefix("tt"), imdb.dropFirst(2).allSatisfy(\.isNumber),
              let u = URL(string: "\(Self.base)/lookup/shows?imdb=\(imdb)") else { return nil }
        let r = try await get(u)
        if r.status == 404 { return nil }
        guard (200..<300).contains(r.status) else { throw APIError.status(r.status) }
        return ((try? JSONSerialization.jsonObject(with: r.data)) as? [String: Any])?["id"] as? Int
    }

    /// Zeitpunkte aller Folgen, Schlüssel "Staffel:Folge".
    public func airstamps(showID: Int) async throws -> [String: Date] {
        guard let u = URL(string: "\(Self.base)/shows/\(showID)/episodes") else { return [:] }
        let r = try await get(u)
        guard (200..<300).contains(r.status) else { throw APIError.status(r.status) }
        return Self.parseAirstamps(r.data)
    }

    static func parseAirstamps(_ data: Data) -> [String: Date] {
        guard let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [:] }
        var out: [String: Date] = [:]
        for e in arr {
            guard let s = e["season"] as? Int, let n = e["number"] as? Int,
                  let stamp = (e["airstamp"] as? String).flatMap(ISODate.dateTime) else { continue }
            out["\(s):\(n)"] = stamp
        }
        return out
    }

    /// Höchstens 20 Abrufe je 10 s (Grenze der API); bei 429 einmal nach `Retry-After` wiederholen.
    private func get(_ u: URL) async throws -> APIResponse {
        await gate.wait()
        return try await http.sendRespectingRateLimit(APIRequest(method: "GET", url: u, headers: [:], body: nil), sleep: sleep)
    }

    /// Folgen mit TVmaze-Zeitpunkt: Tag und Uhrzeit ("20:15") in `calendar`. Übernommen wird nur, wenn der Tag
    /// höchstens einen Tag neben dem TMDB-Datum liegt (sonst ist es vermutlich eine andere Zählung).
    public static func apply(_ eps: [UpcomingEpisode], stamps: [String: Date], calendar: Calendar) -> [UpcomingEpisode] {
        eps.map { e in
            guard let stamp = stamps["\(e.season):\(e.episode)"] else { return e }
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: stamp)
            let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            guard let tmdbDay = Upcoming.dayOffset(e.airDate, today: stamp, calendar: calendar), abs(tmdbDay) <= 1 else { return e }
            var out = e
            out.airDate = day
            out.airTime = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            return out
        }
    }
}

/// Taktgeber: höchstens `limit` Abrufe je `window` Sekunden.
public actor TVmazeGate {
    private var recent: [Date] = []
    private let limit = 20
    private let window: TimeInterval = 10
    private let sleep: APISleep

    init(sleep: @escaping APISleep) { self.sleep = sleep }

    /// Vergibt Startzeiten der Reihe nach: der n-te Abruf startet frühestens `window` nach dem (n − limit)-ten.
    func wait() async {
        let now = Date()
        recent.removeAll { now.timeIntervalSince($0) >= window }
        let slot = recent.count >= limit ? max(now, recent[recent.count - limit].addingTimeInterval(window)) : now
        recent.append(slot)
        if slot > now { await sleep(slot.timeIntervalSince(now)) }
    }
}

/// Zwischenspeicher: TVmaze-ID je IMDb-ID (bleibt), Zeitpunkte je Serie 6 h; Fehler 5 min.
public actor TVmazeAirtimes {
    public static let lifetime: TimeInterval = 6 * 3600
    let client: TVmazeClient
    private var ids: [String: Int?] = [:]
    private var stamps: [Int: (at: Date, ttl: TimeInterval, value: [String: Date])] = [:]

    public init(client: TVmazeClient = TVmazeClient()) { self.client = client }

    /// Zeitpunkte der Folgen einer Serie; [] wenn unbekannt oder gestört.
    public func stamps(imdb: String, now: Date = Date()) async -> [String: Date] {
        let id: Int?
        if let known = ids[imdb] { id = known }
        else {
            do { id = try await client.showID(imdb: imdb); ids[imdb] = id } catch { return [:] }
        }
        guard let id else { return [:] }
        if let s = stamps[id], now.timeIntervalSince(s.at) < s.ttl { return s.value }
        do {
            let v = try await client.airstamps(showID: id)
            stamps[id] = (now, Self.lifetime, v)
            return v
        } catch {
            stamps[id] = (now, 300, [:])
            return [:]
        }
    }
}
