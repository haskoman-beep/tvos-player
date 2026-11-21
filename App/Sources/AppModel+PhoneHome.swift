import Foundation
import PlayerCore

// Welle F-e: „Startseite ordnen“ auf der Handy-Seite. Gleicher Weg wie Schlüssel und URLs (PhoneServer → PhoneCommand),
// nur werden diese Befehle synchron übernommen, damit die Antwortseite schon den neuen Stand zeigt.
extension AppModel {
    /// Was sich einblenden lässt: dieselben Angebote wie „Reihe hinzufügen“ auf dem Fernseher.
    var phoneRowOptions: [RowContent] {
        let lists: [CatalogSource] = [.continueWatching, .watchlist, .upcoming]
            + (isConnected("trakt") ? [.traktRecommendedMovies, .traktRecommendedShows] : [])
            + profile.addons.flatMap { a in
                a.manifest.catalogs.map { c in
                    CatalogSource(id: "addon:\(a.manifest.id):\(c.type):\(c.id)", title: "\(c.name ?? c.id) (\(a.manifest.name))",
                                  kind: .addon(addonId: a.manifest.id, catalogId: c.id, type: c.type),
                                  mediaType: c.type == "series" ? .series : .movie)
                }
            }
        return profile.collections.map { RowContent.collection(id: $0.id) } + lists.map { RowContent.list($0) }
    }

    func phoneHomeState() -> PhoneHomeState {
        PhoneHomeState.make(layout: profile.home, hiddenRows: profile.hiddenRows, options: phoneRowOptions,
                            title: { self.rowTitle($0) }, detail: { o in
            switch o {
            case .list: "Liste"
            case .collection(let id): "Collection · \(self.collection(id)?.folders.count ?? 0) Ordner"
            }
        })
    }

    /// Übernimmt Befehle aus „Startseite ordnen“ (andere Befehle werden übergangen).
    func applyHome(_ commands: [PhoneCommand]) {
        let options = phoneRowOptions
        var changed = false
        for c in commands where c.isHomeEdit {
            var home = profile.home, hidden = profile.hiddenRows
            let edit = home.applyPhone(c, hidden: &hidden, options: options)
            if home != profile.home || hidden != profile.hiddenRows {
                update { $0.home = home; $0.hiddenRows = hidden }
            }
            guard let edit else {
                RemoteLog.info("home", "Handy: Zug ohne Wirkung (Liste veraltet)")
                continue
            }
            changed = true
            switch edit {
            case let .moved(row, from, to): RemoteLog.info("home", "Reihe verschoben \(from)→\(to) (Handy): \(rowTitle(row.content))")
            case let .removed(row, at): RemoteLog.info("home", "Reihe ausgeblendet an \(at) (Handy): \(rowTitle(row.content))")
            case let .restored(row, at): RemoteLog.info("home", "Reihe wieder eingeblendet an \(at) (Handy): \(rowTitle(row.content))")
            case let .added(row, at): RemoteLog.info("home", "Reihe hinzugefügt an \(at) (Handy): \(rowTitle(row.content))")
            }
        }
        if changed { notice = "Startseite vom Handy geändert." }
    }

    private func rowTitle(_ c: RowContent) -> String {
        switch c {
        case .list(let s): s.title
        case .collection(let id): collection(id)?.title ?? "Collection"
        }
    }
}
