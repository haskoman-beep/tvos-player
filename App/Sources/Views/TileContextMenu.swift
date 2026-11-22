import SwiftUI
import PlayerCore

/// Wave L: long-press menu on a poster/tile: watchlist on/off, watched/unwatched, remove from Continue Watching
/// (only in that row), open the detail page. On home rows the row actions (wave F-b2) follow in the same menu.
/// Without a title (folders, collections) only the row actions remain.
struct TileContextMenu: ViewModifier {
    let item: MetaPreview?
    var inContinueRow = false
    var row: HomeRowMenu?
    @EnvironmentObject private var model: AppModel
    @Environment(\.navigate) private var navigate

    @ViewBuilder func body(content: Content) -> some View {
        if let item {
            content.contextMenu {
                ForEach(model.tileMenu(for: item, inContinueRow: inContinueRow), id: \.self) { a in
                    Button(role: a == .removeFromContinue ? .destructive : nil) { run(a, item) } label: {
                        Label(a.title, systemImage: Self.symbol(a))
                    }
                }
                if let row { HomeRowMenuItems(menu: row) }
            }
        } else {
            content.homeRowMenu(row)
        }
    }

    private func run(_ a: TileMenuAction, _ m: MetaPreview) {
        if a == .openDetail {
            RemoteLog.info("nav", "Kachelmenü: Detailseite \(m.name)")
            navigate(.detail(m))
            return
        }
        Task { await model.perform(a, on: m) }
    }

    static func symbol(_ a: TileMenuAction) -> String {
        switch a {
        case .watchlistAdd: "bookmark"
        case .watchlistRemove: "bookmark.slash"
        case .markWatched: "checkmark.circle"
        case .markUnwatched: "arrow.uturn.backward.circle"
        case .removeFromContinue: "xmark.circle"
        case .openDetail: "info.circle"
        }
    }
}

extension View {
    /// Wave L: tile long-press menu (see `TileContextMenu`).
    func tileMenu(_ item: MetaPreview?, inContinueRow: Bool = false, row: HomeRowMenu? = nil) -> some View {
        modifier(TileContextMenu(item: item, inContinueRow: inContinueRow, row: row))
    }
}
