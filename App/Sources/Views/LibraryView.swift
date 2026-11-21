import SwiftUI
import PlayerCore

/// Bibliothek (Spec §5, §7a.5): Weiterschauen, Merkliste, Verlauf.
struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @State private var continueRow = HomeRow(content: .list(.continueWatching), style: .landscape)
    @State private var watchlistRow = HomeRow(content: .list(.watchlist), style: .poster)
    /// Fokus-Entprellung wie auf der Startseite (ohne Hero): treibt das Vorladen der Quellen.
    @State private var focus = HomeFocus()

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 56) {
                HomeRowView(row: continueRow, onActivate: { $0 }, onLongPress: {})
                if model.isConnected("trakt") || model.isConnected("simkl") {
                    HomeRowView(row: watchlistRow, onActivate: { $0 }, onLongPress: {})
                } else {
                    LibraryHint(title: "Merkliste", text: "Die Merkliste kommt aus Trakt oder Simkl (Einstellungen → Dienste & Schlüssel).")
                }
                HistoryRow()
            }
            .padding(.vertical, 40)
        }
        .environment(focus)
    }
}

/// Verlauf: lokal zu Ende gesehene Titel, neueste zuerst (Trakt/Simkl-Verlauf folgt später).
private struct HistoryRow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let items = model.progress.history().map(\.item)
        if items.isEmpty {
            LibraryHint(title: "Verlauf", text: "Noch nichts zu Ende gesehen.")
        } else {
            VStack(alignment: .leading, spacing: 18) {
                Text("Verlauf").font(.title3.bold()).padding(.leading, 60)
                Strip {
                    ForEach(items) { m in
                        NavigationLinkish(route: .detail(m), onActivate: { $0 }, label: PosterCard(item: m))
                    }
                }
            }
        }
    }
}

private struct LibraryHint: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title3.bold())
            Text(text).foregroundStyle(.secondary).frame(height: 120)
        }
        .padding(.leading, 60)
    }
}
