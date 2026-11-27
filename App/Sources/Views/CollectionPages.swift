import SwiftUI
import Combine
import PlayerCore

/// Ordner einer Collection: eine Reihe pro Quelle.
/// Build 7 (folder): rows from `FolderPage.rows` (same request once, shared titles get " · Filme" / " · Serien"),
/// and a page line under the title (`FolderLoadStatus`): spinner at once while nothing arrived, a German reason
/// when every source finished without titles. The rows keep their placeholders and status tiles.
struct FolderView: View {
    let folder: Folder
    private let rows: [CatalogSource]

    init(folder: Folder) {
        self.folder = folder
        rows = FolderPage.rows(folder.sources)
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: Theme.Space.xl) {
                // Build 7: the page line sits beside the title (no extra gap above the rows once titles show). Own
                // view with its own state: a source landing re-runs only the line, not the rows.
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.l) {
                    Text(folder.title).textRole(.display).layoutPriority(1)
                        .accessibilityAddTraits(.isHeader)
                    FolderLoadStatus(folder: folder, rows: rows)
                }
                .padding(.horizontal, Theme.Space.edge)
                if rows.isEmpty { FocusAnchor(kind: .back).padding(.leading, Theme.Space.edge) }   // N6 (Welle F-c)
                ForEach(rows) { s in
                    HomeRowView(row: HomeRow(content: .list(s), style: .poster), onActivate: { $0 })
                }
            }
            .padding(.vertical, Theme.Space.edgeVertical)
        }
    }
}

/// Build 7 (folder): starts every row's load at once (parallel, through the shared `homeRowItems`, so the rows and a
/// focus warm-up join the same request), shows the page phase (`FolderPagePhase`) and logs one line with the
/// per-source times when the last source finished (`FolderLoadLog`).
private struct FolderLoadStatus: View {
    @EnvironmentObject var model: AppModel
    let folder: Folder
    let rows: [CatalogSource]
    @State private var results: [String: FolderSourceResult] = [:]

    private var phase: FolderPagePhase {
        FolderPagePhase.of(rows.map { results[$0.id] ?? .loading })
    }

    var body: some View {
        let p = phase
        // A real container (not `Group`): the task belongs to it and does not restart when the phase changes.
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
        .task(id: folder.id) { await loadAll() }
    }

    private func loadAll() async {
        let t0 = Date()
        // A warm-up of the last two minutes counts (the tile rested shortly before the click).
        let warm = model.folderPrefetches[folder.id].map { Date().timeIntervalSince($0.at) < 120 ? $0.count : 0 } ?? 0
        let m = model
        await withTaskGroup(of: (String, FolderSourceResult).self) { group in
            for s in rows {
                if isUnserved(s) { results[s.id] = .noAddon; continue }
                group.addTask { @MainActor in
                    let r = await m.homeRowItems(s)
                    let ms = Int(Date().timeIntervalSince(t0) * 1000)
                    let result: FolderSourceResult = r.failed ? .failed(ms: ms)
                        : .loaded(count: r.items.count, ms: ms, cached: r.fromCache)
                    return (s.id, result)
                }
            }
            for await (id, result) in group { results[id] = result }
        }
        // The shared loads do not stop when the page goes (they fill the cache), so the line also comes after leaving.
        let total = Int(Date().timeIntervalSince(t0) * 1000)
        let lines = rows.map { (title: $0.title, result: results[$0.id] ?? .loading) }
        let left = Task.isCancelled ? " · Seite vorher verlassen" : ""
        RemoteLog.info("katalog", FolderLoadLog.line(folder: folder.title, rows: lines, totalMs: total, prefetched: warm) + left)
    }

    /// Addon catalog no installed addon serves (`loadItems` returns an empty list for it without a request).
    private func isUnserved(_ s: CatalogSource) -> Bool {
        guard case .addon(let addonId, let catalogId, let type) = s.kind else { return false }
        return AddonCatalogResolver.resolve(model.profile.addons, addonId: addonId, catalogId: catalogId, type: type) == nil
    }
}

struct CollectionView: View {
    @EnvironmentObject var model: AppModel
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
