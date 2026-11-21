import SwiftUI
import PlayerCore

/// Welle E-a Nacharbeit 1: Poster einer Kachel. TMDB-Kacheln zeigen zuerst das TMDB-Poster und wechseln auf das
/// Poster des Metadaten-Addons, sobald es da ist (Cache-Treffer synchron, also ohne Flackern beim Neuzeichnen).
/// Geladen wird nur, solange die Kachel sichtbar ist; `.task` bricht beim Verschwinden ab.
struct TilePosterImage: View {
    let item: MetaPreview
    @EnvironmentObject var model: AppModel
    /// Ergebnis samt Schlüssel: nach Profil- oder Addon-Wechsel gilt ein altes Ergebnis nicht mehr.
    @State private var loaded: Loaded?

    var body: some View {
        let addonOn = model.profile.appearance.titles.addonImages
        let key = TaskKey(id: item.id, on: addonOn, profile: model.profile.id, addon: model.tileAddonURL(for: item))
        let current = loaded?.key == key ? loaded : nil
        RemoteImage(url: (addonOn ? (current.map(\.url) ?? model.cachedTilePoster(for: item)) : nil) ?? item.poster)
            .task(id: key) {
                guard addonOn else { loaded = nil; return }
                // Runde 2: jedes nicht abgebrochene Ergebnis übernehmen, auch nil (Addon weg → TMDB-Poster).
                let p = await model.loadTilePoster(for: item)
                if !Task.isCancelled { loaded = Loaded(key: key, url: p) }
            }
    }

    private struct TaskKey: Hashable { var id: String; var on: Bool; var profile: UUID; var addon: String? }
    private struct Loaded { var key: TaskKey; var url: String? }
}
