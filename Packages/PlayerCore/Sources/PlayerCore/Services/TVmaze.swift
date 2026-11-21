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
        await gate.wait()   // die Antwort ist eine Weiterleitung (301): zählt als zweiter Abruf
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

/// Zwischenspeicher, auf Platte wenn `file` gesetzt: TVmaze-ID je IMDb-ID (ändert sich nie, bleibt; „unbekannt“
/// 7 Tage), Zeitpunkte je Serie 6 h, nach Fehlern 5 min. So fallen beim Kaltstart höchstens die Folgenlisten an.
public actor TVmazeAirtimes {
    public static let lifetime: TimeInterval = 6 * 3600
    static let missingLifetime: TimeInterval = 7 * 24 * 3600
    static let failedLifetime: TimeInterval = 300

    struct StampEntry: Codable, Equatable { var at: Date; var ttl: TimeInterval; var value: [String: Date] }
    struct Disk: Codable, Equatable {
        var ids: [String: Int] = [:]
        var missing: [String: Date] = [:]
        var stamps: [String: StampEntry] = [:]
    }

    let client: TVmazeClient
    let file: URL?
    private var disk = Disk()
    private var loaded = false

    public init(client: TVmazeClient = TVmazeClient(), file: URL? = nil) { self.client = client; self.file = file }

    /// Zeitpunkte der Folgen einer Serie; [] wenn unbekannt oder gestört.
    public func stamps(imdb: String, now: Date = Date()) async -> [String: Date] {
        load()
        let id: Int
        if let known = disk.ids[imdb] { id = known }
        else if let m = disk.missing[imdb], now.timeIntervalSince(m) < Self.missingLifetime { return [:] }
        else {
            do {
                guard let found = try await client.showID(imdb: imdb) else {
                    disk.missing[imdb] = now; save(); return [:]
                }
                disk.ids[imdb] = found; disk.missing[imdb] = nil; id = found
            } catch { return [:] }
        }
        let key = String(id)
        if let e = disk.stamps[key], now.timeIntervalSince(e.at) < e.ttl { return e.value }
        do {
            let v = try await client.airstamps(showID: id)
            disk.stamps[key] = StampEntry(at: now, ttl: Self.lifetime, value: v)
            save()
            return v
        } catch {
            disk.stamps[key] = StampEntry(at: now, ttl: Self.failedLifetime, value: [:])
            return [:]
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let file, let d = try? Data(contentsOf: file), let x = try? JSONDecoder().decode(Disk.self, from: d) { disk = x }
    }

    private func save() {
        guard let file else { return }
        // Alte Zeitpunkte nicht ewig mitschleppen.
        let now = Date()
        disk.stamps = disk.stamps.filter { now.timeIntervalSince($0.value.at) < 7 * 24 * 3600 }
        if let d = try? JSONEncoder().encode(disk) { try? d.write(to: file, options: .atomic) }
    }
}
