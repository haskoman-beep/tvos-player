import Foundation

/// Task 3.2: which start steps run after a successful load, for both ways in (start path `loadAndStart` and the
/// error ladder). W-A-1: the first successful load of a session always runs the whole start, also when it comes
/// from the ladder. W-A-3: every later load restores the last chosen audio track. W-A-4/W-B-4: the jump to the
/// synced fraction is repeated until it has been executed.
public struct StartSequence: Sendable {
    public enum Step: Sendable, Equatable {
        /// Placeholder clip check (short "not cached" clips → next source); logs „Geladen ·“.
        case placeholderCheck
        /// Audio choice. nil = automatic (track memory, then profile priority); an ID = restore that track.
        case selectAudio(restore: Int?)
        /// Subtitle preferences, remembered subtitles and offset, else the subtitle automatic.
        case subtitleAutomatic
        /// Query subtitle addons.
        case addonSubtitles
        /// Jump to the synced fraction (Trakt/Simkl); nil = nothing to jump to.
        case seek(fraction: Double?)
        /// Start or continue playback (unless the system holds it); logs „Spielt ·“ on the whole start.
        case play
    }

    /// The whole start has been delivered once in this session.
    public private(set) var startCompleted = false
    /// The fraction jump has arrived (playback ran at the target); it is never repeated afterwards.
    public private(set) var seekExecuted = false

    public init() {}

    /// Steps after a successful load. `isFirst`: the load comes from the start path, which always runs the whole
    /// start (it only runs again while the start is unfinished). `remembered`: the audio track active before the
    /// reload. `pendingFraction`: the synced fraction to jump to (nil = none, e.g. a fixed start position).
    public mutating func afterSuccessfulLoad(isFirst: Bool, remembered: TrackMemory.Entry?,
                                             pendingFraction: Double?) -> [Step] {
        let fraction = seekExecuted ? nil : pendingFraction
        if isFirst || !startCompleted {
            startCompleted = true
            return [.placeholderCheck, .selectAudio(restore: nil), .subtitleAutomatic, .addonSubtitles,
                    .seek(fraction: fraction), .play]
        }
        var steps: [Step] = [.selectAudio(restore: remembered?.audioID)]
        if let fraction { steps.append(.seek(fraction: fraction)) }
        steps.append(.play)
        return steps
    }

    /// The jump arrived: later loads keep the position instead of jumping again.
    public mutating func noteSeekExecuted() { seekExecuted = true; jumpTarget = nil }

    // MARK: Pending sync jump (fix round 1)

    /// What the view does with the pending sync jump on this observation.
    public enum JumpAction: Sendable, Equatable {
        /// Nothing now (audio reload or engine busy, or settling after a seek, or no jump pending).
        case wait
        /// Issue the jump.
        case seek(Double)
        /// The jump did not land: issue it once more (log `player: Sprung wiederholt`).
        case retry(Double)
        /// Playback is at the target.
        case arrived
        /// Not landed after the retry or after `jumpGiveUpSeconds`: stop holding progress.
        case gaveUp
    }

    /// After a seek, wait this long (engine idle) before judging it lost.
    public static let jumpSettleSeconds: Double = 3
    /// Hard limit from planning: then the jump is given up, so progress saving never stays blocked.
    public static let jumpGiveUpSeconds: Double = 60
    /// The jump counts as landed at or behind target minus this (keyframe seeks land a little early).
    public static let jumpTolerance: Double = 15

    /// Target (seconds) of the planned, not yet landed jump; nil = none.
    public private(set) var jumpTarget: Double?
    private var jumpPlannedAt: Double = 0
    private var jumpIssuedAt: Double?
    private var jumpIssues = 0

    /// A jump is pending: do not save progress (the synced position would be overwritten by the start position).
    public var holdsProgress: Bool { jumpTarget != nil }

    /// The `seek(fraction:)` step with a known duration: plan the jump (`now` = uptime in seconds).
    public mutating func planJump(target: Double, now: Double) {
        jumpTarget = target; jumpPlannedAt = now; jumpIssuedAt = nil; jumpIssues = 0
    }

    /// Every tick and after planning. The jump waits for the start's audio reload (a seek during it can be lost),
    /// is issued once the engine is idle, and is retried once if it has not landed after `jumpSettleSeconds`.
    /// `busy`: the engine loads or seeks (or the player reloads after an error).
    public mutating func observeJump(audioReloading: Bool, busy: Bool, position: Double, now: Double) -> JumpAction {
        guard let target = jumpTarget else { return .wait }
        if !busy, !audioReloading, position >= target - Self.jumpTolerance { finishJump(); return .arrived }
        if now - jumpPlannedAt >= Self.jumpGiveUpSeconds { finishJump(); return .gaveUp }
        if audioReloading || busy { return .wait }
        guard let issued = jumpIssuedAt else { jumpIssues = 1; jumpIssuedAt = now; return .seek(target) }
        guard now - issued >= Self.jumpSettleSeconds else { return .wait }
        if jumpIssues < 2 { jumpIssues = 2; jumpIssuedAt = now; return .retry(target) }
        finishJump(); return .gaveUp
    }

    /// The user jumped himself (arrows, scrubbing, chapter, skip): drop the pending jump, never repeat it.
    public mutating func userSeeked() { finishJump() }

    private mutating func finishJump() { jumpTarget = nil; jumpIssuedAt = nil; seekExecuted = true }

    /// For the log line `player: Startschritte <list>`, e.g. "selectAudio(restore),play".
    public static func logText(_ steps: [Step]) -> String {
        steps.map { step -> String in
            switch step {
            case .placeholderCheck: "placeholderCheck"
            case .selectAudio(let r): r == nil ? "selectAudio" : "selectAudio(restore)"
            case .subtitleAutomatic: "subtitleAutomatic"
            case .addonSubtitles: "addonSubtitles"
            case .seek(let f): f == nil ? "seek" : "seek(fraction)"
            case .play: "play"
            }
        }.joined(separator: ",")
    }
}

extension TrackMemory {
    /// Task 3.2 (W-A-3): the audio track active before a reload, to choose it again afterwards. Not stored.
    public struct Entry: Sendable, Equatable {
        public var audioID: Int
        /// Language of that track as the engine reported it (nil = unknown).
        public var audioLanguage: String?

        public init(audioID: Int, audioLanguage: String?) {
            self.audioID = audioID; self.audioLanguage = audioLanguage
        }

        /// The track to choose after the reload: the same ID if it still has the same language, else the best
        /// track of that language; nil = keep the engine's choice. A fresh load can renumber the tracks.
        public func track(in tracks: [AudioTrackInfo]) -> AudioTrackInfo? {
            let lang = MediaLabels.languageCode(audioLanguage)
            // Without a known language only the ID counts.
            if let same = tracks.first(where: { $0.id == audioID }),
               lang == nil || MediaLabels.languageCode(same.language) == lang {
                return same
            }
            guard let lang else { return nil }
            let matching = tracks.filter { MediaLabels.languageCode($0.language) == lang }
            guard !matching.isEmpty else { return nil }
            return preferredAudioTrack(matching, priority: [lang])
        }
    }
}
