import SwiftUI
import Vision
import CoreGraphics
import os
import AetherFEL
import PlayerCore

// Wave X0 (spike): with "Gesichter bei Pause prüfen" on (System › Erweitert › Diagnose), a pause grabs the paused
// frame from the engine, runs Vision face rectangles, landmarks and capture quality on it and logs `xray:` lines.
// Debug only: nothing is shown, nothing is stored, nothing leaves the device except the log lines.
//
// Rules (brief X0): never block or slow the pause (the probe starts after `XRayProbe.settleDelay` in its own task,
// Vision runs detached at utility priority); cancel on resume, scrub, track panel, error or leave; release the still
// decoders after a finished probe; drop the frame as soon as Vision is done.

/// Hook for PlayerControls (one line in PlayerScreen). `playing` and `blocked` are passed as values so a change
/// re-runs this modifier; `blocked` = leaving, track panel open, scrubbing or a failure notice.
struct XRayProbeHook<E: PlaybackEngine>: ViewModifier {
    let engine: E
    let playing: Bool
    let blocked: Bool

    @AppStorage(XRayProbe.settingKey) private var enabled = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var task: Task<Void, Never>?
    @State private var flag: XRayCancelFlag?

    func body(content: Content) -> some View {
        content
            .onChange(of: playing) { was, now in
                if now { stop("weiter") ; return }
                guard XRayProbe.shouldStart(enabled: enabled, wasPlaying: was, playing: now, loading: engine.isLoading,
                                            ended: engine.isEnded, sceneActive: scenePhase == .active,
                                            duration: engine.duration, failed: engine.errorText != nil,
                                            blocked: blocked) else { return }
                start()
            }
            .onChange(of: blocked) { _, b in if b { stop("gesperrt") } }
            .onChange(of: enabled) { _, on in if !on { stop("aus") } }
            .onChange(of: scenePhase) { _, p in if p != .active { stop("Hintergrund") } }
            .onDisappear { stop("verlassen") }
    }

    private func start() {
        stop(nil)
        guard let backend = engine as? AetherBackend else {
            RemoteLog.info("xray", "übersprungen: anderes Backend")
            return
        }
        let f = XRayCancelFlag()
        flag = f
        task = Task { @MainActor in
            await XRayProbeRun.run(backend, flag: f)
            f.set()   // finished: a later stop() has nothing to cancel and logs nothing
        }
    }

    /// Cancels a running probe; `reason` nil = silent (replaced by a new one).
    private func stop(_ reason: String?) {
        guard let t = task else { return }
        let running = flag?.isSet == false && !t.isCancelled
        flag?.set()
        t.cancel()
        task = nil
        flag = nil
        if running, let reason { RemoteLog.info("xray", "abgebrochen (\(reason))") }
    }
}

/// Cancel flag for the engine's `isCancelled` closure, which runs off the main actor.
final class XRayCancelFlag: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)
    var isSet: Bool { lock.withLock { $0 } }
    func set() { lock.withLock { $0 = true } }
}

@MainActor
enum XRayProbeRun {
    static func run(_ backend: AetherBackend, flag: XRayCancelFlag) async {
        try? await Task.sleep(for: XRayProbe.settleDelay)
        guard !Task.isCancelled, !flag.isSet else { return }
        let e = backend.engine
        let begin = ContinuousClock.now
        let t = e.clock.currentTime
        let content = XRayProbe.contentLabel(format: "\(e.sourceVideoFormat)", dvProfile: e.sourceDVProfile,
                                             convertedToP81: e.dolbyVisionConversion == .profile7ToProfile81)
        let reshaping = AetherEngine.OptionalComponent.dolbyVisionStillReshaping.isBuiltIn
        RemoteLog.info("xray", XRayProbe.startLine(content: content, at: t, stills: e.supportsCacheBackedStills,
                                                   drawsInView: e.scrubPreviewDrawsInView, reshapingBuiltIn: reshaping))
        guard e.supportsCacheBackedStills else {
            let why = XRayProbe.isProfile5(dvProfile: e.sourceDVProfile) && !reshaping
                ? "P5 ohne Umformung" : "Engine liefert keine Standbilder"
            RemoteLog.info("xray", XRayProbe.noFrameLine(ms: ms(since: begin), content: content, reason: why))
            return
        }
        let grabbed = await e.scrubPreviewFrame(atSeconds: t, refined: true, maxWidth: XRayProbe.maxWidth,
                                                isCancelled: { flag.isSet })
        let grabMs = ms(since: begin)
        guard !Task.isCancelled, !flag.isSet else { return }
        guard let frame = grabbed else {
            RemoteLog.info("xray", XRayProbe.noFrameLine(ms: grabMs, content: content,
                                                          reason: "nil (nicht im Zwischenspeicher oder abgelehnt)"))
            if !flag.isSet { await e.releaseScrubPreviewDecoders() }   // a scrub may own them by now
            return
        }
        let verdict = XRayProbe.verdict(requested: t, actual: frame.actualSeconds, refined: frame.refined)
        let width = frame.image.width, height = frame.image.height
        RemoteLog.info("xray", XRayProbe.frameLine(ms: grabMs, width: width, height: height, verdict: verdict,
                                                   content: content))
        // Decoders are not needed for Vision: close them now (100–160 MB for 4K HEVC), not after 3 s idle.
        // Re-checked first: a scrub that started meanwhile has its own decoders open (a cancelled probe leaves
        // them to the engine's 3 s idle close).
        guard !Task.isCancelled, !flag.isSet else { return }
        await e.releaseScrubPreviewDecoders()
        guard !Task.isCancelled, !flag.isSet else { return }

        let visionBegin = ContinuousClock.now
        let image = XRayImage(frame.image)
        let result = await Task.detached(priority: .utility) { XRayVision.detect(image) }.value
        let visionMs = ms(since: visionBegin)
        guard !Task.isCancelled, !flag.isSet else { return }
        switch result {
        case .failure(let error):
            RemoteLog.error("xray", "Vision fehlgeschlagen nach \(visionMs) ms: \(error.localizedDescription)")
            RemoteLog.info("xray", XRayProbe.totalLine(ms: ms(since: begin), outcome: "Vision-Fehler"))
        case .success(let faces):
            RemoteLog.info("xray", XRayProbe.visionLine(ms: visionMs, faces: faces.count, frameWidth: width))
            for (i, face) in XRayProbe.facesForLog(faces).enumerated() {
                RemoteLog.info("xray", XRayProbe.faceLine(index: i, face))
            }
            RemoteLog.info("xray", XRayProbe.totalLine(ms: ms(since: begin),
                                                       outcome: "\(faces.count) Gesicht\(faces.count == 1 ? "" : "er")"))
        }
    }

    private static func ms(since start: ContinuousClock.Instant) -> Int {
        let d = ContinuousClock.now - start
        return Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000)
    }
}

/// CGImage handed to the detached Vision task (read only).
struct XRayImage: @unchecked Sendable {
    let cgImage: CGImage
    init(_ image: CGImage) { cgImage = image }
}

enum XRayVision {
    /// Face rectangles first, then landmarks and capture quality for exactly those faces (matched by uuid).
    static func detect(_ image: XRayImage) -> Result<[XRayProbe.Face], Error> {
        let cg = image.cgImage
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        let rects = VNDetectFaceRectanglesRequest()
        do { try handler.perform([rects]) } catch { return .failure(error) }
        let found = rects.results ?? []
        guard !found.isEmpty else { return .success([]) }
        let marks = VNDetectFaceLandmarksRequest()
        marks.inputFaceObservations = found
        let quality = VNDetectFaceCaptureQualityRequest()
        quality.inputFaceObservations = found
        // Landmarks or quality failing still leaves the rectangles worth logging.
        try? handler.perform([marks, quality])
        // Match by uuid (Vision keeps the input observation's uuid); position only as fallback when counts agree.
        let markResults = marks.results ?? [], qualityResults = quality.results ?? []
        func pick(_ list: [VNFaceObservation], _ i: Int, _ o: VNFaceObservation) -> VNFaceObservation? {
            list.first { $0.uuid == o.uuid } ?? (list.count == found.count ? list[i] : nil)
        }
        let w = Double(cg.width), h = Double(cg.height)
        let degrees = { (v: NSNumber?) in v.map { $0.doubleValue * 180 / .pi } }
        return .success(found.enumerated().map { i, o in
            XRayProbe.Face(width: Int((o.boundingBox.width * w).rounded()),
                           height: Int((o.boundingBox.height * h).rounded()),
                           confidence: Double(o.confidence), yaw: degrees(o.yaw), roll: degrees(o.roll),
                           quality: pick(qualityResults, i, o)?.faceCaptureQuality.map(Double.init),
                           landmarks: pick(markResults, i, o)?.landmarks != nil)
        })
    }
}
