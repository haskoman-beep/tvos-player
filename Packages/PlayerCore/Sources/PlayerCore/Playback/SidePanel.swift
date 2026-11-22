import Foundation

// Wave P-b: side panel in the player. It sits in the right third (720 pt), the picture keeps running. A start list
// of entries; choosing one replaces the list in the same panel ("stack of one"). Back goes up one level, then closes.

/// Pages of the side panel.
public enum SidePanelPage: String, Equatable, Hashable, Sendable, CaseIterable {
    case episodes, chapters, sources, info

    public var title: String {
        switch self {
        case .episodes: "Folgen"
        case .chapters: "Kapitel"
        case .sources: "Andere Quelle"
        case .info: "Infos"
        }
    }

    /// Short name for the hint line in the control bar.
    public var shortTitle: String {
        switch self {
        case .episodes: "Folgen"
        case .chapters: "Kapitel"
        case .sources: "Quelle"
        case .info: "Infos"
        }
    }
}

/// One row of the start list: name and, on the right, the current value or count.
public struct SidePanelEntry: Equatable, Sendable, Identifiable {
    public var page: SidePanelPage
    public var title: String
    public var detail: String
    public var id: SidePanelPage { page }

    public init(page: SidePanelPage, title: String, detail: String) {
        self.page = page; self.title = title; self.detail = detail
    }
}

/// What the running title offers; empty parts leave their entry out.
public struct SidePanelAvailability: Equatable, Sendable {
    /// Episodes of the series (0 = movie or unknown).
    public var episodeCount: Int
    public var seasonCount: Int
    public var currentSeason: Int?
    public var currentEpisode: Int?
    public var chapterCount: Int
    /// Name of the chapter at the current position.
    public var currentChapter: String?
    /// Sources in the list including the running one; nil = the player cannot switch here (no source list).
    public var sourceCount: Int?
    /// Short technical summary ("4K · Dolby Vision · Dolby Atmos"); nil or empty = still loading.
    public var infoSummary: String?

    public init(episodeCount: Int = 0, seasonCount: Int = 0, currentSeason: Int? = nil, currentEpisode: Int? = nil,
                chapterCount: Int = 0, currentChapter: String? = nil, sourceCount: Int? = nil, infoSummary: String? = nil) {
        self.episodeCount = episodeCount; self.seasonCount = seasonCount
        self.currentSeason = currentSeason; self.currentEpisode = currentEpisode
        self.chapterCount = chapterCount; self.currentChapter = currentChapter
        self.sourceCount = sourceCount; self.infoSummary = infoSummary
    }
}

public enum SidePanelMenu {
    /// Start list in a fixed order: Folgen · Kapitel · Andere Quelle · Infos. Infos is always there.
    public static func entries(_ a: SidePanelAvailability) -> [SidePanelEntry] {
        var out: [SidePanelEntry] = []
        if a.episodeCount > 1 {
            var d = a.seasonCount > 1 ? "\(a.seasonCount) Staffeln" : "\(a.episodeCount) Folgen"
            if let s = a.currentSeason, let e = a.currentEpisode { d = "S\(s) F\(e) · " + d }
            out.append(.init(page: .episodes, title: SidePanelPage.episodes.title, detail: d))
        }
        if a.chapterCount > 0 {
            let n = a.chapterCount == 1 ? "1 Kapitel" : "\(a.chapterCount) Kapitel"
            let d = a.currentChapter.map { "\($0) · \(n)" } ?? n
            out.append(.init(page: .chapters, title: SidePanelPage.chapters.title, detail: d))
        }
        if let n = a.sourceCount, n > 1 {
            out.append(.init(page: .sources, title: SidePanelPage.sources.title,
                             detail: n - 1 == 1 ? "1 weitere" : "\(n - 1) weitere"))
        }
        let info = a.infoSummary.flatMap { $0.isEmpty ? nil : $0 } ?? "Technik der laufenden Quelle"
        out.append(.init(page: .info, title: SidePanelPage.info.title, detail: info))
        return out
    }

    /// Hint in the control bar, e.g. "▲ Folgen · Kapitel · Infos"; nil when only Infos is there.
    public static func hint(trackStyle: TrackPanelStyle, pages: [SidePanelPage]) -> String? {
        guard pages.contains(where: { $0 != .info }) else { return nil }
        let arrow = SidePanelGesture.opensDownward(trackStyle: trackStyle) ? "▼" : "▲"
        return arrow + " " + pages.map(\.shortTitle).joined(separator: " · ")
    }
}

/// Which gesture opens the side panel. The track panel keeps its gestures from build 198: "Leiste oben" opens with
/// a swipe down / ▼, "Leiste unten" and "Kleines Menü" with a swipe up / ▲. The other vertical direction did nothing
/// until now, so the side panel takes it.
public enum SidePanelGesture {
    public static func opens(trackStyle: TrackPanelStyle, gesture: TrackPanelGesture) -> Bool {
        !TrackPanelEntry.opens(style: trackStyle, gesture: gesture)
    }

    /// The side panel opens downward (▼) when the track panel uses upward gestures.
    public static func opensDownward(trackStyle: TrackPanelStyle) -> Bool {
        !TrackPanelEntry.opens(style: trackStyle, gesture: .swipeDown)
    }

    /// A track panel style that this gesture opens. Used to run the same guards as the track panel
    /// (`TrackPanelEntry.decide`): leaving, failure card, scrubbing, up-next card, skip button, locks.
    public static func guardStyle(for gesture: TrackPanelGesture) -> TrackPanelStyle {
        switch gesture {
        case .swipeDown, .clickDown: .topBar
        case .swipeUp, .clickUp: .bottomBar
        }
    }
}

/// Navigation of the side panel: start list or one page.
public struct SidePanelNav: Equatable, Sendable {
    public enum Back: Equatable, Sendable { case toList, close }

    /// nil = start list.
    public private(set) var page: SidePanelPage?
    /// Entry that gets the focus on the start list (after Back the page that was open).
    public private(set) var listFocus: SidePanelPage?

    public init(entries: [SidePanelEntry]) {
        listFocus = entries.first?.page
    }

    public mutating func open(_ p: SidePanelPage) {
        listFocus = p
        page = p
    }

    /// Menu button.
    public mutating func back() -> Back {
        guard let p = page else { return .close }
        listFocus = p
        page = nil
        return .toList
    }
}

// MARK: Chapters

public struct SideChapterRow: Equatable, Sendable, Identifiable {
    public var index: Int
    public var title: String
    /// "12:34" or "1:02:03".
    public var time: String
    public var start: Double
    public var isCurrent: Bool
    public var id: Int { index }
}

public enum SideChapters {
    /// Chapter at `position`: the last one that starts at or before it (nil before the first).
    public static func currentIndex(_ marks: [ChapterMark], position: Double) -> Int? {
        let sorted = marks.enumerated().sorted { $0.element.start < $1.element.start }
        return sorted.last(where: { $0.element.start <= position + 0.5 })?.offset
    }

    /// Rows in time order. Empty or generic names ("Chapter 3", "00:12:00.000") become "Kapitel N".
    public static func rows(_ marks: [ChapterMark], position: Double) -> [SideChapterRow] {
        let order = marks.indices.sorted { marks[$0].start < marks[$1].start }
        let current = currentIndex(marks, position: position)
        return order.enumerated().map { n, i in
            SideChapterRow(index: i, title: displayName(marks[i].name, number: n + 1), time: timeLabel(marks[i].start),
                           start: marks[i].start, isCurrent: i == current)
        }
    }

    public static func displayName(_ raw: String, number: Int) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || isGeneric(t) { return "Kapitel \(number)" }
        return t
    }

    /// "Chapter 1", "Kapitel 01", "1", "00:05:00.000", "Chapter 01 - 00:05:00".
    static func isGeneric(_ t: String) -> Bool {
        let l = t.lowercased()
        let stripped = ["chapter", "kapitel", "chap.", "ch."].reduce(l) { $0.replacingOccurrences(of: $1, with: "") }
        return stripped.allSatisfy { $0.isNumber || $0 == " " || $0 == ":" || $0 == "." || $0 == "-" }
    }

    public static func timeLabel(_ s: Double) -> String {
        let t = Int(max(0, s))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: Episodes

public struct SideEpisodeRow: Equatable, Sendable, Identifiable {
    public var season: Int
    public var episode: Int
    /// "F3 · Pilot" ("F3" without a title).
    public var line: String
    public var isCurrent: Bool
    public var isWatched: Bool
    public var id: String { "\(season):\(episode)" }
}

public enum SideEpisodes {
    public static func seasons(_ episodes: [EpisodeRef]) -> [Int] {
        Array(Set(episodes.map(\.season))).sorted()
    }

    /// The running season, else the first one.
    public static func initialSeason(current: Int?, in episodes: [EpisodeRef]) -> Int? {
        let s = seasons(episodes)
        if let c = current, s.contains(c) { return c }
        return s.first
    }

    /// Episodes of one season. `titles`: localized titles by episode number (they win over the addon's).
    public static func rows(_ episodes: [EpisodeRef], season: Int, current: EpisodeRef?, titles: [Int: String] = [:],
                            isWatched: (EpisodeRef) -> Bool) -> [SideEpisodeRow] {
        episodes.filter { $0.season == season }.sorted { $0.episode < $1.episode }.map { e in
            let title = (titles[e.episode] ?? e.title)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let line = title.flatMap { $0.isEmpty ? nil : "F\(e.episode) · \($0)" } ?? "F\(e.episode)"
            return SideEpisodeRow(season: e.season, episode: e.episode, line: line,
                                  isCurrent: current.map { $0.season == e.season && $0.episode == e.episode } ?? false,
                                  isWatched: isWatched(e))
        }
    }

    /// Row with the focus when the page opens: the running episode, else the first unwatched, else the first.
    public static func initialFocus(_ rows: [SideEpisodeRow]) -> String? {
        (rows.first(where: \.isCurrent) ?? rows.first(where: { !$0.isWatched }) ?? rows.first)?.id
    }
}

// MARK: Sources

public enum SideSourceChoice: Equatable, Sendable {
    /// Running source chosen: just close the panel.
    case keep
    /// Start the chosen source at the held position.
    case switchTo(String)
    /// Source has no address (cannot play here).
    case unavailable
}

public enum SideSources {
    public static func choose(_ id: String, current: String?, playable: Bool) -> SideSourceChoice {
        if id == current { return .keep }
        return playable ? .switchTo(id) : .unavailable
    }

    /// Focus on open: the running source, else the first one.
    public static func initialFocus(ids: [String], current: String?) -> String? {
        if let c = current, ids.contains(c) { return c }
        return ids.first
    }
}

// MARK: Info

public enum SideInfo {
    /// Rows of the info page: the track panel's technical rows, then audio track, data rate, size and addon.
    public static func rows(tech: PlaybackTechSnapshot, traits: StreamTraits? = nil, duration: Double = 0,
                            addon: String? = nil) -> [TrackPanelInfoRow] {
        var rows = TrackPanelLogic.infoRows(tech)
        if let a = tech.activeAudio {
            var parts = [MediaLabels.languageName(a.language)]
            let fmt = MediaLabels.audioFormat(codec: a.codec, profile: a.profile, isAtmos: a.isAtmos, isDTSX: a.isDTSX)
            if fmt != "Unbekannt" { parts.append(fmt) }
            if let ch = MediaLabels.channels(a.channels, layout: a.channelLayout) { parts.append(ch) }
            let at = rows.firstIndex(where: { $0.label == "Ton-Ausgabe" }) ?? rows.endIndex
            rows.insert(.init(label: "Tonspur", value: parts.joined(separator: " · ")), at: at)
        }
        if let r = bitrateLabel(sizeBytes: traits?.sizeBytes, duration: traits?.durationSeconds ?? duration) {
            rows.append(.init(label: "Datenrate", value: r))
        }
        if let b = traits?.sizeBytes, b > 0 { rows.append(.init(label: "Größe", value: sizeLabel(b))) }
        if let a = addon?.trimmingCharacters(in: .whitespaces), !a.isEmpty { rows.append(.init(label: "Addon", value: a)) }
        return rows
    }

    /// Average data rate from file size and running time, "≈ 24,3 Mbit/s".
    public static func bitrateLabel(sizeBytes: Int64?, duration: Double) -> String? {
        guard let b = sizeBytes, b > 0, duration > 60 else { return nil }
        let mbps = Double(b) * 8 / duration / 1_000_000
        return "≈ " + decimal(mbps, digits: mbps >= 100 ? 0 : 1) + " Mbit/s"
    }

    /// "58,2 GB" / "850 MB".
    public static func sizeLabel(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1 { return decimal(gb, digits: 1) + " GB" }
        return decimal(Double(bytes) / 1_000_000, digits: 0) + " MB"
    }

    /// Start list detail: resolution · dynamic range (from the info rows).
    public static func summary(_ rows: [TrackPanelInfoRow]) -> String? {
        let parts = ["Auflösung", "Dynamik"].compactMap { l in rows.first { $0.label == l }?.value }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func decimal(_ v: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", v).replacingOccurrences(of: ".", with: ",")
    }
}
