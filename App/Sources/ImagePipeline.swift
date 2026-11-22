import SwiftUI
import UIKit
import ImageIO
import CoreImage
import os
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

    private let session: URLSession
    private let urlCache: URLCache
    /// NSCache ist threadsicher: `cachedImage` liest ohne Umweg über den Actor (Bild ohne Überblendung zeigen).
    nonisolated(unsafe) private let memory = NSCache<NSString, UIImage>()
    /// Welle F-g: bewegte Fokusbilder (GIF) getrennt vom Bildcache: nur das zuletzt fokussierte bleibt (~30 MB).
    private let animated = NSCache<NSString, UIImage>()
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
        if let img = memory.object(forKey: key as NSString) { return img }
        if let t = failed[key], Date().timeIntervalSince(t) < 300 { return nil }
        if let running = inFlight[key] { return await running.value }
        let task = Task<UIImage?, Never> { await self.fetch(url, target: target, blur: blur) }
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

    nonisolated static func memoryKey(_ url: URL, target: ImageTarget, blur: Int) -> String {
        "\(url.absoluteString)#\(target.cacheKey)\(blur > 0 ? "#b\(blur)" : "")"
    }

    /// Nur der Speichercache, synchron: Treffer erscheinen sofort ohne Überblendung (kein Aufploppen, kein Grau).
    nonisolated func cachedImage(_ url: URL, target: ImageTarget, blur: Int = 0) -> UIImage? {
        memory.object(forKey: Self.memoryKey(url, target: target, blur: blur) as NSString)
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
        animated.removeAllObjects()
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
    /// Nicht während der Wiedergabe; Fehlschläge werden wie beim Standbild 5 min gemerkt.
    func animatedImage(_ url: URL, maxPixels: Int) async -> UIImage? {
        guard !playback else { return nil }
        let key = "\(url.absoluteString)#anim\(maxPixels)"
        if let img = animated.object(forKey: key as NSString) { return img }
        if let t = failed[key], Date().timeIntervalSince(t) < 300 { return nil }
        guard let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else {
            failed[key] = Date(); return nil
        }
        await acquire()
        let decoded = await Task.detached(priority: .utility) { Self.decodeAnimated(data, maxPixels: maxPixels) }.value
        release()
        guard let (img, cost) = decoded else { failed[key] = Date(); return nil }
        if !playback { animated.setObject(img, forKey: key as NSString, cost: cost) }
        return img
    }

    /// Alle (bzw. ausgedünnte) Einzelbilder verkleinert; Rückgabe mit Speicherkosten (ein bewegtes UIImage hat kein cgImage).
    nonisolated static func decodeAnimated(_ data: Data, maxPixels: Int) -> (UIImage, Int)? {
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
        let frames = GIFFramePlan.indices(frameCount: n).compactMap { downsample(src, maxPixels: maxPixels, index: $0) }
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

    /// Größenvariante zuerst, bei Fehlschlag die Original-Adresse.
    private func fetch(_ url: URL, target: ImageTarget, blur: Int) async -> UIImage? {
        let candidates = ImageURLVariant.candidates(for: url.absoluteString, neededWidth: target.neededSourceWidth).compactMap(URL.init(string:))
        for (i, u) in candidates.enumerated() {
            guard let (data, resp) = try? await session.data(from: u),
                  (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else {
                if i + 1 < candidates.count { noteVariantMiss(u) }
                continue
            }
            await acquire()
            let img = await Task.detached(priority: .utility) { Self.downsample(data, target: target, blur: blur) }.value
            release()
            if let img { return img }
        }
        return nil
    }

    /// Fehlende Größenvarianten melden (höchstens 5 Zeilen je Start), damit falsche Stufen auffallen.
    private var variantMisses = 0
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
        guard blur > 0 else { return img }
        return blurred(img, radius: max(1, Double(blur) / 4)) ?? img
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

    var total: Int { lock.lock(); defer { lock.unlock() }; return bytes }
    func add(_ c: Int) { lock.lock(); bytes += c; lock.unlock() }
    func reset() { lock.lock(); bytes = 0; lock.unlock() }

    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        guard let img = obj as? UIImage else { return }
        let c = ImagePipeline.cost(img)
        lock.lock(); bytes = max(0, bytes - c); lock.unlock()
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
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var loadedURL: String?
    @State private var target: ImageTarget?

    /// Ab dieser Bitmap-Größe gibt die Ansicht beim Verschwinden frei (≈ 2560×1600 und größer).
    static let releaseBytes = 16 << 20

    private struct LoadKey: Equatable {
        let url: String?
        let target: ImageTarget?
        /// Weichzeichner an/aus (z. B. Spoilerschutz nach „gesehen“) lädt die passende Variante.
        let blur: CGFloat
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: fit ? .fit : .fill)
                    .transition(.opacity)
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
        .task(id: LoadKey(url: url, target: fixedTarget ?? target, blur: blur)) {
            guard let s = url, let u = URL(string: s) else { image = nil; return }
            guard let target = fixedTarget ?? target else { return }   // Größe noch unbekannt: nicht winzig dekodieren
            let blurPx = Int((blur * displayScale).rounded())
            // Speichercache-Treffer (auch nach dem Freigeben beim Zurückkehren): sofort, ohne Überblendung.
            if let hit = ImagePipeline.shared.cachedImage(u, target: target, blur: blurPx) {
                image = hit; loadedURL = s
                return
            }
            if loadedURL != s { image = nil }
            let img = await ImagePipeline.shared.image(u, target: target, blur: blurPx)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { image = img; loadedURL = s }
        }
        .onDisappear {
            guard let image, ImagePipeline.cost(image) >= Self.releaseBytes else { return }
            self.image = nil
            loadedURL = nil
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
