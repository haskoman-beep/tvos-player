import Foundation

/// Eine kommende (oder gerade erschienene) Folge für Kalender und „Heute neu“.
public struct UpcomingEpisode: Sendable, Hashable, Identifiable {
    /// ID der Serie wie in Weiterschauen/Merkliste ("tt123" oder "tmdb:456").
    public var seriesID: String
    public var seriesName: String
    public var poster: String?
    public var season: Int
    public var episode: Int
    public var title: String?
    /// YYYY-MM-DD (Erstausstrahlung laut TMDB).
    public var airDate: String
    /// Standbild der Folge (Querformat-Kachel).
    public var still: String?
    /// Hintergrund der Serie (Rückfall für die Querformat-Kachel).
    public var background: String?

    public init(seriesID: String, seriesName: String, poster: String? = nil, season: Int, episode: Int,
                title: String? = nil, airDate: String, still: String? = nil, background: String? = nil) {
        self.seriesID = seriesID; self.seriesName = seriesName; self.poster = poster
        self.season = season; self.episode = episode; self.title = title; self.airDate = airDate
        self.still = still; self.background = background
    }

    public var id: String { "\(seriesID):\(season):\(episode)" }
    /// "S2 F5".
    public var episodeLabel: String { "S\(season) F\(episode)" }
    /// "S2 F5 · Titel".
    public var label: String { [episodeLabel, title].compactMap { $0 }.joined(separator: " · ") }
}

/// Kalenderlogik (Spec §7a.3): Serien aus Weiterschauen und Merkliste, Zeitraum gestern bis 14 Tage voraus.
public enum Upcoming {
    public static let daysAhead = 14
    static let weekdays = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]

    /// Tag relativ zu `today` (0 = heute), nil bei unlesbarem Datum.
    public static func dayOffset(_ airDate: String, today: Date, calendar: Calendar) -> Int? {
        let parts = airDate.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let d = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: d)).day
    }

    /// Nach Tag gruppiert (gestern … heute + 14), innerhalb eines Tages nach Serienname.
    public static func days(_ eps: [UpcomingEpisode], today: Date, calendar: Calendar) -> [(label: String, items: [UpcomingEpisode])] {
        var byDay: [Int: [UpcomingEpisode]] = [:]
        var seen = Set<String>()
        for e in eps {
            guard let o = dayOffset(e.airDate, today: today, calendar: calendar), (-1...daysAhead).contains(o),
                  seen.insert(e.id).inserted else { continue }
            byDay[o, default: []].append(e)
        }
        return byDay.keys.sorted().map { o in
            let items = byDay[o]!.sorted {
                let c = $0.seriesName.localizedCaseInsensitiveCompare($1.seriesName)
                if c != .orderedSame { return c == .orderedAscending }
                return ($0.season, $0.episode) < ($1.season, $1.episode)
            }
            return (label(offset: o, today: today, calendar: calendar), items)
        }
    }

    /// „Gestern“, „Heute“, „Morgen“, sonst „Mi 26.11.“.
    public static func label(offset: Int, today: Date, calendar: Calendar) -> String {
        switch offset {
        case -1: return "Gestern"
        case 0: return "Heute"
        case 1: return "Morgen"
        default:
            guard let d = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: today)) else { return "" }
            let c = calendar.dateComponents([.weekday, .day, .month], from: d)
            let wd = weekdays[((c.weekday ?? 1) - 1) % 7]
            return "\(wd) \(c.day ?? 0).\(c.month ?? 0)."
        }
    }

    /// Folgen, die heute erscheinen (für die Reihe „Heute neu“).
    public static func today(_ eps: [UpcomingEpisode], today: Date, calendar: Calendar) -> [UpcomingEpisode] {
        days(eps, today: today, calendar: calendar).first { $0.label == "Heute" }?.items ?? []
    }

    /// Serien für den Kalender: nur Serien, ohne Doppelte, Weiterschauen zuerst, höchstens `limit`.
    public static func seriesIDs(continueWatching: [WatchProgress], watchlist: [MetaPreview], limit: Int = 50) -> [String] {
        var seen = Set<String>()
        let ids = continueWatching.filter { $0.item.type == "series" || $0.season != nil }.map(\.item.id)
            + watchlist.filter { $0.type == "series" }.map(\.id)
        return Array(ids.filter { seen.insert($0).inserted }.prefix(limit))
    }

    /// Letzter Tag des Kalenders als YYYY-MM-DD (Abrufe weiterer Folgen nur bis dahin).
    public static func lastDay(today: Date, calendar: Calendar) -> String {
        let d = calendar.date(byAdding: .day, value: daysAhead, to: calendar.startOfDay(for: today)) ?? today
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
