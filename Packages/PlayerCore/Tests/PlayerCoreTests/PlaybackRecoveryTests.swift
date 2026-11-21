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

@Test func logTextHasNoMessage() {
    let f = PlaybackFailure(kind: "sourceRefused", code: 403, message: "https://host/token123")
    #expect(f.logText == "sourceRefused · 403")
}

// MARK: Leiter

@Test func unknownKeepsLegacyBehaviour() {
    var p = RecoveryPlanner()
    let f = PlaybackFailure(kind: "vodSourceFailed")
    #expect(p.next(for: f, at: 100).1 == .retrySame(delay: 0))
    #expect(p.next(for: f, at: 100).1 == .nextSource)
}

@Test func networkRetriesWithGrowingDelayThenMessage() {
    var p = RecoveryPlanner()
    let f = url(-1005)
    #expect(p.next(for: f, at: 10).1 == .retrySame(delay: 2))
    #expect(p.next(for: f, at: 10).1 == .retrySame(delay: 5))
    #expect(p.next(for: f, at: 10).1 == .retrySame(delay: 10))
    if case .giveUp(let m) = p.next(for: f, at: 10).1 { #expect(m.contains("Verbindung")) } else { Issue.record("kein giveUp") }
}

@Test func expiredLinkReresolvesOnceThenNextSource() {
    var p = RecoveryPlanner()
    #expect(p.next(for: refused(403), at: 50) == (.linkExpired, .reresolve))
    #expect(p.next(for: refused(410), at: 50).1 == .nextSource)
}

@Test func expiredLinkWithoutReresolveGoesToNextSource() {
    var p = RecoveryPlanner(canReresolve: false)
    #expect(p.next(for: refused(403), at: 0).1 == .nextSource)
    var d = RecoveryPlanner(canReresolve: false)
    #expect(d.next(for: refused(500), at: 0).1 == .retrySame(delay: 2))
    #expect(d.next(for: refused(500), at: 0).1 == .nextSource)
}

@Test func rateLimitAndUnsupportedNeverRetry() {
    var p = RecoveryPlanner()
    if case .giveUp = p.next(for: refused(429), at: 0).1 {} else { Issue.record("429 muss Meldung sein") }
    #expect(p.next(for: PlaybackFailure(kind: "hlsFormatUnsupported"), at: 0).1 == .nextSource)
    #expect(p.total == 0)
}

@Test func totalBudgetBoundsMixedFailures() {
    var p = RecoveryPlanner(canReresolve: true)
    p.maxAttempts = 3
    #expect(p.next(for: url(-1005), at: 0).1 == .retrySame(delay: 2))
    #expect(p.next(for: refused(403), at: 0).1 == .reresolve)
    #expect(p.next(for: PlaybackFailure(kind: "vodSourceFailed"), at: 0).1 == .retrySame(delay: 0))
    // Budget leer: Timeout würde neu versuchen, schaltet jetzt weiter; Netz gibt auf.
    #expect(p.next(for: url(-1001), at: 0).1 == .nextSource)
    if case .giveUp = p.next(for: url(-1005), at: 0).1 {} else { Issue.record("Netz ohne Budget muss Meldung sein") }
}

@Test func healthyPlaybackResetsLadder() {
    var p = RecoveryPlanner()
    let f = PlaybackFailure(kind: "vodSourceFailed")
    #expect(p.next(for: f, at: 600).1 == .retrySame(delay: 0))
    p.notePlaying(at: 650)
    #expect(p.total == 1)
    p.notePlaying(at: 720)
    #expect(p.total == 0)
    #expect(p.next(for: f, at: 3000).1 == .retrySame(delay: 0))
}

@Test func resetAllowsManualRetry() {
    var p = RecoveryPlanner()
    let f = PlaybackFailure(kind: "vodSourceFailed")
    _ = p.next(for: f, at: 0)
    p.reset()
    #expect(p.next(for: f, at: 0).1 == .retrySame(delay: 0))
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
    #expect(l.phaseChanged(to: .active, isActiveMedia: false, now: t0.addingTimeInterval(1001)) == .reloadPaused)
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
}
