import SwiftUI
import UIKit
import ImageIO
import CoreImage
import Combine
import os
import Network
import PlayerCore

/// Bildlader: Plattencache (URLCache), Speichercache nach Bytes,
/// Verkleinern per ImageIO abseits des Hauptthreads, gleiche Anfragen zusammengelegt, Fehler kurz gemerkt.
/// Speichercache-Grenze nach freiem Prozess-Speicher (`ImageCacheBudget`), bei Speicherwarnung geleert,
/// während der Wiedergabe klein (Meldung über `StreamPrefetcher.playerAppeared/Disappeared`).
actor ImagePipeline {
    static let shared = ImagePipeline()
    /// Speicher-Anteil des URLCache (Plattencache bleibt unberührt).
    static let urlMemory = 20 << 20
    static let urlMemoryPlayback = 4 << 20
    /// Bitmaps from this size on (≈ 2560×1600 and larger) count as large: views release them when they disappear
    /// (`RemoteImage.releaseBytes`) and the decode does not copy them for display (review M2: no 2× peak).
    static let largeBitmapBytes = 16 << 20

    private let session: URLSession
    private let http: LimitedHTTPClient
    /// Task 2.3: 20 MiB like `HTTPLimits.image`; 15 s without data as before (Wave F-k R1).
    static let limits = HTTPLimits(requestTimeout: 15, resourceTimeout: HTTPLimits.image.resourceTimeout,
                                   maxBytes: HTTPLimits.image.maxBytes)
    private let urlCache: URLCache
    /// NSCache ist threadsicher: `cachedImage` liest ohne Umweg über den Actor (Bild ohne Überblendung zeigen).
    nonisolated(unsafe) private let memory = NSCache<NSString, UIImage>()
    /// Welle F-g: bewegte Fokusbilder (GIF) getrennt vom Bildcache: nur das zuletzt fokussierte bleibt (~30 MB).
    private let animated = NSCache<NSString, UIImage>()
    /// Belegung des Speichercaches (Verdrängen meldet NSCache über den Delegate).
    private let tracker: CacheCostTracker
    private var costLimit = ImageCacheBudget.maximum
    private var playback = false
    private var playbackVersion = 0
    private var lastBudgetCheck = Date.distantPast
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    /// A-B-3: failed loads with their kind; 404/410 stay blocked 5 min, everything else 20 s (`ImageFailure`).
    private var failed: [String: (at: Date, kind: ImageFailure)] = [:]
    /// Höchstens 3 gleichzeitige Dekodierungen, damit das Scrollen flüssig bleibt.
    private var decoding = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Welle F-g: GIFs dekodieren in einem eigenen Platz (höchstens 1) und belegen keinen der 3 Standbild-Plätze.
    private var gifDecoding = false
    private var gifWaiters: [CheckedContinuation<Void, Never>] = []
    /// Laufende GIF-Ladungen je Schlüssel; mit den wartenden Aufrufern, damit die Ladung abbricht, wenn keiner mehr wartet.
    private struct AnimLoad { let id: UUID; let task: Task<UIImage?, Never>; var callers: Set<UUID> }
    private var animInFlight: [String: AnimLoad] = [:]
    /// Letzter Speicherschlüssel je Adresse (+ Weichzeichner): synchroner Treffer, bevor die Zielgröße bekannt ist.
    private let lastKeys = LockedKeys()
    /// Treffer/Fehlgriffe des Speichercaches, alle 30 s als Summe geloggt (P3: mit Art der Fehlgriffe, Platte/Netz,
    /// Dekodierzeit und Freigaben, `ImageCacheTally`).
    let stats: CacheStats

    init() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("images")
        let cfg = URLSessionConfiguration.default
        let cache = URLCache(memoryCapacity: Self.urlMemory, diskCapacity: 400 << 20, directory: dir)
        cfg.urlCache = cache
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.httpMaximumConnectionsPerHost = 6
        // Wave F-k R1: a picture service that stops answering gives up after 15 s without data (default 60 s); a slow
        // download that keeps receiving is not cut. The tile then tries its next picture (TilePosterImage).
        cfg.timeoutIntervalForRequest = 15
        let counts = CacheStats()
        stats = counts
        tracker = CacheCostTracker(stats: counts)
        // Build 4 follow-up 2 (P3): a session delegate only for the task metrics (disk cache or network per download).
        session = URLSession(configuration: cfg, delegate: ImageLoadMetrics(stats: counts), delegateQueue: nil)
        // Task 2.3: downloads go through the HTTPClient (size limit 20 MiB, total time limit) on this cached session.
        http = LimitedHTTPClient(transport: URLSessionByteTransport(session: session))
        urlCache = cache
        memory.totalCostLimit = ImageCacheBudget.maximum
        memory.delegate = tracker
        animated.countLimit = 1
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [weak self] _ in
            Task { await self?.memoryWarning() }
        }
        Task { [weak self] in await self?.updateBudget(force: true, reason: "Start") }
    }

    /// Bild in höchstens `maxPixels` Kantenlänge (längere Seite).
    func image(_ url: URL, maxPixels: Int) async -> UIImage? {
        await image(url, target: .square(maxPixels))
    }

    /// Bild für eine Zielgröße (Welle C-b, #16): dekodiert so groß wie gezeichnet, nicht größer als das Original.
    /// Adressen bekannter Bilddienste werden auf die passende Größenvariante umgeschrieben (#23), mit der
    /// Original-Adresse als Ersatz. `blur` > 0: einmal vorberechneter Weichzeichner (Radius in Pixeln, #34).
    func image(_ url: URL, target: ImageTarget, blur: Int = 0) async -> UIImage? {
        let key = Self.memoryKey(url, target: target, blur: blur)
        if let img = memory.object(forKey: key as NSString) { stats.hit(); return img }
        // P3: new address, other size, dropped since, or a load already running for it.
        let previous = lastKeys.get(Self.lastKey(url, blur: blur))
        stats.miss(ImageCacheTally.classify(key: key, lastKey: previous, joined: inFlight[key] != nil))
        if isBlocked(key) { return nil }
        if let running = inFlight[key] { return await running.value }
        let task = Task<UIImage?, Never> {
            let (img, kind) = await self.fetch(url, target: target, blur: blur)
            if img == nil, let kind { await self.noteFailure(key, kind) }
            return img
        }
        inFlight[key] = task
        let img = await task.value
        inFlight[key] = nil
        if let img {
            let c = Self.cost(img)
            tracker.add(c)
            memory.setObject(img, forKey: key as NSString, cost: c)
            lastKeys.set(Self.lastKey(url, blur: blur), key)
            updateBudget()
            failed[key] = nil
        }
        return img
    }

    private func isBlocked(_ key: String, now: Date = Date()) -> Bool {
        guard let f = failed[key] else { return false }
        if f.kind.blocks(since: f.at, now: now) { return true }
        failed[key] = nil
        return false
    }

    private func noteFailure(_ key: String, _ kind: ImageFailure) { failed[key] = (Date(), kind) }

    /// A-B-3: the network is back – forget short-lived failures at once (404/410 stay).
    func networkReturned() {
        failed = failed.filter { $0.value.kind == .gone }
    }

    nonisolated static func memoryKey(_ url: URL, target: ImageTarget, blur: Int) -> String {
        "\(url.absoluteString)#\(target.cacheKey)\(blur > 0 ? "#b\(blur)" : "")"
    }

    /// Nur der Speichercache, synchron: Treffer erscheinen sofort ohne Überblendung (kein Aufploppen, kein Grau).
    /// `count`: in die Treffer-Statistik aufnehmen (nicht beim Nachsehen aus `body`, das je Frame läuft).
    nonisolated func cachedImage(_ url: URL, target: ImageTarget, blur: Int = 0, count: Bool = true) -> UIImage? {
        let img = memory.object(forKey: Self.memoryKey(url, target: target, blur: blur) as NSString)
        if img != nil && count { stats.hit() }
        return img
    }

    nonisolated static func lastKey(_ url: URL, blur: Int) -> String { "\(url.absoluteString)#b\(blur)" }

    /// Welle F-g: zuletzt für diese Adresse dekodiertes Bild aus dem Speichercache, ohne Zielgröße. Für den ersten
    /// Frame einer neu angelegten Kachel (LazyHStack legt Zellen neu an, @State ist dann leer): kein grauer Frame.
    nonisolated func cachedAnySize(_ url: URL, blur: Int = 0) -> UIImage? {
        guard let key = lastKeys.get(Self.lastKey(url, blur: blur)) else { return nil }
        return memory.object(forKey: key as NSString)
    }

    /// Wiedergabe beginnt/endet: Speichercache leeren und klein halten bzw. wieder freigeben.
    /// `version` steigt mit jeder Meldung; ältere (verspätete) werden verworfen.
    func setPlaybackActive(_ active: Bool, version: Int) {
        guard version > playbackVersion else { return }
        playbackVersion = version
        guard active != playback else { return }
        playback = active
        urlCache.memoryCapacity = active ? Self.urlMemoryPlayback : Self.urlMemory
        if active { clearMemory() }
        updateBudget(force: true, reason: active ? "Wiedergabe" : "Wiedergabe beendet")
    }

    private func memoryWarning() {
        clearMemory()
        updateBudget(force: true, reason: "Speicherwarnung")
    }

    private func clearMemory() {
        // P3 review M1: a deliberate clear (playback, memory warning) is no budget pressure: not counted as released.
        tracker.clearing { memory.removeAllObjects() }
        animated.removeAllObjects()
        lastKeys.removeAll()
        tracker.reset()
        // Speicheranteil des URLCache leeren, Plattencache behalten.
        urlCache.memoryCapacity = 0
        urlCache.memoryCapacity = playback ? Self.urlMemoryPlayback : Self.urlMemory
    }

    /// Grenze nach freiem Speicher neu bemessen – höchstens alle 10 s, außer `force`.
    private func updateBudget(force: Bool = false, reason: String? = nil) {
        let now = Date()
        guard force || now.timeIntervalSince(lastBudgetCheck) >= 10 else { return }
        lastBudgetCheck = now
        let available = UInt64(os_proc_available_memory())
        let cached = tracker.total
        let limit = ImageCacheBudget.limit(availableBytes: available, cachedBytes: cached, playback: playback)
        let changed = ImageCacheBudget.changedEnough(old: costLimit, new: limit)
        if changed || force {
            costLimit = limit
            memory.totalCostLimit = limit
        }
        guard changed || reason != nil else { return }
        let mb = UInt64(ImageCacheBudget.mb)
        let free = available > 0 ? "\(available / mb) MB" : "unbekannt"
        let used = Self.footprint().map { "\($0 / mb) MB" } ?? "?"
        let why = reason.map { " (\($0))" } ?? ""
        let line = "Grenze \(UInt64(limit) / mb) MB · frei \(free) · belegt \(used) · Cache \(UInt64(cached) / mb) MB\(why)"
        Task { @MainActor in RemoteLog.info("bilder", line) }
    }

    /// Prozessverbrauch (phys_footprint, wie ihn das System für das Speicherbudget zählt).
    nonisolated static func footprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? info.phys_footprint : nil
    }

    /// Welle F-g: GIF als bewegtes Bild (Einzelbilder höchstens `maxPixels`, ausgedünnt nach `GIFFramePlan`).
    /// Nicht während der Wiedergabe. Eine Ladung je Adresse (weitere Aufrufer warten mit); bricht ab, sobald kein
    /// Aufrufer mehr wartet (Fokus weitergezogen) – auch mitten im Dekodieren. Abbruch zählt nicht als Fehlschlag;
    /// echte Fehlschläge werden wie beim Standbild 5 min gemerkt.
    func animatedImage(_ url: URL, maxPixels: Int) async -> UIImage? {
        guard !playback else { return nil }
        let key = "\(url.absoluteString)#anim\(maxPixels)"
        if let img = animated.object(forKey: key as NSString) { return img }
        if isBlocked(key) { return nil }
        let caller = UUID()
        let load: AnimLoad
        if let running = animInFlight[key] { load = running } else {
            let id = UUID()
            load = AnimLoad(id: id, task: Task { await self.loadAnimated(url, key: key, maxPixels: maxPixels, loadID: id) }, callers: [])
        }
        var l = load; l.callers.insert(caller); animInFlight[key] = l
        let img = await withTaskCancellationHandler {
            await load.task.value
        } onCancel: {
            Task { await self.dropCaller(caller, key: key, loadID: load.id) }
        }
        dropCaller(caller, key: key, loadID: load.id, cancelIfLast: false)
        return Task.isCancelled ? nil : img
    }

    /// Aufrufer austragen; war es der letzte und wurde er abgebrochen, die Ladung abbrechen.
    private func dropCaller(_ caller: UUID, key: String, loadID: UUID, cancelIfLast: Bool = true) {
        guard var l = animInFlight[key], l.id == loadID else { return }
        l.callers.remove(caller)
        if l.callers.isEmpty && cancelIfLast {
            l.task.cancel()
            animInFlight[key] = nil
        } else { animInFlight[key] = l }
    }

    private func loadAnimated(_ url: URL, key: String, maxPixels: Int, loadID: UUID) async -> UIImage? {
        defer { if animInFlight[key]?.id == loadID { animInFlight[key] = nil } }
        let data: Data
        do {
            let (d, resp) = try await load(url)
            if let status = (resp as? HTTPURLResponse)?.statusCode, let kind = ImageFailure.classify(status: status) {
                noteFailure(key, kind); return nil
            }
            data = d
        } catch {
            // Abbruch (Fokus weg) ist kein Fehlschlag: sonst bliebe das GIF gesperrt.
            if !Task.isCancelled, let kind = ImageFailure.classify(error: error) { noteFailure(key, kind) }
            return nil
        }
        guard !Task.isCancelled else { return nil }
        await acquireGIF()
        guard !Task.isCancelled else { releaseGIF(); return nil }
        let flag = CancelFlag()
        let decoded = await withTaskCancellationHandler {
            await Task.detached(priority: .utility) { Self.decodeAnimated(data, maxPixels: maxPixels, cancelled: flag) }.value
        } onCancel: { flag.set() }
        releaseGIF()
        guard !Task.isCancelled else { return nil }
        guard let (img, cost) = decoded else { noteFailure(key, .transient); return nil }
        if !playback { animated.setObject(img, forKey: key as NSString, cost: cost) }
        return img
    }

    private func acquireGIF() async {
        if !gifDecoding { gifDecoding = true; return }
        await withCheckedContinuation { gifWaiters.append($0) }
    }

    private func releaseGIF() {
        if gifWaiters.isEmpty { gifDecoding = false } else { gifWaiters.removeFirst().resume() }
    }

    /// Alle (bzw. ausgedünnte) Einzelbilder verkleinert; Rückgabe mit Speicherkosten (ein bewegtes UIImage hat kein cgImage).
    /// `UIImage.animatedImage` zeigt jedes Einzelbild gleich lang: unterschiedliche Verzögerungen je Bild gehen verloren.
    /// `cancelled` wird vor jedem Einzelbild geprüft (Fokus weg → sofort aufhören).
    nonisolated static func decodeAnimated(_ data: Data, maxPixels: Int, cancelled: CancelFlag = CancelFlag()) -> (UIImage, Int)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let n = CGImageSourceGetCount(src)
        guard n > 1 else { return downsample(src, maxPixels: maxPixels).map { ($0, cost($0)) } }
        var delays: [Double?] = []
        for i in 0..<n {
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let d = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber) ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)
            delays.append(d?.doubleValue)
        }
        var frames: [UIImage] = []
        for idx in GIFFramePlan.indices(frameCount: n) {
            if cancelled.isSet { return nil }
            if let f = downsample(src, maxPixels: maxPixels, index: idx) { frames.append(f) }
        }
        guard !frames.isEmpty else { return nil }
        guard let img = UIImage.animatedImage(with: frames, duration: GIFFramePlan.duration(delays: delays)) else { return nil }
        return (img, frames.reduce(0) { $0 + cost($1) })
    }

    /// Für Reihen: die nächsten Bilder schon laden.
    func prefetch(_ urls: [URL], maxPixels: Int) {
        for u in urls { Task { _ = await image(u, maxPixels: maxPixels) } }
    }

    func prefetch(_ urls: [URL], target: ImageTarget) {
        for u in urls { Task { _ = await image(u, target: target) } }
    }

    /// Task 2.3: one picture download with the image limits; the session's cache rule stays in charge.
    private func load(_ url: URL) async throws -> (Data, URLResponse) {
        stats.fetched()   // P3: disk or network comes from the task metrics (`ImageLoadMetrics`)
        let r = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        let (d, resp) = try await http.data(r, limits: Self.limits, fresh: false)
        return (d, resp)
    }

    /// Größenvariante zuerst, bei Fehlschlag die Original-Adresse. A-B-3: with no picture, the kind of failure
    /// (nil = cancelled, not remembered).
    private func fetch(_ url: URL, target: ImageTarget, blur: Int) async -> (UIImage?, ImageFailure?) {
        noteTargetPolicy(url)
        let candidates = ImageURLVariant.candidates(for: url.absoluteString, neededWidth: target.neededSourceWidth).compactMap(URL.init(string:))
        var failure: ImageFailure?
        var cancelled = false
        for (i, u) in candidates.enumerated() {
            let data: Data
            do {
                let (d, resp) = try await load(u)
                if let status = (resp as? HTTPURLResponse)?.statusCode, let kind = ImageFailure.classify(status: status) {
                    failure = ImageFailure.combine(failure, kind)
                    if i + 1 < candidates.count { noteVariantMiss(u) }
                    continue
                }
                data = d
            } catch {
                if Task.isCancelled { cancelled = true; break }
                if let kind = ImageFailure.classify(error: error) { failure = ImageFailure.combine(failure, kind) } else { cancelled = true; break }
                if i + 1 < candidates.count { noteVariantMiss(u) }
                continue
            }
            await acquire()
            let decodeStart = ContinuousClock.now
            let img = await Task.detached(priority: .utility) { Self.downsample(data, target: target, blur: blur) }.value
            release()
            stats.decoded(ms: Metric.ms(decodeStart.duration(to: ContinuousClock.now)))   // P3
            if let img { return (img, nil) }
            failure = ImageFailure.combine(failure, .transient)   // undecodable: short memory only
        }
        return (nil, cancelled ? nil : (failure ?? .transient))
    }

    /// Fehlende Größenvarianten melden (höchstens 5 Zeilen je Start), damit falsche Stufen auffallen.
    private var variantMisses = 0
    /// Task 2.3, shadow build: pictures the TargetPolicy would refuse (non-http, private targets; the origin addon
    /// is unknown here, so LAN addons count too). Only counted and logged (first 5 per start), never blocked.
    private var targetRefusals = 0
    private func noteTargetPolicy(_ u: URL) {
        guard !TargetPolicy.allows(u, origin: nil) else { return }
        targetRefusals += 1
        guard targetRefusals <= 5 else { return }
        let line = "Zielprüfung würde Bild ablehnen (Schattenbetrieb, \(u.scheme ?? "?"), Nr. \(targetRefusals))"
        Task { @MainActor in RemoteLog.info("bilder", line) }
    }

    private func noteVariantMiss(_ u: URL) {
        variantMisses += 1
        guard variantMisses <= 5 else { return }
        let line = "Größenvariante nicht geladen (\(u.host ?? "?") \(u.pathComponents.dropFirst().prefix(3).joined(separator: "/"))), nehme Original"
        Task { @MainActor in RemoteLog.info("bilder", line) }
    }

    private func acquire() async {
        if decoding < 3 { decoding += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { decoding -= 1 } else { waiters.removeFirst().resume() }
    }

    nonisolated static func downsample(_ data: Data, target: ImageTarget, blur: Int) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        var w = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        var h = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        // EXIF-Drehung 5–8: Breite und Höhe tauschen die Rollen.
        if let o = (props?[kCGImagePropertyOrientation] as? NSNumber)?.intValue, (5...8).contains(o) { swap(&w, &h) }
        var maxPixels = target.decodeMaxPixels(imageWidth: w, imageHeight: h)
        // Weichgezeichnet sieht ein Viertel der Auflösung gleich aus und kostet ein Sechzehntel.
        if blur > 0 { maxPixels = max(64, maxPixels / 4) }
        guard let img = downsample(src, maxPixels: maxPixels) else { return nil }
        guard blur > 0 else { return prepared(img) }
        return prepared(blurred(img, radius: max(1, Double(blur) / 4)) ?? img)
    }

    /// Build 4 follow-up S2: decode into the display format here (off the main thread), so the first frame that shows
    /// the picture needs no colour/format conversion on commit. Kept only when it is still a CGImage-backed bitmap
    /// (`cost` and the blur step read `cgImage`). Large bitmaps (4K backdrops) stay as they are: the copy would double
    /// their memory at the peak of the decode.
    nonisolated private static func prepared(_ img: UIImage) -> UIImage {
        guard cost(img) < largeBitmapBytes else { return img }
        guard let p = img.preparingForDisplay(), p.cgImage != nil else { return img }
        return p
    }

    nonisolated static func downsample(_ data: Data, maxPixels: Int) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return downsample(src, maxPixels: maxPixels)
    }

    nonisolated private static func downsample(_ src: CGImageSource, maxPixels: Int, index: Int = 0) -> UIImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, index, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Weichzeichner einmal auf das kleine Bitmap (Ränder fortgesetzt, damit sie nicht ausbleichen).
    nonisolated(unsafe) private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    nonisolated private static func blurred(_ img: UIImage, radius: Double) -> UIImage? {
        guard let cg = img.cgImage else { return nil }
        let input = CIImage(cgImage: cg)
        let out = input.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: input.extent)
        guard let res = ciContext.createCGImage(out, from: input.extent) else { return nil }
        return UIImage(cgImage: res)
    }

    nonisolated static func cost(_ img: UIImage) -> Int {
        guard let cg = img.cgImage else { return 1 }
        return cg.bytesPerRow * cg.height
    }
}

/// Zählt die Kosten im Bild-Speichercache mit (NSCache gibt seine Belegung nicht heraus).
/// Der Delegate wird aus NSCache heraus auf beliebigen Threads gerufen, daher mit Sperre.
private final class CacheCostTracker: NSObject, NSCacheDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = 0
    /// P3: releases counted for the 30 s cache line (budget pressure: e.g. 4K backdrops pushing posters out).
    private let stats: CacheStats
    /// P3 review M1: set while `clearMemory` empties the cache (NSCache reports each object as evicted then).
    private var isClearing = false

    init(stats: CacheStats) { self.stats = stats }

    /// Runs `body` (removing all objects) without counting its removals as released.
    func clearing(_ body: () -> Void) {
        lock.lock(); isClearing = true; lock.unlock()
        body()
        lock.lock(); isClearing = false; lock.unlock()
    }

    var total: Int { lock.lock(); defer { lock.unlock() }; return bytes }
    func add(_ c: Int) { lock.lock(); bytes += c; lock.unlock() }
    func reset() { lock.lock(); bytes = 0; lock.unlock() }

    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        guard let img = obj as? UIImage else { return }
        let c = ImagePipeline.cost(img)
        lock.lock(); bytes = max(0, bytes - c); let clearing = isClearing; lock.unlock()
        if !clearing { stats.evicted(bytes: c) }
    }
}

/// Build 4 follow-up 2 (P3): per finished picture download whether it came from the URLCache (disk) or the network.
/// Called by URLSession on its own queue; `CacheStats` locks.
private final class ImageLoadMetrics: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let stats: CacheStats

    init(stats: CacheStats) { self.stats = stats }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let kind = metrics.transactionMetrics.last?.resourceFetchType else { return }
        if kind == .localCache { stats.loaded(fromDisk: true) } else if kind == .networkLoad { stats.loaded(fromDisk: false) }
    }
}

/// A-B-3: counts "network back" moments (NWPath unsatisfied → satisfied). Visible `RemoteImage`s without a picture
/// load again when it changes (they listen to `$generation`, they do not observe this object, so views that show
/// their picture are not re-rendered); the pipeline forgets its short-lived failures first.
@MainActor final class NetworkReturn: ObservableObject {
    static let shared = NetworkReturn()
    @Published private(set) var generation = 0
    private var online = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let ok = path.status == .satisfied
            Task { @MainActor in NetworkReturn.shared.changed(online: ok) }
        }
        monitor.start(queue: DispatchQueue(label: "player.bilder.netzpfad"))
    }

    private func changed(online ok: Bool) {
        guard ok != online else { return }
        online = ok
        guard ok else { return }
        Task {
            await ImagePipeline.shared.networkReturned()
            generation += 1
            RemoteLog.info("bilder", "Netz wieder da · sichtbare Bilder laden neu")
        }
    }
}

/// Bild aus dem Netz über `ImagePipeline`. Dekodiert nach der gezeichneten Größe × Bildschirmfaktor (#16);
/// solange die Größe unbekannt ist (erster Layout-Durchlauf), wird nichts angefordert.
/// `maxPixels` begrenzt optional die längere Seite. Große Bitmaps (Vollbild-Hintergründe) gibt die Ansicht
/// beim Verschwinden frei (eine verdeckte Seite hält dann kein 4K-Bitmap); beim Wiederkommen kommt es aus dem Cache.
struct RemoteImage: View {
    let url: String?
    var maxPixels: Int? = nil
    /// Logos: ganz zeigen statt beschneiden.
    var fit = false
    /// Vorberechneter Weichzeichner in Punkten (0 = aus); kein Live-Effekt je Bild (#34).
    var blur: CGFloat = 0
    /// Feste Zielgröße statt der gezeichneten (aufgeklappte Karte nutzt die Variante des Vollbild-Hintergrunds:
    /// ein Download, ein Bitmap im Speichercache für beide).
    var fixedTarget: ImageTarget? = nil
    /// Welle F-l: eigene Fläche, solange kein Bild da ist (Paket-Kachel: Farbverlauf), statt der grauen.
    var placeholder: AnyView? = nil
    /// Build 4 follow-up S2: while a new address loads, keep showing the previous picture instead of the placeholder
    /// (only one loaded with the same blur: spoiler rule). Only poster tiles use it (TMDB poster → addon poster).
    var keepsPreviousWhileLoading = false
    /// Wave F-k: called with the address when it cannot be loaded (not on cancel); poster tiles then try the next one.
    var onFailure: (@MainActor (String) -> Void)? = nil
    @Environment(\.displayScale) private var displayScale
    /// A-B-3: bumped when the network comes back while this view has no picture for its address (part of `LoadKey`).
    /// Build 4 follow-up S2: a local counter instead of observing `NetworkReturn`, so views showing their picture
    /// neither re-render nor restart their load.
    @State private var retry = 0
    @State private var image: UIImage?
    @State private var loadedURL: String?
    /// Weichzeichner, mit dem `image` geladen wurde: nach einem Wechsel (Spoilerschutz) nie das alte Bild zeigen.
    @State private var loadedBlur: CGFloat?
    @State private var target: ImageTarget?
    /// S2: address of the last picture this view showed (swap log: did a swap start without any picture?).
    @State private var shownURL: String?

    /// What the body draws: the picture of this address and blur, else a memory-cache hit, else (poster tiles) the
    /// previous picture of the same blur until the new address has one.
    private var visible: UIImage? {
        let exact = loadedURL == url && loadedBlur == blur ? image : nil
        let kept = keepsPreviousWhileLoading && url != nil && loadedBlur == blur ? image : nil
        return exact ?? syncHit ?? kept
    }

    private var syncHit: UIImage? {
        guard let s = url, let u = URL(string: s) else { return nil }
        let b = Int((blur * displayScale).rounded())
        if let t = fixedTarget ?? target, let hit = ImagePipeline.shared.cachedImage(u, target: t, blur: b, count: false) { return hit }
        return ImagePipeline.shared.cachedAnySize(u, blur: b)
    }

    /// Ab dieser Bitmap-Größe gibt die Ansicht beim Verschwinden frei (≈ 2560×1600 und größer).
    static let releaseBytes = ImagePipeline.largeBitmapBytes

    private struct LoadKey: Equatable {
        let url: String?
        let target: ImageTarget?
        /// Weichzeichner an/aus (z. B. Spoilerschutz nach „gesehen“) lädt die passende Variante.
        let blur: CGFloat
        /// A-B-3: `retry`; a change loads again.
        let retry: Int
    }

    var body: some View {
        // Welle F-g: eine neu angelegte Zelle (LazyHStack) hat leeren @State; ihr erster Frame nimmt das Bild synchron
        // aus dem Speichercache statt grau zu zeichnen (die .task läuft erst nach dem ersten Frame).
        // Nur ein Bild derselben Adresse und desselben Weichzeichners zeigen (kein Spoiler nach Blur-Wechsel).
        // S2: a poster tile keeps its previous picture (same blur only) until the new address has one (`visible`).
        let shown = visible
        ZStack {
            if let shown {
                Image(uiImage: shown).resizable().aspectRatio(contentMode: fit ? .fit : .fill)
                    .transition(.opacity)
            } else if let placeholder {
                placeholder
            } else if !fit {
                Color.white.opacity(0.08)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            guard fixedTarget == nil else { return }
            guard var t = ImageTarget(points: size.width, size.height, scale: displayScale, fit: fit) else { return }
            if let cap = maxPixels { t.width = min(t.width, cap); t.height = min(t.height, cap) }
            if t != target { target = t }
        }
        .onReceive(NetworkReturn.shared.$generation.dropFirst()) { _ in
            // Only a view still missing the picture for its current address (and blur) tries again.
            guard url != nil, image == nil || loadedURL != url || loadedBlur != blur else { return }
            retry += 1
        }
        .task(id: LoadKey(url: url, target: fixedTarget ?? target, blur: blur, retry: retry)) {
            guard let s = url, let u = URL(string: s) else {
                image = nil
                if let url { onFailure?(url) }
                return
            }
            guard let target = fixedTarget ?? target else { return }   // Größe noch unbekannt: nicht winzig dekodieren
            let blurPx = Int((blur * displayScale).rounded())
            // S2: a poster tile moving on from a picture of another address; a gap when it draws no picture now.
            let swapStart = keepsPreviousWhileLoading
                ? PosterSwapStats.start(previous: shownURL, next: s, pictureVisible: visible != nil) : nil
            // P3: the first picture this poster tile shows (`PictureArrivalLog.firstPoster`; swaps go to PosterSwapLog).
            let firstPoster = keepsPreviousWhileLoading && shownURL == nil
            // Speichercache-Treffer (auch nach dem Freigeben beim Zurückkehren): sofort, ohne Überblendung.
            if let hit = ImagePipeline.shared.cachedImage(u, target: target, blur: blurPx) {
                image = hit; loadedURL = s; loadedBlur = blur; shownURL = s
                if let swapStart { PosterSwapLog.note(gapMs: swapStart == .gap ? 0 : nil, waitMs: 0) }
                if firstPoster { PictureArrivalLog.firstPoster.note(hit, fromMemory: true, waitMs: 0, fades: false) }
                return
            }
            let keep = keepsPreviousWhileLoading && loadedBlur == blur
            if (loadedURL != s || loadedBlur != blur) && !keep { image = nil }
            let started = ContinuousClock.now
            let img = await ImagePipeline.shared.image(u, target: target, blur: blurPx)
            guard !Task.isCancelled else { return }
            if img == nil && keep && image != nil {
                // S2: keep the previous picture; `onFailure` moves the tile on to its next address.
            } else {
                withAnimation(.easeOut(duration: 0.2)) { image = img; loadedURL = s; loadedBlur = blur }
            }
            if let img {
                shownURL = s
                let ms = Metric.ms(started.duration(to: ContinuousClock.now))
                if let swapStart { PosterSwapLog.note(gapMs: swapStart == .gap ? ms : nil, waitMs: ms) }
                if firstPoster { PictureArrivalLog.firstPoster.note(img, fromMemory: false, waitMs: ms, fades: true) }
            }
            if img == nil { onFailure?(s) }
        }
        .onDisappear {
            guard let image, ImagePipeline.cost(image) >= Self.releaseBytes else { return }
            self.image = nil
            loadedURL = nil
            loadedBlur = nil
            shownURL = nil
        }
    }
}

/// Welle F-g: bewegtes Bild (UIImage.animatedImage) – SwiftUI `Image` spielt es nicht ab, `UIImageView` schon.
struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.contentMode = .scaleAspectFill
        v.clipsToBounds = true
        // Größe bestimmt SwiftUI (.frame), nicht die Bildgröße.
        for axis in [NSLayoutConstraint.Axis.horizontal, .vertical] {
            v.setContentHuggingPriority(.defaultLow, for: axis)
            v.setContentCompressionResistancePriority(.defaultLow, for: axis)
        }
        return v
    }

    func updateUIView(_ v: UIImageView, context: Context) {
        guard v.image !== image else { return }
        v.image = image
        v.startAnimating()
    }

    static func dismantleUIView(_ v: UIImageView, coordinator: Coordinator) {
        v.stopAnimating()
        v.image = nil
    }
}

/// Welle F-g: GIF, das nur auf der fokussierten Kachel spielt. Erst nach kurzer Ruhe geladen (schnelles Durchscrollen
/// lädt nichts); beim Verlassen gibt die Kachel die Einzelbilder frei.
struct FocusGIF: View {
    let url: String
    let focused: Bool
    @State private var image: UIImage?
    /// Fehlgeschlagene Adressen nur einmal je Start loggen.
    @MainActor private static var logged = Set<String>()

    var body: some View {
        ZStack {
            if focused, let image { AnimatedImageView(image: image).transition(.opacity) }
        }
        .allowsHitTesting(false)
        .task(id: focused) {
            guard focused, let u = URL(string: url) else { image = nil; return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let img = await ImagePipeline.shared.animatedImage(u, maxPixels: GIFFramePlan.maxPixels)
            guard !Task.isCancelled else { return }
            if img == nil, Self.logged.insert(url).inserted {
                RemoteLog.info("bilder", "Fokus-GIF nicht geladen (\(u.host ?? "?") \(u.lastPathComponent))")
            }
            withAnimation(.easeOut(duration: 0.2)) { image = img }
        }
    }
}

/// Welle F-g: Abbruch-Merker, threadsicher (für die abgekoppelte GIF-Dekodierung).
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

/// Welle F-g: Adresse → letzter Speicherschlüssel, threadsicher (synchroner Zugriff aus `body`).
final class LockedKeys: @unchecked Sendable {
    private let lock = NSLock()
    private var map: [String: String] = [:]
    func get(_ k: String) -> String? { lock.lock(); defer { lock.unlock() }; return map[k] }
    /// Höchstens so viele Einträge; voll → ganz leeren (die Bilder selbst hält der NSCache, hier nur Schlüssel).
    static let limit = 2000
    func set(_ k: String, _ v: String) {
        lock.lock()
        if map.count >= Self.limit && map[k] == nil { map.removeAll(keepingCapacity: true) }
        map[k] = v
        lock.unlock()
    }
    func removeAll() { lock.lock(); map.removeAll(); lock.unlock() }
}

/// Welle F-g: Treffer/Fehlgriffe des Bild-Speichercaches, höchstens alle 30 s eine Logzeile (nur wenn etwas passiert ist).
/// Build 4 follow-up 2 (P3): the line also gives the miss classes, downloads from disk/network, decode time and
/// releases (`ImageCacheTally`); written on a hit or miss as before.
final class CacheStats: @unchecked Sendable {
    private let lock = NSLock()
    private var tally = ImageCacheTally()
    private var last = Date()
    func hit() { record { $0.hit() } }
    func miss(_ kind: ImageCacheTally.Miss) { record { $0.miss(kind) } }
    func fetched() { update { $0.fetched() } }
    func loaded(fromDisk: Bool) { update { $0.loaded(fromDisk: fromDisk) } }
    func decoded(ms: Int) { update { $0.decoded(ms: ms) } }
    func evicted(bytes: Int) { update { $0.evicted(bytes: bytes) } }

    private func update(_ change: (inout ImageCacheTally) -> Void) {
        lock.lock(); change(&tally); lock.unlock()
    }

    private func record(_ change: (inout ImageCacheTally) -> Void) {
        lock.lock()
        change(&tally)
        let now = Date()
        var line: String?
        if now.timeIntervalSince(last) >= 30 {
            line = tally.text()
            tally = ImageCacheTally(); last = now
        }
        lock.unlock()
        if let line { Task { @MainActor in RemoteLog.info("bilder", line) } }
    }
}
