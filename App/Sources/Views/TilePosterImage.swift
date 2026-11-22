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
        RemoteImage(url: url, onFailure: { s in
            var urls = gone
            urls.insert(s)
            failed = Failed(item: item.id, urls: urls)
            TilePosterLog.note(url: s, next: TilePosterChoice.fallbackText(addon: addon, poster: item.poster, failed: urls))
        })
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
