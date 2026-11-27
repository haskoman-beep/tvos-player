import SwiftUI
import PlayerCore

/// Welle E-a Nacharbeit 1: Poster einer Kachel. TMDB-Kacheln zeigen zuerst das TMDB-Poster und wechseln auf das
/// Poster des Metadaten-Addons, sobald es da ist (Cache-Treffer synchron, also ohne Flackern beim Neuzeichnen).
/// Geladen wird nur, solange die Kachel sichtbar ist; `.task` bricht beim Verschwinden ab.
/// Wave F-k: an address that fails to load is skipped (addon poster → TMDB poster, PlayerCore `TilePosterChoice`);
/// the title lies under the picture from the start (R1: also while a slow picture loads), so a tile is never an empty
/// grey card.
struct TilePosterImage: View {
    let item: MetaPreview
    /// Title under the picture, visible until the picture covers it (off while the card is expanded: it shows logo or
    /// title itself).
    var showsTitle = true
    @EnvironmentObject var model: AppModel
    /// Ergebnis samt Schlüssel: nach Profil- oder Addon-Wechsel gilt ein altes Ergebnis nicht mehr.
    @State private var loaded: Loaded?
    /// Wave F-k: addresses of this tile that failed to load (with the item they belong to).
    @State private var failed = Failed()

    var body: some View {
        let addonOn = model.profile.appearance.titles.addonImages
        let key = TaskKey(id: item.id, on: addonOn, profile: model.profile.id, addon: model.tileAddonURL(for: item))
        let current = loaded?.key == key ? loaded : nil
        let addon = addonOn ? (current.map(\.url) ?? model.cachedTilePoster(for: item)) : nil
        let gone = failed.item == item.id ? failed.urls : []
        let url = TilePosterChoice.current(addon: addon, poster: item.poster, failed: gone)
        // S2: the TMDB poster stays until the addon poster has arrived (no placeholder in between); `.id`: a kept
        // picture always belongs to this item.
        // Build 8 (poster): decoded at the tile size exactly (`exactSize`), not the next size step.
        RemoteImage(url: url, keepsPreviousWhileLoading: true, onFailure: { s in
            var urls = gone
            urls.insert(s)
            failed = Failed(item: item.id, urls: urls)
            TilePosterLog.note(url: s, next: TilePosterChoice.fallbackText(addon: addon, poster: item.poster, failed: urls))
        }, exactSize: true)
        .id(item.id)
        // Wave F-k R1: base layer; the placeholder is 92 % transparent, the loaded picture covers the title.
        .background(alignment: .bottomLeading) {
            if showsTitle { Text(item.name).font(.caption).padding(10) }
        }
        .task(id: key) {
            guard addonOn else { loaded = nil; return }
            // Runde 2: jedes nicht abgebrochene Ergebnis übernehmen, auch nil (Addon weg → TMDB-Poster).
            let p = await model.loadTilePoster(for: item)
            if !Task.isCancelled { loaded = Loaded(key: key, url: p) }
        }
    }

    private struct TaskKey: Hashable { var id: String; var on: Bool; var profile: UUID; var addon: String? }
    private struct Loaded { var key: TaskKey; var url: String? }
    private struct Failed { var item: String? = nil; var urls: Set<String> = [] }
}

/// Build 4 follow-up S2: tile picture swaps (TMDB poster → addon poster), one `bilder` line per 10 s with activity:
/// how many, how many showed the placeholder in between (should be 0), longest gap, longest wait for the new picture.
@MainActor
enum PosterSwapLog {
    private static var stats = PosterSwapStats()

    /// `fades`: the new picture was loaded and fades in. P3 review M5: only those count as a frame-meter event;
    /// a memory hit (shown at once) would put a `Poster` event next to nearly every missed frame while scrolling.
    static func note(gapMs: Int?, waitMs: Int, fades: Bool) {
        if fades { FrameMeter.event(.poster) }   // S1/P3 frame meter: counted and named in the next `ruckler` line
        guard stats.record(gapMs: gapMs, waitMs: waitMs) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(PosterSwapStats.window))
            if let line = stats.take() { RemoteLog.info("bilder", line) }
        }
    }
}

/// Build 4 follow-up 2 (P3): pictures that went on screen, one `bilder` line per 10 s with activity
/// (`PictureArrivalStats`): backdrop swaps (`HeroBackdrop`) and the first picture of a poster tile (`RemoteImage`).
/// Each one that fades in also counts as a frame-meter event (the `ruckler` line names it when missed frames lie near
/// it); memory hits shown at once do not (P3 review M5).
@MainActor
final class PictureArrivalLog {
    static let backdrop = PictureArrivalLog(title: "Hintergrund", event: .backdrop)
    static let firstPoster = PictureArrivalLog(title: "Erste Poster", event: .poster)

    private var stats: PictureArrivalStats
    private let event: FramePacing.Event

    private init(title: String, event: FramePacing.Event) {
        stats = PictureArrivalStats(title: title)
        self.event = event
    }

    /// `img` goes on screen now; `fades`: with a fade-in (0.6 s backdrop crossfade, 0.2 s poster fade).
    func note(_ img: UIImage, fromMemory: Bool, waitMs: Int, fades: Bool) {
        if fades { FrameMeter.event(event) }
        let w = img.cgImage?.width ?? 0
        let h = img.cgImage?.height ?? 0
        let opened = stats.record(fromMemory: fromMemory, waitMs: waitMs, pixelWidth: w, pixelHeight: h,
                                  bytes: ImagePipeline.cost(img), fades: fades)
        guard opened else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(PictureArrivalStats.window))
            if let line = self?.stats.take() { RemoteLog.info("bilder", line) }
        }
    }
}

/// Wave F-k: tile pictures that did not load, at most 5 lines per launch (host only, never the path: addon addresses
/// can carry configuration).
@MainActor
enum TilePosterLog {
    private static var lines = 0

    static func note(url: String, next: String) {
        lines += 1
        guard lines <= 5 else { return }
        let host = URL(string: url)?.host ?? "?"
        RemoteLog.info("bilder", "Kachelbild nicht geladen (\(host)), zeige \(next)")
    }
}
