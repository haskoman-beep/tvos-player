import SwiftUI
import PlayerCore

/// Welle E-a Nacharbeit 1: Poster einer Kachel. TMDB-Kacheln zeigen zuerst das TMDB-Poster und wechseln auf das
/// Poster des Metadaten-Addons, sobald es da ist (Cache-Treffer synchron, also ohne Flackern beim Neuzeichnen).
/// Geladen wird nur, solange die Kachel sichtbar ist; `.task` bricht beim Verschwinden ab.
struct TilePosterImage: View {
    let item: MetaPreview
    @EnvironmentObject var model: AppModel
    @State private var loaded: String?

    var body: some View {
        let addonOn = model.profile.appearance.titles.addonImages
        RemoteImage(url: (addonOn ? loaded ?? model.cachedTilePoster(for: item) : nil) ?? item.poster)
            .task(id: TaskKey(id: item.id, on: addonOn, addons: model.profile.addons.count)) {
                guard addonOn else { loaded = nil; return }
                if let p = await model.loadTilePoster(for: item), !Task.isCancelled { loaded = p }
            }
    }

    private struct TaskKey: Hashable { var id: String; var on: Bool; var addons: Int }
}
