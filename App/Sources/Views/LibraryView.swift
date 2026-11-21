import SwiftUI
import PlayerCore

/// Bibliothek: Weiterschauen, Merkliste, Verlauf (Platzhalter).
struct LibraryView: View {
    var body: some View {
        PlaceholderTab(title: "Bibliothek", symbol: "books.vertical")
    }
}

/// Leere Seite für Tabs, die noch kommen.
struct PlaceholderTab: View {
    let title: String
    let symbol: String

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: symbol).font(.system(size: 90)).foregroundStyle(.secondary)
            Text(title).font(.title2.bold())
            Text("Kommt in Build 26").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
