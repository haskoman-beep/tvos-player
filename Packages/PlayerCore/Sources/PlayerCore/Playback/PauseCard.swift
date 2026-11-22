import Foundation

// Wave P-b: pause card. After about 2 s of pause without input it shows the logo (or the title), season/episode
// with the episode title, a short description, the cast line and the clock. Any input hides it.

/// When the card is visible. Times are seconds on one monotonic clock (e.g. `systemUptime`).
public struct PauseCardRule: Equatable, Sendable {
    /// Pause without input until the card appears.
    public static let delay: Double = 2
    /// After an input during the same pause the card waits longer before it comes back, so browsing the paused
    /// control bar is not interrupted every two seconds.
    public static let delayAfterInput: Double = 6

    public private(set) var pausedSince: Double?
    public private(set) var lastInput: Double?

    public init() {}

    /// Feed the playing state on every check. Returns true when it changed.
    @discardableResult
    public mutating func update(isPlaying: Bool, now: Double) -> Bool {
        if isPlaying {
            guard pausedSince != nil else { return false }
            pausedSince = nil; lastInput = nil
            return true
        }
        guard pausedSince == nil else { return false }
        pausedSince = now
        lastInput = nil
        return true
    }

    /// Any key, swipe or click.
    public mutating func noteInput(now: Double) {
        guard pausedSince != nil else { return }
        lastInput = now
    }

    /// `blocked`: a panel, scrubbing, the failure card, the up-next card, the skip button, loading or leaving.
    public func isVisible(now: Double, blocked: Bool) -> Bool {
        guard !blocked, let p = pausedSince else { return false }
        if let i = lastInput, i >= p { return now - i >= Self.delayAfterInput }
        return now - p >= Self.delay
    }

    /// Why the card is not shown although paused (for one log line), nil when shown or playing.
    public static func blockReason(panelOpen: Bool, scrubbing: Bool, failure: Bool, upNext: Bool, skipPrompt: Bool,
                                   loading: Bool, leaving: Bool, noPicture: Bool) -> String? {
        if leaving { return "Ausgang" }
        if failure { return "Fehlerkarte" }
        if noPicture { return "kein Bild" }
        if loading { return "lädt" }
        if panelOpen { return "Panel offen" }
        if scrubbing { return "Spulen" }
        if upNext { return "Up-next" }
        if skipPrompt { return "Überspringen-Knopf" }
        return nil
    }
}

/// Texts of the card.
public struct PauseCardContent: Equatable, Sendable {
    public var title: String
    /// Logo picture; the title is shown when it is missing or fails to load.
    public var logoURL: String?
    /// "S1 · F3 · Pilot".
    public var episodeLine: String?
    public var description: String?
    /// "Mit Anna A., Bert B., …".
    public var castLine: String?

    public static let maxDescription = 260
    public static let maxCast = 4

    public init(title: String, logoURL: String? = nil, episodeLine: String? = nil, description: String? = nil,
                castLine: String? = nil) {
        self.title = title; self.logoURL = logoURL; self.episodeLine = episodeLine
        self.description = description; self.castLine = castLine
    }

    /// `descriptions`: candidates in order (localized episode text, addon episode text, then the title's text for a
    /// movie); the first non-empty one wins.
    public static func make(title: String, logo: String?, season: Int?, episode: Int?, episodeTitle: String?,
                            descriptions: [String?], cast: [String]) -> PauseCardContent {
        var line: String?
        if let s = season, let e = episode {
            line = "S\(s) · F\(e)"
            if let t = clean(episodeTitle) { line! += " · \(t)" }
        }
        let text = descriptions.lazy.compactMap { clean($0) }.first.map { shortened($0, maxChars: maxDescription) }
        let names = cast.compactMap { clean($0) }.prefix(maxCast)
        return PauseCardContent(title: clean(title) ?? title, logoURL: clean(logo), episodeLine: line,
                                description: text, castLine: names.isEmpty ? nil : "Mit " + names.joined(separator: ", "))
    }

    /// Cut at a word boundary and add "…"; a sentence end in the last third is preferred.
    public static func shortened(_ text: String, maxChars: Int) -> String {
        let t = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        guard t.count > maxChars else { return t }
        let head = String(t.prefix(maxChars))
        if let dot = head.lastIndex(where: { ".!?".contains($0) }), head.distance(from: head.startIndex, to: dot) >= maxChars * 2 / 3 {
            return String(head[...dot])
        }
        let cut = head.lastIndex(of: " ").map { String(head[..<$0]) } ?? head
        return cut.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–")) + " …"
    }

    static func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}

/// What a later accessory (X-Ray, waves X4/X5) gets to fill its slot on the pause card.
public struct PauseCardAccessoryContext: Equatable, Sendable {
    /// IMDb ID of the title (series ID for an episode).
    public var itemID: String
    public var season: Int?
    public var episode: Int?
    /// Paused position in seconds.
    public var position: Double
    /// Cast names as shown in the cast line (full list, not cut).
    public var cast: [String]

    public init(itemID: String, season: Int? = nil, episode: Int? = nil, position: Double, cast: [String] = []) {
        self.itemID = itemID; self.season = season; self.episode = episode; self.position = position; self.cast = cast
    }
}
