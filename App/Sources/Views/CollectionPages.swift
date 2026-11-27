import SwiftUI
import Combine
import PlayerCore

/// Ordner einer Collection: eine Reihe pro Quelle.
/// Build 7 (folder): rows from `FolderPage.rows` (same request once, shared titles get " · Filme" / " · Serien"),
/// and a page line beside the title (`FolderLoadStatus`): spinner at once while nothing arrived, a German reason
/// when every source finished without titles. The rows keep their placeholders and status tiles.
/// Review b7 M2: the load state lives in `FolderPageLoad`, owned here (the header inside the `LazyVStack` is dropped
/// when it scrolls off; its state went with it: spinner again, second log line, new requests).
struct FolderView: View {
    @Environment(AppModel.self) var model
    let folder: Folder
    private let rows: [CatalogSource]
    @StateObject private var load = FolderPageLoad()

    init(folder: Folder) {
        self.folder = folder
        rows = FolderPage.rows(folder.sources)
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: Theme.Space.xl) {
                // Build 7: the page line sits beside the title (no extra gap above the rows once titles show). Own
                // view observing the holder: a source landing re-runs only the line, not the rows.
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.l) {
                    Text(folder.title).textRole(.display).layoutPriority(1)
                        .accessibilityAddTraits(.isHeader)
                    FolderLoadStatus(load: load, rows: rows)
                }
                .padding(.horizontal, Theme.Space.edge)
                if rows.isEmpty { FocusAnchor(kind: .back).padding(.leading, Theme.Space.edge) }   // N6 (Welle F-c)
                ForEach(rows) { s in
                    HomeRowView(row: HomeRow(content: .list(s), style: .poster), onActivate: { $0 })
                }
            }
            .padding(.vertical, Theme.Space.edgeVertical)
        }
        // Outside the lazy stack: runs once per page (the holder ignores a second start, e.g. back from a detail page).
        .task { load.start(model: model, folder: folder, rows: rows) }
    }
}

/// Build 7 (folder): the page line (phase from `FolderLoadState`, the cache read synchronously for rows without a
/// recorded result, so a cached folder shows no spinner).
private struct FolderLoadStatus: View {
    @Environment(AppModel.self) var model
    @ObservedObject var load: FolderPageLoad
    let rows: [CatalogSource]

    var body: some View {
        let cache = model.cache
        let p = load.state.phase(rows, cachedCount: { cache[$0]?.count })
        ZStack(alignment: .leading) {
            switch p {
            case .content:
                Color.clear.frame(width: 1, height: 1)
            case .loading:
                HStack(spacing: Theme.Space.s) {
                    ProgressView()
                    Text(p.text ?? "").textRole(.rowDetail)
                }
                .accessibilityElement(children: .combine)
            default:
                Label(p.text ?? "", systemImage: p == .failed ? "exclamationmark.triangle" : "info.circle")
                    .textRole(.rowDetail)
                    .lineLimit(2)
            }
        }
    }
}

/// Build 7 (folder): load state of one folder page. `start` runs once: every row's load in parallel through the shared
/// `homeRowItems` (rows and a focus warm-up join the same request), one log line with the per-source times when the
/// last finished (`FolderLoadLog`). Review b7 M3: later loads of the same sources (row retry, rebuilt lazy row,
/// background refresh) arrive through `homeRowLoadDone` and keep the line current.
@MainActor
final class FolderPageLoad: ObservableObject {
    @Published private(set) var state = FolderLoadState()
    private var started = false
    private var updates: AnyCancellable?

    func start(model: AppModel, folder: Folder, rows: [CatalogSource]) {
        guard !started else { return }
        started = true
        let t0 = Date()
        let ids = Set(rows.map(\.id))
        updates = model.homeRowLoadDone.sink { [weak self] e in
            MainActor.assumeIsolated {
                guard let self, ids.contains(e.id) else { return }
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                self.state.record(e.id, Self.result(e.load, ms: ms))
            }
        }
        // A warm-up of the last two minutes counts (the tile rested shortly before the click).
        let warm = model.folderPrefetches[folder.id].map { Date().timeIntervalSince($0.at) < 120 ? $0.count : 0 } ?? 0
        var unserved: [String] = []
        for s in rows where Self.isUnserved(s, model: model) {
            state.record(s.id, .noAddon)
            unserved.append(s.id)
        }
        let loads = rows.filter { !unserved.contains($0.id) }
        Task { @MainActor [weak self] in
            var own: [String: FolderSourceResult] = [:]
            await withTaskGroup(of: (String, FolderSourceResult).self) { group in
                for s in loads {
                    group.addTask { @MainActor in
                        let r = await model.homeRowItems(s)
                        return (s.id, Self.result(r, ms: Int(Date().timeIntervalSince(t0) * 1000)))
                    }
                }
                for await (id, result) in group {
                    own[id] = result
                    self?.state.record(id, result)
                }
            }
            for id in unserved { own[id] = .noAddon }
            let total = Int(Date().timeIntervalSince(t0) * 1000)
            let lines = rows.map { (title: $0.title, result: own[$0.id] ?? .loading) }
            RemoteLog.info("katalog", FolderLoadLog.line(folder: folder.title, rows: lines, totalMs: total, prefetched: warm))
        }
    }

    private static func result(_ r: CatalogLoad, ms: Int) -> FolderSourceResult {
        r.failed ? .failed(ms: ms) : .loaded(count: r.items.count, ms: ms, cached: r.fromCache)
    }

    /// Addon catalog no installed addon serves (`loadItems` returns an empty list for it without a request).
    private static func isUnserved(_ s: CatalogSource, model: AppModel) -> Bool {
        guard case .addon(let addonId, let catalogId, let type) = s.kind else { return false }
        return AddonCatalogResolver.resolve(model.profile.addons, addonId: addonId, catalogId: catalogId, type: type) == nil
    }
}

struct CollectionView: View {
    @Environment(AppModel.self) var model
    let collectionID: String
    /// Fehlende Collection erst nach kurzer Ladezeit als fehlend werten (Fusion-Kit lädt nach; kein „Zurück“-Flackern).
    @State private var missingSettled = false
    var body: some View {
        let c = model.collection(collectionID)
        ScrollView(.vertical) {
            HomeRowView(row: HomeRow(content: .collection(id: collectionID)), onActivate: { $0 })
            // N6 (Welle F-c): leere Collection sofort, fehlende erst nach der Ladezeit.
            if c?.folders.isEmpty == true || (c == nil && missingSettled) {
                FocusAnchor(kind: .back).padding(.leading, Theme.Space.edge)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            missingSettled = true
        }
    }
}
