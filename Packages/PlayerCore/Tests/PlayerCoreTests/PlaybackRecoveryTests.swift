import Foundation
import Testing
@testable import PlayerCore

private func refused(_ status: Int) -> PlaybackFailure { PlaybackFailure(kind: "sourceRefused", code: status) }
private func url(_ code: Int, kind: String = "vodSourceFailed") -> PlaybackFailure {
    PlaybackFailure(kind: kind, domain: "NSURLErrorDomain", code: code)
}

// MARK: Einordnung

@Test func classifyHTTPStatus() {
    #expect(PlaybackErrorClassifier.classify(refused(403)) == .linkExpired)
    #expect(PlaybackErrorClassifier.classify(refused(410)) == .linkExpired)
    #expect(PlaybackErrorClassifier.classify(refused(404)) == .linkExpired)
    #expect(PlaybackErrorClassifier.classify(refused(401)) == .debrid)
    #expect(PlaybackErrorClassifier.classify(refused(502)) == .debrid)
    #expect(PlaybackErrorClassifier.classify(refused(503)) == .rateLimited)
    #expect(PlaybackErrorClassifier.classify(PlaybackFailure(kind: "sourceRateLimited", code: 429)) == .rateLimited)
    #expect(PlaybackErrorClassifier.classify(refused(418)) == .unknown)
}

@Test func classifyURLErrorsAnyKind() {
    #expect(PlaybackErrorClassifier.classify(url(-1005)) == .network)
    #expect(PlaybackErrorClassifier.classify(url(-1009, kind: "nativeItemFailed")) == .network)
    #expect(PlaybackErrorClassifier.classify(url(-1001, kind: "sourceOpenFailed")) == .timeout)
    #expect(PlaybackErrorClassifier.classify(url(-1004)) == .hostUnreachable)
    #expect(PlaybackErrorClassifier.classify(url(-1202)) == .certificate)
    #expect(PlaybackErrorClassifier.classify(url(-999)) == .unknown)
}

@Test func classifyKinds() {
    #expect(PlaybackErrorClassifier.classify(PlaybackFailure(kind: "dolbyVisionRequiresHardware")) == .unsupported)
    #expect(PlaybackErrorClassifier.classify(PlaybackFailure(kind: "audioBridgeProducedNoOutput")) == .unsupported)
    #expect(PlaybackErrorClassifier.classify(PlaybackFailure(kind: "noPlayableTrackWithinBudget")) == .timeout)
    #expect(PlaybackErrorClassifier.classify(PlaybackFailure(kind: "sourceCertificateRejected", code: -1202)) == .certificate)
    #expect(PlaybackErrorClassifier.classify(PlaybackFailure(kind: "storageExhausted")) == .storage)
    #expect(PlaybackErrorClassifier.classify(PlaybackFailure(kind: "sourceOpenFailed", ffmpegCode: -1_094_995_529)) == .unsupported)
    #expect(PlaybackErrorClassifier.classify(PlaybackFailure(kind: "sourceOpenFailed")) == .unknown)
    #expect(PlaybackErrorClassifier.classify(PlaybackFailure(kind: "vodSourceFailed")) == .unknown)
    // Nur Text, keine Art (z. B. anderes Backend): wie bisher.
    #expect(PlaybackErrorClassifier.classify(PlaybackFailure(message: "403 Forbidden")) == .unknown)
}

@Test func classifyAVPlayerErrors() {
    #expect(PlaybackErrorClassifier.classify(PlaybackFailure(kind: "nativeItemFailed", domain: "CoreMediaErrorDomain", code: -12660)) == .linkExpired)
    #expect(PlaybackErrorClassifier.classify(PlaybackFailure(kind: "nativeItemFailed", domain: "CoreMediaErrorDomain", code: -12938)) == .linkExpired)
    #expect(PlaybackErrorClassifier.classify(PlaybackFailure(kind: "nativeItemFailed", domain: "AVFoundationErrorDomain", code: -11800,
                                                             underlyingURLCode: -1009)) == .network)
    #expect(PlaybackErrorClassifier.classify(PlaybackFailure(kind: "nativeItemFailed", domain: "AVFoundationErrorDomain", code: -11800)) == .unknown)
}

// Task 3.5 (W-A-5): transport errors the classifier does not know are not remembered for 8 h.
@Test func unknownTransportErrorIsNotRemembered() {
    let posix = PlaybackFailure(kind: "vodSourceFailed", domain: "NSPOSIXErrorDomain", code: 54)
    #expect(PlaybackErrorClassifier.classify(posix) == .unknown)
    #expect(SourceVerdict.forNextSource(.unknown, failure: posix, reachedFirstFrame: true) == nil)
    let parse = url(-1017)
    #expect(PlaybackErrorClassifier.classify(parse) == .unknown)
    #expect(SourceVerdict.forNextSource(.unknown, failure: parse, reachedFirstFrame: false) == nil)
    let cf = PlaybackFailure(kind: "vodSourceFailed", domain: "kCFErrorDomainCFNetwork", code: 303)
    #expect(SourceVerdict.forNextSource(.unknown, failure: cf, reachedFirstFrame: true) == nil)
}

@Test func avFoundationWithUnknownURLCodeIsNotRemembered() {
    let f = PlaybackFailure(kind: "nativeItemFailed", domain: "AVFoundationErrorDomain", code: -11800, underlyingURLCode: -1017)
    #expect(PlaybackErrorClassifier.classify(f) == .unknown)
    #expect(SourceVerdict.forNextSource(.unknown, failure: f, reachedFirstFrame: true) == nil)
    // Without a URL error below, -11800 is not known to be transport: remembered as before.
    let plain = PlaybackFailure(kind: "nativeItemFailed", domain: "AVFoundationErrorDomain", code: -11800)
    #expect(SourceVerdict.forNextSource(.unknown, failure: plain, reachedFirstFrame: true) == .failed(.unknown))
}

@Test func classifiedSourceErrorsAreStillRemembered() {
    #expect(SourceVerdict.forNextSource(.linkExpired, failure: refused(403), reachedFirstFrame: true) == .failed(.linkExpired))
    let decoder = PlaybackFailure(kind: "vodSourceFailed")
    #expect(SourceVerdict.forNextSource(.unknown, failure: decoder, reachedFirstFrame: true) == .failed(.unknown))
    let dead = PlaybackFailure(kind: LoadWatchdog.Verdict.start.kind)
    #expect(SourceVerdict.forNextSource(.timeout, failure: dead, reachedFirstFrame: false) == .deadStart)
    var b = FailedLinkBook()
    let s = StreamItem(name: "A", url: "https://x/token", behaviorHints: StreamBehaviorHints(filename: "a.mkv"))
    if let v = SourceVerdict.forNextSource(.unknown, failure: decoder, reachedFirstFrame: true) { b.apply(v, stream: s, title: "tt1") }
    #expect(b.isRecentlyFailed(s, title: "tt1"))
}

@Test func logTextHasNoMessage() {
    let f = PlaybackFailure(kind: "sourceRefused", code: 403, message: "https://host/token123")
    #expect(f.logText == "sourceRefused · 403")
}

// MARK: Leiter

@Test func unknownKeepsLegacyBehaviour() {
    var p = RecoveryPlanner()
    let f = PlaybackFailure(kind: "vodSourceFailed")
    #expect(p.next(for: f).1 == .retrySame(delay: 0))
    #expect(p.next(for: f).1 == .nextSource)
}

@Test func networkRetriesWithGrowingDelayThenMessage() {
    var p = RecoveryPlanner()
    let f = url(-1005)
    #expect(p.next(for: f).1 == .retrySame(delay: 2))
    #expect(p.next(for: f).1 == .retrySame(delay: 5))
    #expect(p.next(for: f).1 == .retrySame(delay: 10))
    if case .giveUp(let m) = p.next(for: f).1 { #expect(m.contains("Verbindung")) } else { Issue.record("kein giveUp") }
}

@Test func expiredLinkReresolvesOnceThenNextSource() {
    var p = RecoveryPlanner()
    #expect(p.next(for: refused(403)) == (.linkExpired, .reresolve))
    #expect(p.next(for: refused(410)).1 == .nextSource)
}

@Test func expiredLinkWithoutReresolveGoesToNextSource() {
    var p = RecoveryPlanner(canReresolve: false)
    #expect(p.next(for: refused(403)).1 == .nextSource)
    var d = RecoveryPlanner(canReresolve: false)
    #expect(d.next(for: refused(500)).1 == .retrySame(delay: 2))
    #expect(d.next(for: refused(500)).1 == .nextSource)
}

@Test func rateLimitAndUnsupportedNeverRetry() {
    var p = RecoveryPlanner()
    if case .giveUp = p.next(for: refused(429)).1 {} else { Issue.record("429 muss Meldung sein") }
    #expect(p.next(for: PlaybackFailure(kind: "hlsFormatUnsupported")).1 == .nextSource)
    #expect(p.total == 0)
}

@Test func totalBudgetBoundsMixedFailures() {
    var p = RecoveryPlanner(canReresolve: true)
    p.maxAttempts = 3
    #expect(p.next(for: url(-1005)).1 == .retrySame(delay: 2))
    #expect(p.next(for: refused(403)).1 == .reresolve)
    #expect(p.next(for: PlaybackFailure(kind: "vodSourceFailed")).1 == .retrySame(delay: 0))
    // Budget leer: Timeout würde neu versuchen, schaltet jetzt weiter; Netz gibt auf.
    #expect(p.next(for: url(-1001)).1 == .nextSource)
    if case .giveUp = p.next(for: url(-1005)).1 {} else { Issue.record("Netz ohne Budget muss Meldung sein") }
}

@Test func healthyPlaybackResetsLadder() {
    var p = RecoveryPlanner()
    let f = PlaybackFailure(kind: "vodSourceFailed")
    #expect(p.next(for: f).1 == .retrySame(delay: 0))
    for _ in 0..<119 { p.notePlaying() }
    #expect(p.total == 1)
    p.notePlaying()
    #expect(p.total == 0)
    #expect(p.next(for: f).1 == .retrySame(delay: 0))
}

@Test func failureAtStartWithResumeDoesNotResetAfterOneTick() {
    // Fehler vor dem ersten Bild (Position 0), Neuladen springt an start 3000: ein Takt setzt nichts zurück.
    var p = RecoveryPlanner()
    let f = PlaybackFailure(kind: "vodSourceFailed")
    #expect(p.next(for: f).1 == .retrySame(delay: 0))
    p.notePlaying()
    #expect(p.total == 1)
    #expect(p.next(for: f).1 == .nextSource)
}

@Test func seekDoesNotResetLadder() {
    // Ein Sprung um > 120 s ist keine Spielzeit: nur gezählte Takte zählen.
    var p = RecoveryPlanner()
    _ = p.next(for: url(-1005))
    for _ in 0..<5 { p.notePlaying() }
    #expect(p.total == 1)
    #expect(p.playedSinceAttempt == 5)
}

@Test func budgetWithoutReresolve() {
    var p = RecoveryPlanner(canReresolve: false)
    p.maxAttempts = 2
    #expect(p.next(for: refused(500)).1 == .retrySame(delay: 2))   // Debrid ohne Auflöser: neu versuchen
    #expect(p.next(for: url(-1004)).1 == .retrySame(delay: 2))
    #expect(p.next(for: PlaybackFailure(kind: "vodSourceFailed")).1 == .nextSource)  // Budget leer
    #expect(p.next(for: refused(403)).1 == .nextSource)
    #expect(p.total == 2)
}

@Test func resetAllowsManualRetry() {
    var p = RecoveryPlanner()
    let f = PlaybackFailure(kind: "vodSourceFailed")
    _ = p.next(for: f)
    p.reset()
    #expect(p.next(for: f).1 == .retrySame(delay: 0))
}

// MARK: Lebenszyklus

@Test func inactivePausesPlayingAndHolds() {
    var l = PlaybackLifecycle()
    #expect(l.phaseChanged(to: .inactive, isActiveMedia: true) == .pause)
    #expect(l.holdsPlayback)
    // Kurz inaktiv (Kontrollzentrum) und zurück: nichts neu aufbauen, pausiert bleiben.
    #expect(l.phaseChanged(to: .active, isActiveMedia: false) == .none)
    #expect(l.holdsPlayback)
    l.userResumed()
    #expect(!l.holdsPlayback)
}

@Test func duplicatePhaseReportsAreHarmless() {
    var l = PlaybackLifecycle()
    let t0 = Date(timeIntervalSince1970: 1_000)
    #expect(l.phaseChanged(to: .inactive, isActiveMedia: true, now: t0) == .pause)
    #expect(l.phaseChanged(to: .inactive, isActiveMedia: true, now: t0) == .none)
    #expect(l.phaseChanged(to: .active, isActiveMedia: false, now: t0) == .none)
    #expect(l.phaseChanged(to: .active, isActiveMedia: false, now: t0) == .none)
    #expect(l.phaseChanged(to: .background, isActiveMedia: false, now: t0) == .none)
    #expect(l.phaseChanged(to: .background, isActiveMedia: false, now: t0.addingTimeInterval(300)) == .none)
    #expect(l.backgroundSince == t0)
    #expect(l.phaseChanged(to: .active, isActiveMedia: false, now: t0.addingTimeInterval(400)) == .returnedFromBackground)
    #expect(l.phaseChanged(to: .active, isActiveMedia: false, now: t0.addingTimeInterval(401)) == .none)
}

@Test func pausedByUserIsNotHeld() {
    var l = PlaybackLifecycle()
    #expect(l.phaseChanged(to: .inactive, isActiveMedia: false) == .none)
    #expect(!l.holdsPlayback)
}

@Test func backgroundReturnReloadsPaused() {
    var l = PlaybackLifecycle()
    let t0 = Date(timeIntervalSince1970: 1_000)
    #expect(l.phaseChanged(to: .inactive, isActiveMedia: true, now: t0) == .pause)
    #expect(l.phaseChanged(to: .background, isActiveMedia: false, now: t0.addingTimeInterval(600)) == .none)
    #expect(!l.shouldClose(now: t0.addingTimeInterval(900)))
    #expect(l.phaseChanged(to: .inactive, isActiveMedia: false, now: t0.addingTimeInterval(1000)) == .none)
    #expect(l.phaseChanged(to: .active, isActiveMedia: false, now: t0.addingTimeInterval(1001)) == .returnedFromBackground)
    #expect(l.backgroundSince == nil)
    #expect(l.holdsPlayback)
}

@Test func longBackgroundCloses() {
    var l = PlaybackLifecycle()
    let t0 = Date(timeIntervalSince1970: 1_000)
    #expect(l.phaseChanged(to: .background, isActiveMedia: true, now: t0) == .pause)
    #expect(l.shouldClose(now: t0.addingTimeInterval(601)))
    #expect(l.phaseChanged(to: .active, isActiveMedia: false, now: t0.addingTimeInterval(601)) == .close)
}

// MARK: Link neu auflösen

@Test func exactURLFindsSameFileOnly() {
    let old = StreamItem(name: "TB 2160p", description: "⚡ Film.2160p.mkv", url: "https://x/alt")
    let last = LastSource(stream: old, addon: "AIO", contentID: "tt1")
    let fresh = StreamItem(name: "TB 2160p", description: "⚡ Film.2160p.mkv", url: "https://x/neu")
    let other = StreamItem(name: "TB 1080p", description: "⚡ Film.1080p.mkv", url: "https://x/b")
    #expect(last.exactURL(in: [other, fresh])?.absoluteString == "https://x/neu")
    #expect(last.exactURL(in: [other]) == nil)
    // Nicht abspielbare Treffer (kein http) zählen nicht.
    let magnet = StreamItem(name: "TB 2160p", description: "⚡ Film.2160p.mkv", url: "magnet:?xt=1")
    #expect(last.exactURL(in: [magnet]) == nil)
    // Gleiche Datei bei zwei Diensten: gleicher Name zuerst.
    let otherService = StreamItem(name: "RD 2160p", description: "⚡ Film.2160p.mkv", url: "https://y/rd")
    #expect(last.exactURL(in: [otherService, fresh])?.absoluteString == "https://x/neu")
    #expect(last.exactURL(in: [otherService])?.absoluteString == "https://y/rd")
    // Leerer Fingerabdruck trifft nie (sonst jede Quelle ohne Beschreibung).
    let blank = LastSource(stream: StreamItem(name: "TB", url: "https://x/a"), addon: "AIO", contentID: "tt1")
    #expect(blank.exactURL(in: [StreamItem(name: "TB", url: "https://x/b")]) == nil)
}
