import SwiftUI
import UIKit
import ImageIO

/// Bildlader nach Vorbild NuvioTVOS/VortX: Plattencache (URLCache), Speichercache nach Bytes,
/// Verkleinern per ImageIO abseits des Hauptthreads, gleiche Anfragen zusammengelegt, Fehler kurz gemerkt.
actor ImagePipeline {
    static let shared = ImagePipeline()

    private let session: URLSession
    private let memory = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var failed: [String: Date] = [:]
    /// Höchstens 3 gleichzeitige Dekodierungen, damit das Scrollen flüssig bleibt.
    private var decoding = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("images")
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(memoryCapacity: 20 << 20, diskCapacity: 400 << 20, directory: dir)
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: cfg)
        memory.totalCostLimit = 160 << 20
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
        if let img { memory.setObject(img, forKey: key as NSString, cost: Self.cost(img)) } else { failed[key] = Date() }
        return img
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
