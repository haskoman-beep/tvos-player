import Foundation
import Testing
@testable import PlayerCore

// Task 3.2 (W-A-1, W-A-3, W-A-4, W-B-4, W-A-9): start steps after every successful load.

private let fullNoFraction: [StartSequence.Step] = [
    .placeholderCheck, .selectAudio(restore: nil), .subtitleAutomatic, .addonSubtitles, .seek(fraction: nil), .play,
]
private let english = TrackMemory.Entry(audioID: 2, audioLanguage: "en")

@Test func startSequenceFirstLoadDeliversAllSteps() {
    var s = StartSequence()
    #expect(s.afterSuccessfulLoad(isFirst: true, remembered: nil, pendingFraction: nil) == fullNoFraction)
    var t = StartSequence()
    #expect(t.afterSuccessfulLoad(isFirst: true, remembered: nil, pendingFraction: 0.6) == [
        .placeholderCheck, .selectAudio(restore: nil), .subtitleAutomatic, .addonSubtitles, .seek(fraction: 0.6), .play,
    ])
    #expect(t.startCompleted)
}

/// W-A-1: the first load failed, the ladder repaired it. Its first successful load runs the whole start.
@Test func startSequenceFirstSuccessFromLadderDeliversAllSteps() {
    var s = StartSequence()
    #expect(s.afterSuccessfulLoad(isFirst: false, remembered: english, pendingFraction: nil) == fullNoFraction)
    // Afterwards only the short list.
    #expect(s.afterSuccessfulLoad(isFirst: false, remembered: english, pendingFraction: nil)
        == [.selectAudio(restore: 2), .play])
}

/// W-A-3: every later load restores the last chosen audio track.
@Test func startSequenceLaterLoadRestoresAudioAndPlays() {
    var s = StartSequence()
    _ = s.afterSuccessfulLoad(isFirst: true, remembered: nil, pendingFraction: nil)
    #expect(s.afterSuccessfulLoad(isFirst: false, remembered: english, pendingFraction: nil)
        == [.selectAudio(restore: 2), .play])
    #expect(s.afterSuccessfulLoad(isFirst: false, remembered: nil, pendingFraction: nil)
        == [.selectAudio(restore: nil), .play])
}

/// W-A-4 / W-B-4: the fraction jump is repeated after a reload until it has been executed.
@Test func startSequenceRepeatsJumpUntilExecuted() {
    var s = StartSequence()
    _ = s.afterSuccessfulLoad(isFirst: true, remembered: nil, pendingFraction: 0.6)
    #expect(s.afterSuccessfulLoad(isFirst: false, remembered: english, pendingFraction: 0.6)
        == [.selectAudio(restore: 2), .seek(fraction: 0.6), .play])
    s.noteSeekExecuted()
    #expect(s.seekExecuted)
    #expect(s.afterSuccessfulLoad(isFirst: false, remembered: english, pendingFraction: 0.6)
        == [.selectAudio(restore: 2), .play])
}

/// Once the jump is executed, even a full start carries no fraction any more (no jump back to it).
@Test func startSequenceExecutedJumpIsNeverRepeated() {
    var s = StartSequence()
    s.noteSeekExecuted()
    #expect(s.afterSuccessfulLoad(isFirst: true, remembered: nil, pendingFraction: 0.6) == fullNoFraction)
    // The start path (loadAndStart) always runs the whole start.
    #expect(s.afterSuccessfulLoad(isFirst: true, remembered: nil, pendingFraction: nil) == fullNoFraction)
}

@Test func startSequenceLogText() {
    #expect(StartSequence.logText(fullNoFraction) == "placeholderCheck,selectAudio,subtitleAutomatic,addonSubtitles,seek,play")
    #expect(StartSequence.logText([.selectAudio(restore: 3), .play]) == "selectAudio(restore),play")
    #expect(StartSequence.logText([.selectAudio(restore: nil), .seek(fraction: 0.5), .play])
        == "selectAudio,seek(fraction),play")
}

/// W-A-3: the remembered track by ID when it is still the same language, else the best of that language.
@Test func startSequenceRestoredAudioTrack() {
    let de = AudioTrackInfo(id: 1, language: "ger", channels: 6, codec: "ac3")
    let en = AudioTrackInfo(id: 2, language: "eng", channels: 2, codec: "aac")
    let en51 = AudioTrackInfo(id: 3, language: "en", channels: 6, codec: "eac3")
    #expect(english.track(in: [de, en, en51]) == en)
    // After a fresh load the IDs differ: ID 2 is now German → the best English track.
    let shuffled = [AudioTrackInfo(id: 2, language: "de"), AudioTrackInfo(id: 5, language: "en", channels: 2),
                    AudioTrackInfo(id: 6, language: "en", channels: 6)]
    #expect(english.track(in: shuffled)?.id == 6)
    // Language not there: keep the engine's choice.
    #expect(english.track(in: [de]) == nil)
    // Without a language only the ID counts.
    #expect(TrackMemory.Entry(audioID: 1, audioLanguage: nil).track(in: [de, en]) == de)
    #expect(TrackMemory.Entry(audioID: 9, audioLanguage: nil).track(in: [de, en]) == nil)
}

/// W-A-9: the ladder counts only time in which the position moves on as healthy (not buffering at one spot).
@Test func recoveryCountsOnlyProgressingPositionAsHealthy() {
    var p = RecoveryPlanner()
    _ = p.next(for: PlaybackFailure(kind: "vodSourceFailed"))
    #expect(p.total == 1)
    p.notePlaying(position: 50)
    for _ in 0..<300 { p.notePlaying(position: 50) }   // buffering: state "playing", position stands
    #expect(p.total == 1)
    #expect(p.playedSinceAttempt == 0)
    for i in 1...119 { p.notePlaying(position: 50 + Double(i)) }
    #expect(p.playedSinceAttempt == 119)
    #expect(p.total == 1)
    p.notePlaying(position: 170)
    #expect(p.total == 0)   // 120 s of real playing: the ladder starts again
}

// MARK: Fix round 1: the sync jump waits for the start's audio reload, retries once, holds progress until done.

private func planned(_ target: Double = 3000) -> StartSequence {
    var s = StartSequence()
    _ = s.afterSuccessfulLoad(isFirst: true, remembered: nil, pendingFraction: 0.6)
    s.planJump(target: target, now: 0)
    return s
}

@Test func startJumpWaitsForAudioReload() {
    var s = planned()
    #expect(s.holdsProgress)
    #expect(s.observeJump(audioReloading: true, busy: false, position: 0, now: 0) == .wait)
    #expect(s.observeJump(audioReloading: true, busy: true, position: 0, now: 2) == .wait)
    #expect(s.observeJump(audioReloading: false, busy: true, position: 0, now: 4) == .wait)
    #expect(s.observeJump(audioReloading: false, busy: false, position: 1, now: 5) == .seek(3000))
    #expect(s.holdsProgress)
}

@Test func startJumpArrives() {
    var s = planned()
    #expect(s.observeJump(audioReloading: false, busy: false, position: 0, now: 0) == .seek(3000))
    #expect(s.observeJump(audioReloading: false, busy: true, position: 0, now: 1) == .wait)
    #expect(s.observeJump(audioReloading: false, busy: false, position: 2992, now: 2) == .arrived)
    #expect(!s.holdsProgress)
    #expect(s.seekExecuted)
    #expect(s.afterSuccessfulLoad(isFirst: false, remembered: nil, pendingFraction: 0.6) == [.selectAudio(restore: nil), .play])
    #expect(s.observeJump(audioReloading: false, busy: false, position: 0, now: 3) == .wait)
}

@Test func startJumpRetriesOnceThenGivesUp() {
    var s = planned()
    #expect(s.observeJump(audioReloading: false, busy: false, position: 0, now: 0) == .seek(3000))
    // Jump lost (e.g. the audio reload restored the old position): no retry before the settle time.
    #expect(s.observeJump(audioReloading: false, busy: false, position: 1, now: 2) == .wait)
    #expect(s.observeJump(audioReloading: false, busy: false, position: 3, now: 3) == .retry(3000))
    #expect(s.holdsProgress)
    #expect(s.observeJump(audioReloading: false, busy: false, position: 4, now: 5) == .wait)
    #expect(s.observeJump(audioReloading: false, busy: false, position: 6, now: 6) == .gaveUp)
    #expect(!s.holdsProgress)
    #expect(s.seekExecuted)   // not repeated on later loads
}

@Test func startJumpGivesUpAfterLimitEvenWhileWaiting() {
    var s = planned()
    #expect(s.observeJump(audioReloading: true, busy: true, position: 0, now: 59) == .wait)
    #expect(s.observeJump(audioReloading: true, busy: true, position: 0, now: StartSequence.jumpGiveUpSeconds) == .gaveUp)
    #expect(!s.holdsProgress)
}

@Test func startJumpDroppedByUserSeek() {
    var s = planned()
    #expect(s.observeJump(audioReloading: false, busy: false, position: 0, now: 0) == .seek(3000))
    s.userSeeked()
    #expect(!s.holdsProgress)
    #expect(s.observeJump(audioReloading: false, busy: false, position: 100, now: 5) == .wait)
    #expect(s.afterSuccessfulLoad(isFirst: false, remembered: nil, pendingFraction: 0.6) == [.selectAudio(restore: nil), .play])
}
