import SwiftUI
import Combine
import PlayerCore

/// Ordner einer Collection: eine Reihe pro Quelle.
struct FolderView: View {
    let folder: Folder
    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: Theme.Space.xl) {
                Text(folder.title).textRole(.display).padding(.leading, Theme.Space.edge)
                    .accessibilityAddTraits(.isHeader)
                if folder.sources.isEmpty { FocusAnchor(kind: .back).padding(.leading, Theme.Space.edge) }   // N6 (Welle F-c)
                ForEach(folder.sources) { s in
                    HomeRowView(row: HomeRow(content: .list(s), style: .poster), onActivate: { $0 })
                }
            }
            .padding(.vertical, Theme.Space.edgeVertical)
        }
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
