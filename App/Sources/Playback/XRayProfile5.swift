import Foundation
import AetherFEL
import PlayerCore

/// X0 review R0/I1, R1/N1: the DolbyVisionStillReshaping trait (needed for the paused-frame probe) would otherwise
/// change Dolby Vision Profile 5 playback. Profile 5 keeps its old behaviour here:
/// - no background still ladder (no second reader on the source): `generatesBackgroundScrubPreviews = false`,
///   decided before the first load (the option is read only at session setup; no rebuild ever);
/// - no scrub previews (PlayerScrub.swift checks `profile5KeepsOldPreviews`).
/// Known Profile 5 sources (scheme, host, path) skip the pre-check. An unknown source is probed with the public
/// `AetherEngine.probe` in parallel with the disk cache routing, capped at `profile5ProbeBudget`; a failed or slow
/// probe loads normally (ladder on) and the source is only remembered after the load, for the next play.
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

    /// Disk cache routing (unchanged) plus, in parallel, the Profile 5 pre-check that sets
    /// `o.generatesBackgroundScrubPreviews` before the load.
    func routeCheckingProfile5(_ url: URL, prefs: LoadPrefs, options o: inout LoadOptions) async
        -> (url: URL, session: String?) {
        Self.installXRayEngineLog()
        let key = XRayProbe.sourceKey(url)
        if Self.profile5Sources.contains(key) {
            o.generatesBackgroundScrubPreviews = false
            RemoteLog.info("xray", "P5 bekannt → Hintergrund-Standbilder aus")
            return await DiskCacheProxy.shared.route(url, headers: prefs.headers, settings: prefs.diskCache,
                                                     nativeHLS: prefs.nativeRemoteHLS, reuse: cacheSession)
        }
        let probeOptions = o   // an inout parameter cannot be captured by `async let`
        async let check = Self.probeProfile5(url, options: probeOptions)
        let routed = await DiskCacheProxy.shared.route(url, headers: prefs.headers, settings: prefs.diskCache,
                                                       nativeHLS: prefs.nativeRemoteHLS, reuse: cacheSession)
        let (isP5, ms) = await check
        switch isP5 {
        case true?:
            o.generatesBackgroundScrubPreviews = false
            Self.rememberProfile5(key)
            RemoteLog.info("xray", "P5-Vorprüfung: P5 nach \(ms) ms → Hintergrund-Standbilder aus, Quelle gemerkt")
        case false?:
            break
        case nil:
            RemoteLog.info("xray", "P5-Vorprüfung ohne Ergebnis nach \(ms) ms → normal laden")
        }
        return routed
    }

    /// nil = probe failed, was cancelled or ran past the budget. Only `file`/`http(s)` sources are probed.
    private static func probeProfile5(_ url: URL, options o: LoadOptions) async -> (Bool?, Int) {
        guard let scheme = url.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) else { return (false, 0) }
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
        guard profile5KeepsOldPreviews, !Task.isCancelled, !stopped else { return }
        if o.generatesBackgroundScrubPreviews {
            Self.rememberProfile5(XRayProbe.sourceKey(url))
            RemoteLog.info("xray", "P5 geladen · Hintergrund-Standbilder an (Vorprüfung verpasst) → Quelle fürs nächste Mal gemerkt")
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
