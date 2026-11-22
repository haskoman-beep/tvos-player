import Foundation

/// Wave F-p: how long a resting tile waits before its sources are fetched (home hero: `HomeFocus`; pages without
/// hero: `StreamPrefetcher.requestAfterRest`). Fast scrolling through a row starts nothing.
public enum FocusRest {
    public static let milliseconds = 350
}

extension ContentKind {
    /// Wave F-p: the catalogue type alone says movie or series (the meta's episode list cannot change it), so the
    /// detail page may ask TMDB in parallel to the meta instead of after it.
    public static func typeDecides(_ type: String) -> Bool {
        isEpisodic(type: type, hasVideos: false) == isEpisodic(type: type, hasVideos: true)
    }
}

/// Wave F-p: when the parts of a detail page arrived, in ms since the page appeared; one log line per page
/// („detail: Ladezeiten …“). Device log build 214: the badges and the poster came late again, the old lines showed
/// only the first badge.
public struct DetailLoadTimeline: Sendable, Equatable {
    public enum Part: String, Sendable, CaseIterable {
        /// IMDb ID known (TMDB lookup for `tmdb:` entries).
        case id = "ID"
        /// TMDB in the profile language (age rating, cast, similar titles).
        case tmdb = "TMDB"
        /// Merged meta (addon, Cinemeta, TMDB): logo, description, episodes.
        case meta = "Meta"
        /// Poster left of the info block shown.
        case poster = "Poster"
        /// Tech badges known (movies only).
        case tech = "Technik"
    }

    /// After this the line is logged with whatever arrived (a part that never comes shows „–“).
    public static let giveUpMilliseconds = 10_000

    public let title: String
    public let expectsTech: Bool
    public private(set) var times: [Part: Int] = [:]
    /// Where the tech badges came from („Cache“, „vorgeladen“, „neu, 154 Quellen“).
    public private(set) var techSource: String?
    public private(set) var logged = false

    public init(title: String, expectsTech: Bool) {
        self.title = title
        self.expectsTech = expectsTech
    }

    /// Records the first arrival of `part`; later ones are ignored.
    public mutating func mark(_ part: Part, ms: Int, source: String? = nil) {
        guard times[part] == nil else { return }
        times[part] = max(0, ms)
        if part == .tech { techSource = source }
    }

    /// Parts that must arrive before the line is logged (the poster is optional: a short block shows none).
    public var required: [Part] { expectsTech ? [.id, .tmdb, .meta, .tech] : [.id, .tmdb, .meta] }

    public var isComplete: Bool { required.allSatisfy { times[$0] != nil } }

    /// The line once all required parts arrived, or with `force` (give-up time, page left); nil afterwards.
    public mutating func takeLine(force: Bool = false) -> String? {
        guard !logged, isComplete || force else { return nil }
        logged = true
        return line
    }

    public var line: String {
        let parts: [Part] = expectsTech ? Part.allCases : Part.allCases.filter { $0 != .tech }
        let fields = parts.map { p -> String in
            guard let ms = times[p] else { return "\(p.rawValue) –" }
            if p == .tech, let s = techSource { return "\(p.rawValue) \(ms) ms (\(s))" }
            return "\(p.rawValue) \(ms) ms"
        }
        return "Ladezeiten \(title) · " + fields.joined(separator: " · ")
    }
}
