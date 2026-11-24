import Foundation

/// Wave P-a: what happens in a skippable segment of one kind.
public enum SkipAction: String, Codable, Sendable, CaseIterable {
    /// No button, no jump (the segment still shows on the timeline).
    case off
    /// Button „… überspringen“, takes the focus as before.
    case button
    /// Button with a countdown ring; when it runs out the player jumps. Any key stops the countdown.
    case auto

    public var label: String {
        switch self {
        case .off: "Aus"
        case .button: "Knopf"
        case .auto: "Automatisch"
        }
    }
}

/// Wave P-a: skip action per segment type, plus the card after a movie. Stored in the profile (`Profile.skip`).
/// Defaults keep the behaviour before this wave: intro and recap with a button, credits without a button (the
/// credits only drive the next-episode card), preview off. A scene after the credits is never skipped.
public struct SkipSettings: Codable, Sendable, Equatable {
    public var intro: SkipAction
    public var recap: SkipAction
    public var credits: SkipAction
    public var preview: SkipAction
    /// Card with recommendations once a movie's credits start (needs credits data from chapters or IntroDB).
    public var postPlayCard: Bool

    public init(intro: SkipAction = .button, recap: SkipAction = .button, credits: SkipAction = .off,
                preview: SkipAction = .off, postPlayCard: Bool = true) {
        self.intro = intro; self.recap = recap; self.credits = credits; self.preview = preview
        self.postPlayCard = postPlayCard
    }

    /// Kinds with a setting, in display order.
    public static let configurableKinds: [SkipSegment.Kind] = [.intro, .recap, .credits, .preview]

    public func action(for kind: SkipSegment.Kind) -> SkipAction {
        switch kind {
        case .intro: intro
        case .recap: recap
        case .credits: credits
        case .preview: preview
        case .postCredits: .off
        }
    }

    public mutating func set(_ action: SkipAction, for kind: SkipSegment.Kind) {
        switch kind {
        case .intro: intro = action
        case .recap: recap = action
        case .credits: credits = action
        case .preview: preview = action
        case .postCredits: break
        }
    }

    /// Settings row title per kind.
    public static func title(_ kind: SkipSegment.Kind) -> String {
        switch kind {
        case .intro: "Intro"
        case .recap: "Rückblick"
        case .credits: "Abspann"
        case .preview: "Vorschau"
        case .postCredits: "Szene nach dem Abspann"
        }
    }

    enum CodingKeys: String, CodingKey { case intro, recap, credits, preview, postPlayCard }

    /// Missing or unknown values (older profiles, newer app) fall back to the default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SkipSettings()
        intro = (try? c.decodeIfPresent(SkipAction.self, forKey: .intro)) ?? nil ?? d.intro
        recap = (try? c.decodeIfPresent(SkipAction.self, forKey: .recap)) ?? nil ?? d.recap
        credits = (try? c.decodeIfPresent(SkipAction.self, forKey: .credits)) ?? nil ?? d.credits
        preview = (try? c.decodeIfPresent(SkipAction.self, forKey: .preview)) ?? nil ?? d.preview
        postPlayCard = (try? c.decodeIfPresent(Bool.self, forKey: .postPlayCard)) ?? nil ?? d.postPlayCard
    }
}

/// Wave P-a: what the player knows about the cards that already cover the credits.
public struct SkipContext: Sendable, Equatable {
    /// An episode with the next-episode card (autoplay on, next episode known, no „Noch da?“ pending).
    public var upNextCard: Bool
    /// A movie with the card after the movie switched on.
    public var postPlayCard: Bool
    /// Running time of the file in seconds (0 = unknown; then no credits count as end credits).
    public var duration: Double

    public init(upNextCard: Bool = false, postPlayCard: Bool = false, duration: Double = 0) {
        self.upNextCard = upNextCard; self.postPlayCard = postPlayCard; self.duration = duration
    }
}

/// Wave P-a: shown for one segment now. `countdown` = seconds left before the automatic jump; nil = plain button.
public struct SkipPrompt: Sendable, Equatable {
    public var segment: SkipSegment
    public var countdown: Double?

    public init(segment: SkipSegment, countdown: Double? = nil) { self.segment = segment; self.countdown = countdown }

    /// Ring progress 1 → 0 (1 = full countdown left).
    public var ringFraction: Double? { countdown.map { min(1, max(0, $0 / SkipPlanner.countdownSeconds)) } }
}

/// Wave P-a: result of `SkipPlanner.evaluate`.
public struct SkipDecision: Sendable, Equatable {
    public var prompt: SkipPrompt?
    /// The countdown ran out: jump over this segment now.
    public var autoSkip: SkipSegment?

    public init(prompt: SkipPrompt? = nil, autoSkip: SkipSegment? = nil) { self.prompt = prompt; self.autoSkip = autoSkip }
}

/// Wave P-a: rules for credits, the scene after them, and the card after a movie. Pure functions.
public enum SkipPolicy {
    /// More than this many seconds after the credits without a known segment: there may be a scene.
    public static let unknownTailSeconds: Double = 5

    /// The end credits: first credits segment that starts after 60 % of the running time.
    public static func endCredits(_ segments: [SkipSegment], duration: Double) -> SkipSegment? {
        guard duration > 0 else { return nil }
        return segments.first { $0.kind == .credits && $0.start >= SkipSegments.creditsMinFraction * duration
                                && $0.start < duration }
    }

    /// true = after the credits more than 5 s remain that no known segment (a preview) fills.
    static func unknownTail(after credits: SkipSegment, _ segments: [SkipSegment], duration: Double) -> Bool {
        var covered = credits.end
        for s in segments.sorted(by: { $0.start < $1.start })
            where s.kind == .preview && s.start <= covered + 2 && s.end > covered { covered = s.end }
        return duration - covered > unknownTailSeconds
    }

    /// Start of the scene after the end credits; nil = none known.
    /// - A post-credits segment after the credits starts: its start.
    /// - Credits from chapters or IntroDB that end more than 5 s before the file end, with nothing known filling
    ///   the rest (no preview): content follows at the end of the credits. A season estimate never counts (its credits
    ///   always run to the end).
    public static func sceneAfterCredits(_ segments: [SkipSegment], duration: Double) -> Double? {
        guard let credits = endCredits(segments, duration: duration) else { return nil }
        if let post = segments.first(where: { $0.kind == .postCredits && $0.start >= credits.start && $0.start < duration }) {
            return max(credits.start, min(post.start, credits.end))
        }
        guard credits.source != .seasonEstimate, credits.end < duration,
              unknownTail(after: credits, segments, duration: duration) else { return nil }
        return credits.end
    }

    /// Where a skip of this segment lands (before `SkipPlanner` keeps it 5 s before the file end).
    /// End credits with a scene after them land at the scene, never further.
    public static func target(for s: SkipSegment, in segments: [SkipSegment], duration: Double) -> Double {
        guard s.kind == .credits, let credits = endCredits(segments, duration: duration), credits == s,
              let scene = sceneAfterCredits(segments, duration: duration) else { return s.end }
        return min(s.end, scene)
    }

    /// Task 3.5 (W-B-12): where a skip lands from `position`. Never before the position (a skip never jumps
    /// backwards) and, with a known duration, never later than 1 s before the file end:
    /// `max(position, min(target, duration − 1))`.
    public static func skipTarget(for s: SkipSegment, in segments: [SkipSegment], position: Double,
                                  duration: Double) -> Double {
        var t = target(for: s, in: segments, duration: duration)
        if duration > 0 { t = min(t, duration - 1) }
        return max(max(0, position), t)
    }

    /// Action for a segment under the given settings. The end credits get no button or countdown while a card
    /// covers them: the card after a movie, or the next-episode card (unless a scene follows; then that card waits
    /// for the scene and the button leads to the scene).
    public static func action(for s: SkipSegment, segments: [SkipSegment], settings: SkipSettings,
                              context: SkipContext) -> SkipAction {
        var a = settings.action(for: s.kind)
        // A season estimate is a guess from other episodes: never an automatic jump, only the button.
        if a == .auto, s.source == .seasonEstimate { a = .button }
        guard s.kind == .credits, a != .off, endCredits(segments, duration: context.duration) == s else { return a }
        if context.postPlayCard { return .off }
        if context.upNextCard, sceneAfterCredits(segments, duration: context.duration) == nil { return .off }
        return a
    }

    /// Movie IntroDB marks belong to an IMDb ID, not to this release (other cut, other frame rate). Their credits
    /// only count when they line up with this file: some credits or post-credits mark ends within this many seconds
    /// of the file end.
    public static let movieAlignSeconds: Double = 5

    /// IntroDB marks of a movie for this file: credits and post-credits marks are dropped unless one of them ends
    /// at the file end (± `movieAlignSeconds`). Otherwise the card, the scene hint and the credits button would show
    /// inside the film. Chapters are not affected (they come from the file itself). Duration 0 = unchanged.
    public static func alignedMovieIntroDB(_ list: [SkipSegment], duration: Double) -> [SkipSegment] {
        guard duration > 0 else { return list }
        let tail: (SkipSegment) -> Bool = { $0.kind == .credits || $0.kind == .postCredits }
        guard list.contains(where: tail),
              !list.contains(where: { tail($0) && abs($0.end - duration) <= movieAlignSeconds }) else { return list }
        return list.filter { !tail($0) }
    }

    /// Window of the card after a movie: from the start of the end credits up to the scene after them (the card
    /// never covers it) or the file end. nil = no end credits known.
    public static func postPlayWindow(_ segments: [SkipSegment], duration: Double) -> Range<Double>? {
        guard let credits = endCredits(segments, duration: duration) else { return nil }
        let end = sceneAfterCredits(segments, duration: duration) ?? duration
        return end > credits.start ? credits.start..<end : nil
    }

    /// Window of the hint „Szene nach dem Abspann“: from the start of the end credits to the scene.
    public static func sceneHintWindow(_ segments: [SkipSegment], duration: Double) -> Range<Double>? {
        guard let credits = endCredits(segments, duration: duration),
              let scene = sceneAfterCredits(segments, duration: duration), scene > credits.start else { return nil }
        return credits.start..<scene
    }
}

/// Wave P-a: recommendations for the card after a movie: not the movie itself, no doubles, only with a poster.
public enum PostPlayPicks {
    public static func choose(_ list: [MetaPreview], excluding id: String, imdb: String?, limit: Int = 3) -> [MetaPreview] {
        var seen: Set<String> = [id]
        if let imdb { seen.insert(imdb) }
        var out: [MetaPreview] = []
        for m in list where out.count < limit {
            guard !seen.contains(m.id), m.poster?.isEmpty == false else { continue }
            seen.insert(m.id)
            out.append(m)
        }
        return out
    }
}
