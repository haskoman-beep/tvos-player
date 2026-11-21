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

    /// Welle D-b (N-M4): Ergebnisse je Serie (in beliebiger Fertig-Reihenfolge) in die ursprüngliche Reihenfolge
    /// zurücksetzen. So vergleicht `merged != original` den Inhalt und nicht die Reihenfolge, in der die Serien fertig wurden.
    public static func merged(_ original: [UpcomingEpisode], updated: [UpcomingEpisode]) -> [UpcomingEpisode] {
        var byKey: [String: UpcomingEpisode] = [:]
        for e in updated { byKey["\(e.seriesID)|\(e.season)|\(e.episode)"] = e }
        return original.map { byKey["\($0.seriesID)|\($0.season)|\($0.episode)"] ?? $0 }
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
/// Welle D-b (N-M5): Je Serie bleiben nur die Zeitpunkte im Kalenderfenster (mit Puffer), und die Datei wird
/// nicht bei jeder Abfrage geschrieben, sondern einmal je Durchgang über `flush()`. Beim Schreiben wird
/// aufgeräumt: „unbekannt“ nach 7 Tagen, Zeitpunkte nach 7 Tagen, IDs über `maxIDs` nur noch die zuletzt genutzten.
public actor TVmazeAirtimes {
    public static let lifetime: TimeInterval = 6 * 3600
    static let missingLifetime: TimeInterval = 7 * 24 * 3600
    static let failedLifetime: TimeInterval = 300
    /// Kalenderfenster gestern bis +14 Tage, mit Puffer (6-h-Cache, Abweichung bis 1 Tag zum TMDB-Datum).
    static let keepBehind: TimeInterval = 3 * 24 * 3600
    static let keepAhead: TimeInterval = TimeInterval(Upcoming.daysAhead + 3) * 24 * 3600
    static let maxIDs = 300

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
    private var dirty = false

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
                    disk.missing[imdb] = now; dirty = true; return [:]
                }
                disk.ids[imdb] = found; disk.missing[imdb] = nil; id = found; dirty = true
            } catch { return [:] }
        }
        let key = String(id)
        if let e = disk.stamps[key], now.timeIntervalSince(e.at) < e.ttl { return e.value }
        do {
            let v = Self.window(try await client.airstamps(showID: id), now: now)
            disk.stamps[key] = StampEntry(at: now, ttl: Self.lifetime, value: v)
            dirty = true
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

    /// Geänderten Stand einmal schreiben (nach einem Durchgang über alle Serien). Ohne Änderung nichts.
    public func flush(now: Date = Date()) {
        guard dirty, let file else { return }
        dirty = false
        disk = Self.tidy(disk, now: now)
        if let d = try? JSONEncoder().encode(disk) { try? d.write(to: file, options: .atomic) }
    }

    /// Nur Zeitpunkte im Kalenderfenster um `now` behalten.
    static func window(_ stamps: [String: Date], now: Date) -> [String: Date] {
        stamps.filter { let d = $0.value.timeIntervalSince(now); return d >= -keepBehind && d <= keepAhead }
    }

    /// Aufräumen vor dem Schreiben: alte Zeitpunkte und „unbekannt“ nach 7 Tagen raus; zu viele IDs → nur die,
    /// deren Serie noch Zeitpunkte im Cache hat, davon höchstens `maxIDs` mit dem jüngsten Abruf.
    static func tidy(_ d: Disk, now: Date) -> Disk {
        var d = d
        d.stamps = d.stamps.filter { now.timeIntervalSince($0.value.at) < missingLifetime }
        d.missing = d.missing.filter { now.timeIntervalSince($0.value) < missingLifetime }
        if d.ids.count > maxIDs {
            // Nach echter letzter Nutzung: jüngster Abruf der Zeitpunkte zuerst (Gleichstand nach IMDb-ID).
            let used = d.ids.compactMap { e in d.stamps[String(e.value)].map { (e.key, e.value, $0.at) } }
            let kept = used.sorted { $0.2 != $1.2 ? $0.2 > $1.2 : $0.0 < $1.0 }.prefix(maxIDs)
            d.ids = Dictionary(uniqueKeysWithValues: kept.map { ($0.0, $0.1) })
        }
        return d
    }
}
