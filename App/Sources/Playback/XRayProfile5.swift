import Foundation
import AetherFEL
import PlayerCore

/// X0 review R0/I1, R1/N1: the DolbyVisionStillReshaping trait (needed for the paused-frame probe) would otherwise
/// change Dolby Vision Profile 5 playback. Profile 5 keeps its old behaviour here:
/// - no background still ladder (no second reader on the source): `generatesBackgroundScrubPreviews = false`,
///   decided before the first load (the option is read only at session setup; no rebuild ever);
/// - no scrub previews (PlayerScrub.swift checks `profile5KeepsOldPreviews`).
/// Known Profile 5 sources (scheme, host, path; persisted) load with the ladder off and skip the pre-check. With
/// X-Ray on, an unknown file source is probed with the public `AetherEngine.probe` after the disk cache routing
/// (local proxy URL when cached), capped at `profile5ProbeBudget`; results are remembered (non-P5 for this app run),
/// a failed or slow probe loads as before. With X-Ray off there is no probe and no extra open.
/// Accepted trade-off (user, 22.11.): the held picture on an audio switch / reload goes through CPU reshaping; the
/// engine's line is forwarded as `xray: P5 gehaltenes Bild per CPU (… ms)`. `[StillLadder]` lines are forwarded too,
/// so the device check "no ladder on P5" can fail.
extension AetherBackend {
    private static let profile5Key = "xray.profile5Sources"
    static let profile5ProbeBudget: TimeInterval = 1.5

    private static var profile5Sources: RecentKeySet {
        get {
            guard let d = UserDefaults.standard.data(forKey: profile5Key),
                  let s = try? JSONDecoder().decode(RecentKeySet.self, from: d) else { return RecentKeySet() }
            return s
        }
        set { if let d = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(d, forKey: profile5Key) } }
    }

    /// Remembers a Profile 5 source; writes only when the key is new.
    private static func rememberProfile5(_ key: String) {
        var set = profile5Sources
        if set.insert(key) { profile5Sources = set }
    }

    /// True for Dolby Vision Profile 5 (and AV1 10.0): no scrub previews, as before the trait.
    var profile5KeepsOldPreviews: Bool { XRayProbe.isProfile5(dvProfile: engine.sourceDVProfile) }

    /// Sources checked and found not to be Profile 5, this app run only (LRU, 200): each is probed once per run.
    private static var notProfile5 = RecentKeySet()

    /// Disk cache routing (unchanged, always first), then the Profile 5 decision for
    /// `o.generatesBackgroundScrubPreviews` (XRayProbe.profile5Plan). The probe runs only with X-Ray on, for an
    /// unknown file source; with a cache session it reads the local proxy URL, so the origin sees no extra open.
    func routeCheckingProfile5(_ url: URL, prefs: LoadPrefs, options o: inout LoadOptions) async
        -> (url: URL, session: String?) {
        Self.installXRayEngineLog()
        let routed = await DiskCacheProxy.shared.route(url, headers: prefs.headers, settings: prefs.diskCache,
                                                       nativeHLS: prefs.nativeRemoteHLS, reuse: cacheSession)
        let key = XRayProbe.sourceKey(url)
        let known: Bool? = Self.profile5Sources.contains(key) ? true : (Self.notProfile5.contains(key) ? false : nil)
        let enabled = UserDefaults.standard.bool(forKey: XRayProbe.settingKey)
        switch XRayProbe.profile5Plan(xrayEnabled: enabled, known: known, url: url, nativeHLS: prefs.nativeRemoteHLS) {
        case .asBefore:
            break
        case .ladderOff:
            o.generatesBackgroundScrubPreviews = false
            RemoteLog.info("xray", "P5 bekannt → Hintergrund-Standbilder aus")
        case .probe:
            guard !Task.isCancelled, !stopped else { break }
            let (isP5, ms) = await Self.probeProfile5(routed.url, options: o)
            if isP5 == true { o.generatesBackgroundScrubPreviews = false; Self.rememberProfile5(key) }
            if isP5 == false { Self.notProfile5.insert(key) }
            RemoteLog.info("xray", XRayProbe.profile5ProbeLine(isProfile5: isP5, ms: ms, viaCache: routed.session != nil))
        }
        return routed
    }

    /// nil = probe failed, was cancelled or ran past the budget (`profile5Plan` already limits the schemes).
    private static func probeProfile5(_ url: URL, options o: LoadOptions) async -> (Bool?, Int) {
        let begin = ContinuousClock.now
        let cancel = ProbeCancellation()
        let limits = ProbeLimits(timeBudget: profile5ProbeBudget)
        let result: SourceProbe? = await withTaskCancellationHandler {
            await Task.detached(priority: .userInitiated) {
                try? AetherEngine.probe(url: url, options: o, limits: limits, cancellation: cancel)
            }.value
        } onCancel: { cancel.cancel() }
        let d = ContinuousClock.now - begin
        let ms = Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000)
        return (result.map { XRayProbe.isProfile5(dvProfile: $0.dvProfile) }, ms)
    }

    /// After `engine.load`: no rebuild. Logs the ladder state of a Profile 5 session and remembers a Profile 5
    /// source the pre-check missed, so its next play loads with the ladder off.
    func settleProfile5(url: URL, options o: LoadOptions) async {
        guard !Task.isCancelled, !stopped else { return }
        guard profile5KeepsOldPreviews else {
            // Opened anyway: no probe needed for this source again this run.
            Self.notProfile5.insert(XRayProbe.sourceKey(url))
            return
        }
        if o.generatesBackgroundScrubPreviews {
            Self.rememberProfile5(XRayProbe.sourceKey(url))
            RemoteLog.info("xray", "P5 geladen · Hintergrund-Standbilder an (nicht vorgeprüft) → Quelle fürs nächste Mal gemerkt")
        } else {
            RemoteLog.info("xray", "P5 geladen · Hintergrund-Standbilder aus")
        }
    }

    private static var xrayEngineLogInstalled = false
    /// Chains onto the app's engine log handler (installEngineLog) once: held picture and still ladder lines.
    private static func installXRayEngineLog() {
        guard !xrayEngineLogInstalled else { return }
        xrayEngineLogInstalled = true
        let previous = EngineLog.structuredHandler
        EngineLog.structuredHandler = { line, cat, level in
            previous?(line, cat, level)
            if let x = XRayProbe.forwardedLine(engineLine: line) {
                Task { @MainActor in RemoteLog.info("xray", LogRedact.text(x)) }
            }
        }
    }
}
