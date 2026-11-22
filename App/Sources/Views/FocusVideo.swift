import AVFoundation
import SwiftUI
import UIKit
import PlayerCore

// Wave F-o: focus video on tiles (from imports only: `focusVideoUrl` of a collection export, `videoURL` of a preview
// pack). One player for the whole app, so at most one video runs; it is released completely while the main player
// is open. Pure rules (priority, sound, cache limits) live in PlayerCore `TileMotion.swift`.

/// Disk cache of focus videos in Caches/FocusVideos, in two pots: `silent` (50 MB, 20 MiB per file) and `sound`
/// (videos with a sound track, 150 MB, 30 MiB per file); 7 days, least recently used goes first, per pot.
/// One download at a time: a new address cancels the running one. Only a real video body is stored
/// (`FocusVideoCachePlan.check`). Load failures rest 5 min; a stored file that did not play is deleted and its
/// address rests 30 min.
actor FocusVideoCache {
    static let shared = FocusVideoCache()

    enum Outcome {
        case file(URL)
        case failed(String)
        /// Failed shortly before: no new attempt, no new log line.
        case remembered
        case cancelled
    }

    private enum LoadError: Error { case status(Int), body(FocusVideoCachePlan.Check) }

    private let dir: URL
    private let session: URLSession
    private var running: (key: String, task: Task<Void, Error>)?
    /// Address → time until which no new attempt is made.
    private var failed: [String: Date] = [:]

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        dir = caches.appendingPathComponent("FocusVideos", isDirectory: true)
        let fm = FileManager.default
        // Round 2: files sit in pot folders; loose files of round 1 are dropped.
        for u in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        where (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            try? fm.removeItem(at: u)
        }
        for pot in FocusVideoCachePlan.Pot.allCases {
            try? fm.createDirectory(at: dir.appendingPathComponent(pot.folder, isDirectory: true), withIntermediateDirectories: true)
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.urlCache = nil
        cfg.timeoutIntervalForRequest = 15
        session = URLSession(configuration: cfg)
    }

    private func path(_ key: String, _ pot: FocusVideoCachePlan.Pot) -> URL {
        dir.appendingPathComponent(pot.folder, isDirectory: true).appendingPathComponent(FocusVideoCachePlan.fileName(for: key))
    }

    /// Stored file of an address in either pot.
    private func stored(_ key: String) -> URL? {
        for pot in FocusVideoCachePlan.Pot.allCases {
            let u = path(key, pot)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    func file(for url: URL) async -> Outcome {
        let key = url.absoluteString
        if let local = stored(key) {
            // Mark as used (LRU order).
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: local.path)
            return .file(local)
        }
        if let until = failed[key] {
            if Date() < until { return .remembered }
            failed[key] = nil
        }
        let task: Task<Void, Error>
        if let r = running, r.key == key {
            task = r.task
        } else {
            running?.task.cancel()
            task = Task { try await self.download(url, key: key) }
            running = (key, task)
        }
        do {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            if running?.key == key { running = nil }
            guard let local = stored(key) else { return .failed("Datei fehlt") }
            return .file(local)
        } catch {
            if running?.key == key { running = nil }
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { return .cancelled }
            failed[key] = Date().addingTimeInterval(FocusVideoCachePlan.retryAfterLoadFailure)
            switch error {
            case LoadError.status(let code): return .failed("HTTP \(code)")
            case LoadError.body(.tooLarge): return .failed("Datei zu groß")
            case LoadError.body(.tooSmall): return .failed("Datei zu klein")
            case LoadError.body(.notVideo(let type)): return .failed("kein Video: \(type)")
            case LoadError.body: return .failed("ungültige Datei")
            default: return .failed((error as? URLError).map { "Netz \($0.code.rawValue)" } ?? "\(error)")
            }
        }
    }

    private func download(_ url: URL, key: String) async throws {
        let (tmp, resp) = try await session.download(from: url)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Task.checkCancellation()
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw LoadError.status(http.statusCode) }
        let size = Int64((try? tmp.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        if size > FocusVideoCachePlan.maxDownloadBytes { throw LoadError.body(.tooLarge) }
        // Error pages served with 200 (captive portal, CDN) and empty bodies never reach the cache. Head and tail
        // tell whether the file has a sound track (the moov box sits at either end), which picks the pot.
        var head: [UInt8] = [], tail: [UInt8] = []
        if let h = try? FileHandle(forReadingFrom: tmp) {
            head = [UInt8]((try? h.read(upToCount: Mp4Probe.headBytes)) ?? Data())
            if size > Int64(Mp4Probe.headBytes) {
                try? h.seek(toOffset: UInt64(max(Int64(Mp4Probe.headBytes), size - Int64(Mp4Probe.tailBytes))))
                tail = [UInt8]((try? h.readToEnd()) ?? Data())
            }
            try? h.close()
        }
        let check = FocusVideoCachePlan.check(contentType: (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"),
                                              head: head, bytes: size,
                                              hasSound: Mp4Probe.hasSoundTrack(head) || Mp4Probe.hasSoundTrack(tail))
        guard case .ok(let pot) = check else { throw LoadError.body(check) }
        let local = path(key, pot)
        try? FileManager.default.removeItem(at: local)
        try FileManager.default.moveItem(at: tmp, to: local)
        evict(pot)
    }

    /// The stored file of `url` did not play: delete it and let the address rest 30 min (no retry on every focus).
    func markBroken(_ url: URL) {
        let key = url.absoluteString
        for pot in FocusVideoCachePlan.Pot.allCases { try? FileManager.default.removeItem(at: path(key, pot)) }
        failed[key] = Date().addingTimeInterval(FocusVideoCachePlan.retryAfterPlaybackFailure)
    }

    private func evict(_ pot: FocusVideoCachePlan.Pot) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let folder = dir.appendingPathComponent(pot.folder, isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        let entries = files.compactMap { u -> FocusVideoCachePlan.Entry? in
            guard let v = try? u.resourceValues(forKeys: Set(keys)) else { return nil }
            return FocusVideoCachePlan.Entry(name: u.lastPathComponent, bytes: Int64(v.fileSize ?? 0),
                                             used: v.contentModificationDate ?? .distantPast)
        }
        for name in FocusVideoCachePlan.evict(entries, now: Date(), maxBytes: pot.maxBytes) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}

/// The one focus-video player: an `AVQueuePlayer` with `AVPlayerLooper`; per focus only the item changes.
/// Muted unless "Ton bei Kachel-Animation" is on and the file has a sound track; then the sound fades in to
/// `FocusVideoAudio.targetVolume` and plays once (the picture keeps looping silently). The audio session is never
/// deactivated, and the main player always wins: while it is open nothing loads and the player is released.
@MainActor
final class FocusVideoPlayer {
    static let shared = FocusVideoPlayer()

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private weak var layerView: FocusPlayerLayerView?
    private var owner: UUID?
    private var tile = ""
    private var audible = false
    private var mainPlayback = false
    /// Rises with every start/stop: work that awaited something checks it is still current.
    private var generation = 0
    private var fadeTask: Task<Void, Never>?
    private var loopObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    /// Boundary observer shortly before the end of the first pass (fade-out, sound once).
    private var boundaryObserver: Any?
    private var observers: [NSObjectProtocol] = []
    /// Address of the running video (a playback failure marks its cached file broken).
    private var currentURL: URL?
    /// "gestartet" per focus, but at most once per tile and sound state in 30 s (fast browsing should not flood).
    private var loggedStarts: [String: Date] = [:]

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in FocusVideoPlayer.shared.stopAll(release: false) }
        })
        observers.append(center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in FocusVideoPlayer.shared.stopAll(release: true) }
        })
    }

    /// Main player opens (true) or closes (false). Opening stops the focus video and frees the player completely.
    func setMainPlayback(_ active: Bool) {
        guard active != mainPlayback else { return }
        mainPlayback = active
        if active { stopAll(release: true) }
    }

    /// Starts the focus video of a tile for `owner` (the tile view). False if the main player is open, the file
    /// failed, or another tile took over meanwhile.
    func start(url: URL, tile: String, sound: Bool, owner: UUID) async -> Bool {
        guard !mainPlayback else { return false }
        generation += 1
        let gen = generation
        teardown()
        self.owner = owner
        self.tile = tile
        self.currentURL = url
        let source: URL
        if FocusVideoURL.isStream(url.absoluteString) {
            source = url
        } else {
            switch await FocusVideoCache.shared.file(for: url) {
            case .file(let f):
                source = f
            case .failed(let why):
                if gen == generation { self.owner = nil }
                RemoteLog.info("bilder", "Kachel-Video: \(tile) Fehler beim Laden (\(url.host ?? "?") \(url.lastPathComponent), \(why))")
                return false
            case .remembered, .cancelled:
                if gen == generation { self.owner = nil }
                return false
            }
        }
        guard gen == generation, self.owner == owner, !mainPlayback, !Task.isCancelled else { return false }
        let asset = AVURLAsset(url: source)
        var hasAudio = false
        if sound {
            hasAudio = !(((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty)
            guard gen == generation, self.owner == owner, !mainPlayback, !Task.isCancelled else { return false }
        }
        var fadeOutPlan: FocusVideoAudio.FadeOutPlan?
        if hasAudio {
            let d = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? .nan
            fadeOutPlan = FocusVideoAudio.fadeOutPlan(duration: d)
            guard gen == generation, self.owner == owner, !mainPlayback, !Task.isCancelled else { return false }
        }
        audible = FocusVideoAudio.audible(setting: sound, hasAudioTrack: hasAudio, mainPlayback: mainPlayback, loopsDone: 0)
        if audible { prepareAudioSession() }

        let p = player ?? makePlayer()
        player = p
        p.isMuted = !audible
        p.volume = audible ? 0 : 1
        let lp = AVPlayerLooper(player: p, templateItem: AVPlayerItem(asset: asset))
        looper = lp
        loopObservation = lp.observe(\.loopCount, options: [.new]) { l, _ in
            let count = l.loopCount
            Task { @MainActor in FocusVideoPlayer.shared.loopPassed(count, generation: gen) }
        }
        statusObservation = lp.observe(\.status, options: [.new]) { l, _ in
            guard l.status == .failed else { return }
            let why = l.error?.localizedDescription ?? "unbekannt"
            Task { @MainActor in FocusVideoPlayer.shared.failed(why, generation: gen) }
        }
        if audible {
            // Sound exactly once: fade out after about 12 s or before the first pass ends, whichever comes first ...
            if let plan = fadeOutPlan {
                let at = NSValue(time: CMTime(seconds: plan.start, preferredTimescale: 600))
                boundaryObserver = p.addBoundaryTimeObserver(forTimes: [at], queue: .main) {
                    Task { @MainActor in FocusVideoPlayer.shared.endOfFirstPass(generation: gen, fade: plan.length) }
                }
            }
            // ... and, as a hard stop, mute right on the switch to the looper's second replica (also for clips too
            // short for a fade). Set synchronously in the observation, so the second pass is never audible.
            let first = FirstReplica()
            itemObservation = p.observe(\.currentItem, options: [.initial, .new]) { pl, _ in
                guard let item = pl.currentItem else { return }
                guard let seen = first.item else { first.item = item; return }
                guard item !== seen, !pl.isMuted else { return }
                pl.isMuted = true
                Task { @MainActor in FocusVideoPlayer.shared.secondPassStarted(generation: gen) }
            }
        }
        // Plays once the tile's layer is attached (no frames lost before the picture is there).
        let soundText = audible ? "Ton an" : (sound ? "Ton aus, keine Tonspur" : "Ton aus")
        let logKey = "\(tile)|\(soundText)"
        if loggedStarts[logKey].map({ Date().timeIntervalSince($0) >= 30 }) ?? true {
            loggedStarts[logKey] = Date()
            RemoteLog.info("bilder", "Kachel-Video: \(tile) gestartet (\(soundText))")
        }
        return true
    }

    /// The tile's layer view appeared: it shows the player while its owner is the current one.
    func attach(_ view: FocusPlayerLayerView, owner: UUID) {
        guard owner == self.owner, let player else { return }
        if let old = layerView, old !== view { old.playerLayer.player = nil }
        layerView = view
        view.playerLayer.player = player
        if looper != nil, player.rate == 0 { player.play() }
    }

    func detach(_ view: FocusPlayerLayerView) {
        view.playerLayer.player = nil
        if layerView === view { layerView = nil }
    }

    /// First picture is on screen: fade the sound in (after a short quiet wait).
    func layerReady(owner: UUID) {
        guard owner == self.owner, audible, let p = player else { return }
        let gen = generation
        fadeTask?.cancel()
        fadeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(FocusVideoAudio.fadeInDelay))
            await self.fade(p, to: FocusVideoAudio.targetVolume, seconds: FocusVideoAudio.fadeIn, generation: gen)
        }
    }

    /// The tile lost focus or vanished. With sound the video fades out (150 ms) before it stops.
    func stop(owner: UUID) {
        guard owner == self.owner else { return }
        generation += 1
        let gen = generation
        self.owner = nil
        if let v = layerView { v.playerLayer.player = nil; layerView = nil }
        guard audible, let p = player, p.volume > 0 else { teardown(); return }
        fadeTask?.cancel()
        fadeTask = Task { @MainActor in
            await self.fade(p, to: 0, seconds: FocusVideoAudio.fadeOut, generation: gen)
            if gen == self.generation { self.teardown() }
        }
    }

    /// Stops whatever runs; `release` also drops the player object.
    func stopAll(release: Bool) {
        generation += 1
        owner = nil
        teardown()
        if release { player = nil }
    }

    // MARK: private

    private func makePlayer() -> AVQueuePlayer {
        let p = AVQueuePlayer()
        p.automaticallyWaitsToMinimizeStalling = false
        p.preventsDisplaySleepDuringVideoPlayback = false
        p.allowsExternalPlayback = false
        // No subtitle or audio-track logic of the main player.
        p.appliesMediaSelectionCriteriaAutomatically = false
        return p
    }

    /// Sound only: category playback, never deactivated (the main player sets its own mode when it starts).
    private func prepareAudioSession() {
        let s = AVAudioSession.sharedInstance()
        if s.category != .playback { try? s.setCategory(.playback, mode: .default) }
        try? s.setActive(true)
    }

    private func teardown() {
        fadeTask?.cancel()
        fadeTask = nil
        loopObservation = nil
        statusObservation = nil
        itemObservation = nil
        if let b = boundaryObserver { player?.removeTimeObserver(b); boundaryObserver = nil }
        looper?.disableLooping()
        looper = nil
        player?.pause()
        player?.removeAllItems()
        if let v = layerView { v.playerLayer.player = nil }
        layerView = nil
        audible = false
    }

    /// Sound cap reached or the first pass is about to end: fade the sound out, then mute; the picture loops on
    /// silently.
    fileprivate func endOfFirstPass(generation gen: Int, fade: Double) {
        guard gen == generation, audible, let p = player else { return }
        audible = false
        fadeTask?.cancel()
        fadeTask = Task { @MainActor in
            await self.fade(p, to: 0, seconds: fade, generation: gen)
            if gen == self.generation { p.isMuted = true }
        }
    }

    /// The looper switched to its second replica (already muted in the observation): no fade may run any more.
    fileprivate func secondPassStarted(generation gen: Int) {
        guard gen == generation else { return }
        audible = false
        fadeTask?.cancel()
        fadeTask = nil
    }

    /// Fallback for the sound-once rule if neither the boundary nor the item switch was seen.
    private func loopPassed(_ count: Int, generation gen: Int) {
        guard gen == generation, audible, count >= 1, let p = player else { return }
        p.isMuted = true
        secondPassStarted(generation: gen)
    }

    private func failed(_ why: String, generation gen: Int) {
        guard gen == generation else { return }
        RemoteLog.info("bilder", "Kachel-Video: \(tile) Fehler beim Abspielen (\(why))")
        // A stored file that does not play is deleted; the address rests 30 min instead of failing on every focus.
        if let u = currentURL, !FocusVideoURL.isStream(u.absoluteString) {
            Task { await FocusVideoCache.shared.markBroken(u) }
        }
        stopAll(release: false)
    }

    private func fade(_ p: AVPlayer, to target: Float, seconds: Double, generation gen: Int) async {
        let steps = 8
        for v in FocusVideoAudio.ramp(from: p.volume, to: target, steps: steps) {
            guard !Task.isCancelled, gen == generation || target == 0 else { return }
            p.volume = v
            try? await Task.sleep(for: .seconds(seconds / Double(steps)))
        }
    }
}

/// First replica of the looper, seen by the item observation (one per start).
private final class FirstReplica: @unchecked Sendable {
    weak var item: AVPlayerItem?
}

/// A view whose layer is the `AVPlayerLayer` (scales with the focus lift of the card, no extra clip needed).
final class FocusPlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var readyObservation: NSKeyValueObservation?
}

/// Layer of the one focus-video player inside a tile; reports the first picture (`isReadyForDisplay`).
struct FocusVideoLayer: UIViewRepresentable {
    let owner: UUID
    let onReady: @MainActor () -> Void

    func makeUIView(context: Context) -> FocusPlayerLayerView {
        let v = FocusPlayerLayerView()
        v.isUserInteractionEnabled = false
        v.clipsToBounds = true
        v.backgroundColor = .clear
        v.playerLayer.videoGravity = .resizeAspectFill
        let ready = onReady
        v.readyObservation = v.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor in ready() }
        }
        FocusVideoPlayer.shared.attach(v, owner: owner)
        return v
    }

    func updateUIView(_ v: FocusPlayerLayerView, context: Context) {}

    static func dismantleUIView(_ v: FocusPlayerLayerView, coordinator: ()) {
        v.readyObservation = nil
        FocusVideoPlayer.shared.detach(v)
    }
}

/// Focus video over the still of a tile: loads 400 ms after focus (fast scrolling loads nothing), shows the picture
/// only once the first frame is there (the still stays until then), stops on focus loss.
struct FocusVideo: View {
    let url: String
    let tile: String
    let focused: Bool
    let sound: Bool
    @State private var owner = UUID()
    @State private var playing = false
    @State private var ready = false
    /// Rises when the app becomes active again (screensaver, Siri): the focused tile restarts its video.
    @State private var wake = 0
    /// New per started run: forces a fresh layer view, whose attach starts playback.
    @State private var run = UUID()

    var body: some View {
        ZStack {
            if focused && playing {
                FocusVideoLayer(owner: owner) {
                    withAnimation(.easeOut(duration: 0.2)) { ready = true }
                    FocusVideoPlayer.shared.layerReady(owner: owner)
                }
                .opacity(ready ? 1 : 0)
                .id(run)
            }
        }
        .allowsHitTesting(false)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if focused { wake += 1 }
        }
        .task(id: FocusVideoRun(focused: focused, wake: wake)) {
            guard focused, let u = URL(string: url) else { stop(); return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            // A fresh layer per start: its attach starts playback.
            playing = false
            ready = false
            let ok = await FocusVideoPlayer.shared.start(url: u, tile: tile, sound: sound, owner: owner)
            guard !Task.isCancelled else {
                if ok { FocusVideoPlayer.shared.stop(owner: owner) }
                return
            }
            ready = false
            run = UUID()
            playing = ok
        }
        .onDisappear { stop() }
    }

    private func stop() {
        FocusVideoPlayer.shared.stop(owner: owner)
        playing = false
        ready = false
    }
}

/// Identity of one focus-video run of a tile (focus change or app wake starts a new one).
private struct FocusVideoRun: Equatable {
    let focused: Bool
    let wake: Int
}

/// What a focused package tile plays over its still: video, else GIF, else nothing (PlayerCore `TileMotion`).
struct TileMotionOverlay: View {
    let folder: Folder
    let focused: Bool
    let sound: Bool

    var body: some View {
        switch TileMotion.of(folder) {
        case .video(let v): FocusVideo(url: v, tile: folder.title, focused: focused, sound: sound)
        case .gif(let g): FocusGIF(url: g, focused: focused)
        case .still: EmptyView()
        }
    }
}
