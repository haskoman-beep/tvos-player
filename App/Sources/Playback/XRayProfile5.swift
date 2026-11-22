import Foundation
import AetherFEL
import PlayerCore

/// X0 review R0/I1: the DolbyVisionStillReshaping trait (needed for the paused-frame probe) would otherwise
/// change Dolby Vision Profile 5 playback. Profile 5 keeps its old behaviour here:
/// - no background still ladder (no second reader on the source): `generatesBackgroundScrubPreviews = false`;
/// - no scrub previews (PlayerScrub.swift checks `profile5KeepsOldPreviews`).
/// The ladder option is decided at session setup, so a source is known as Profile 5 only after its first load.
/// Known sources load with the ladder off; a new Profile 5 source is corrected once, right after its load and
/// before playback starts, and remembered (by scheme, host and path) for later loads.
/// The held picture on an audio switch / reload has no engine switch and goes through CPU reshaping; the
/// engine's line is forwarded as `xray: P5 gehaltenes Bild per CPU (… ms)`.
extension AetherBackend {
    private static let profile5Key = "xray.profile5Sources"

    private static var profile5Sources: RecentKeySet {
        get {
            guard let d = UserDefaults.standard.data(forKey: profile5Key),
                  let s = try? JSONDecoder().decode(RecentKeySet.self, from: d) else { return RecentKeySet() }
            return s
        }
        set { if let d = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(d, forKey: profile5Key) } }
    }

    /// Load-time value of `generatesBackgroundScrubPreviews`: off for sources already known as Profile 5.
    static func backgroundScrubPreviews(for url: URL) -> Bool {
        !profile5Sources.contains(XRayProbe.sourceKey(url))
    }

    /// True for Dolby Vision Profile 5 (and AV1 10.0): no scrub previews, as before the trait.
    var profile5KeepsOldPreviews: Bool { XRayProbe.isProfile5(dvProfile: engine.sourceDVProfile) }

    /// After `engine.load`: remember a Profile 5 source and, if its session still runs the ladder, rebuild it once
    /// with the ladder off. A failed correction is logged and playback goes on (the ladder is only extra reads).
    func settleProfile5(url: URL, options o: LoadOptions) async {
        Self.installHeldPictureLog()
        guard profile5KeepsOldPreviews, !Task.isCancelled, !stopped else { return }
        var set = Self.profile5Sources
        set.insert(XRayProbe.sourceKey(url))
        Self.profile5Sources = set
        guard o.generatesBackgroundScrubPreviews else { return }
        RemoteLog.info("xray", "P5 erkannt → Hintergrund-Standbilder aus (einmaliger Neuaufbau, Quelle gemerkt)")
        do { try await engine.reloadAtCurrentPosition { $0.generatesBackgroundScrubPreviews = false } }
        catch { RemoteLog.error("xray", "P5: Neuaufbau ohne Hintergrund-Standbilder fehlgeschlagen (\(error))") }
    }

    private static var heldPictureLogInstalled = false
    /// Chains onto the app's engine log handler (installEngineLog) once.
    private static func installHeldPictureLog() {
        guard !heldPictureLogInstalled else { return }
        heldPictureLogInstalled = true
        let previous = EngineLog.structuredHandler
        EngineLog.structuredHandler = { line, cat, level in
            previous?(line, cat, level)
            if let x = XRayProbe.heldPictureLine(engineLine: line) { Task { @MainActor in RemoteLog.info("xray", x) } }
        }
    }
}
