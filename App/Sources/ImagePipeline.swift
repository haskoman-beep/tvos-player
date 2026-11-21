import SwiftUI
import UIKit
import ImageIO
import os
import PlayerCore

/// Bildlader nach Vorbild NuvioTVOS/VortX: Plattencache (URLCache), Speichercache nach Bytes,
/// Verkleinern per ImageIO abseits des Hauptthreads, gleiche Anfragen zusammengelegt, Fehler kurz gemerkt.
/// Speichercache-Grenze nach freiem Prozess-Speicher (`ImageCacheBudget`), bei Speicherwarnung geleert,
/// während der Wiedergabe klein (Meldung über `StreamPrefetcher.playerAppeared/Disappeared`).
actor ImagePipeline {
    static let shared = ImagePipeline()
    /// Speicher-Anteil des URLCache (Plattencache bleibt unberührt).
    static let urlMemory = 20 << 20
    static let urlMemoryPlayback = 4 << 20

    private let session: URLSession
    private let urlCache: URLCache
    private let memory = NSCache<NSString, UIImage>()
    /// Belegung des Speichercaches (Verdrängen meldet NSCache über den Delegate).
    private let tracker = CacheCostTracker()
    private var costLimit = ImageCacheBudget.maximum
    private var playback = false
    private var playbackVersion = 0
    private var lastBudgetCheck = Date.distantPast
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var failed: [String: Date] = [:]
    /// Höchstens 3 gleichzeitige Dekodierungen, damit das Scrollen flüssig bleibt.
    private var decoding = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("images")
        let cfg = URLSessionConfiguration.default
        let cache = URLCache(memoryCapacity: Self.urlMemory, diskCapacity: 400 << 20, directory: dir)
        cfg.urlCache = cache
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: cfg)
        urlCache = cache
        memory.totalCostLimit = ImageCacheBudget.maximum
        memory.delegate = tracker
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { _ in
            Task { await ImagePipeline.shared.memoryWarning() }
        }
        Task { await ImagePipeline.shared.updateBudget(force: true, reason: "Start") }
    }

    /// Bild in höchstens `maxPixels` Kantenlänge (längere Seite).
    func image(_ url: URL, maxPixels: Int) async -> UIImage? {
        let key = "\(url.absoluteString)#\(maxPixels)"
        if let img = memory.object(forKey: key as NSString) { return img }
        if let t = failed[key], Date().timeIntervalSince(t) < 300 { return nil }
        if let running = inFlight[key] { return await running.value }
        let task = Task<UIImage?, Never> { await self.fetch(url, maxPixels: maxPixels) }
        inFlight[key] = task
        let img = await task.value
        inFlight[key] = nil
        if let img {
            let c = Self.cost(img)
            tracker.add(c)
            memory.setObject(img, forKey: key as NSString, cost: c)
            updateBudget()
        } else { failed[key] = Date() }
        return img
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
        memory.removeAllObjects()
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

    /// Für Reihen: die nächsten Bilder schon laden.
    func prefetch(_ urls: [URL], maxPixels: Int) {
        for u in urls { Task { _ = await image(u, maxPixels: maxPixels) } }
    }

    private func fetch(_ url: URL, maxPixels: Int) async -> UIImage? {
        guard let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return nil }
        await acquire()
        defer { release() }
        return await Task.detached(priority: .utility) { Self.downsample(data, maxPixels: maxPixels) }.value
    }

    private func acquire() async {
        if decoding < 3 { decoding += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { decoding -= 1 } else { waiters.removeFirst().resume() }
    }

    nonisolated static func downsample(_ data: Data, maxPixels: Int) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
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

    var total: Int { lock.lock(); defer { lock.unlock() }; return bytes }
    func add(_ c: Int) { lock.lock(); bytes += c; lock.unlock() }
    func reset() { lock.lock(); bytes = 0; lock.unlock() }

    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        guard let img = obj as? UIImage else { return }
        let c = ImagePipeline.cost(img)
        lock.lock(); bytes = max(0, bytes - c); lock.unlock()
    }
}

/// Bild aus dem Netz über `ImagePipeline`. `maxPixels` = längere Seite in Pixeln (tvOS 1080p/4K-UI ≈ Punkte × 2).
struct RemoteImage: View {
    let url: String?
    var maxPixels: Int = 720
    /// Logos: ganz zeigen statt beschneiden.
    var fit = false
    @State private var image: UIImage?
    @State private var loadedURL: String?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: fit ? .fit : .fill)
                    .transition(.opacity)
            } else if !fit {
                Color.white.opacity(0.08)
            }
        }
        .task(id: url) {
            guard let s = url, let u = URL(string: s) else { image = nil; return }
            if loadedURL != s { image = nil }
            let img = await ImagePipeline.shared.image(u, maxPixels: maxPixels)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { image = img; loadedURL = s }
        }
    }
}
