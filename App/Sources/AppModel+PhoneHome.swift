import Foundation
import PlayerCore

// Welle F-e: „Startseite ordnen“ auf der Handy-Seite. Gleicher Weg wie Schlüssel und URLs (PhoneServer → PhoneCommand),
// nur werden diese Befehle synchron übernommen, damit die Antwortseite schon den neuen Stand zeigt.
extension AppModel {
    /// Was sich einblenden lässt: dieselben Angebote wie der Hinzufügen-Browser am Fernseher (Addon-Kataloge über
    /// `RowCatalog.addonSources`, eine ID-Formel für beide Seiten, F-e M5).
    var phoneRowOptions: [RowContent] {
        let lists: [CatalogSource] = [.continueWatching, .watchlist, .upcoming]
            + (isConnected("trakt") ? [.traktRecommendedMovies, .traktRecommendedShows] : [])
            + RowCatalog.addonSources(profile.addons)
        return profile.collections.map { RowContent.collection(id: $0.id) } + lists.map { RowContent.list($0) }
    }

    func phoneHomeState() -> PhoneHomeState {
        PhoneHomeState.make(layout: profile.home, hiddenRows: profile.hiddenRows, options: phoneRowOptions,
                            title: { self.homeRowTitle($0) }, detail: { o in
            switch o {
            case .list: "Liste"
            case .collection(let id): "Collection · \(self.collection(id)?.folders.count ?? 0) Ordner"
            }
        })
    }

    /// Übernimmt Befehle aus „Startseite ordnen“ (andere Befehle werden übergangen). Regeln wie am Fernseher
    /// (`applyPhone` läuft über `HomeEditor`); eine wieder eingeblendete Kit-Reihe wird auch im Kit gewählt.
    func applyHome(_ commands: [PhoneCommand]) {
        let options = phoneRowOptions
        var changed = false, edits = 0
        for c in commands where c.isHomeEdit {
            edits += 1
            var home = profile.home, hidden = profile.hiddenRows
            let edit = home.applyPhone(c, hidden: &hidden, options: options)
            if home != profile.home || hidden != profile.hiddenRows {
                update { $0.home = home; $0.hiddenRows = hidden }
            }
            guard let edit else {
                // F-e N1: ohne Wirkung (veraltete Liste oder Inhalt schon auf der Startseite) heißt „unverändert“.
                RemoteLog.info("home", "Handy: Startseite unverändert (Liste veraltet)")
                continue
            }
            changed = true
            switch edit {
            case let .moved(row, from, to): RemoteLog.info("home", "Reihe verschoben \(from + 1)→\(to + 1) (Handy): \(homeRowTitle(row.content))")
            case let .removed(row, at): RemoteLog.info("home", "Reihe ausgeblendet an \(at + 1) (Handy): \(homeRowTitle(row.content))")
            case let .deleted(row, _): RemoteLog.info("home", "Reihe gelöscht: \(homeRowTitle(row.content)) (Handy)")
            case let .restored(row, at):
                RemoteLog.info("home", "Reihe wieder eingeblendet an \(at + 1) (Handy): \(homeRowTitle(row.content))")
                reselectKitRow(row)
            case let .added(row, at): RemoteLog.info("home", "Reihe hinzugefügt an \(at + 1) (Handy): \(homeRowTitle(row.content))")
            }
        }
        if changed { notice = "Startseite vom Handy geändert." }
        else if edits > 0 { notice = "Startseite unverändert." }
    }

    /// Eingeblendete Kit-Reihe im Kit wählen; sonst nimmt der Kit-Abgleich sie gleich wieder von der Startseite.
    /// Ist das Kit aus, kommt nur diese Reihe zurück, nicht die alte Auswahl (F-b2-Review I1, Fernseher und Handy gleich).
    func reselectKitRow(_ row: HomeRow) {
        let kit = FusionKitStore.shared
        guard let id = FusionImport.kitID(of: row),
              let src = kit.sources.first(where: { $0.id == FusionImport.sourceKey(ofID: id) }) else { return }
        kit.choose(id, source: src)
    }

    /// Reihe vom Handy (TMDB-/Trakt-Link) über `HomeEditor`: unten anhängen, keine Doppelten, gemerkte ausgeblendete
    /// Reihe mit Stil zurück, Log „home“ (F-b2-Review M3).
    func addHomeRow(_ content: RowContent, style: RowStyle? = nil, via: String) {
        let title = homeRowTitle(content)
        if let at = profile.home.rows.firstIndex(where: { $0.content.key == content.key }) {
            RemoteLog.info("home", "Startseite unverändert (\(via)), schon an \(at + 1): \(title)")
            return
        }
        var editor = HomeEditor(layout: profile.home)
        var hidden = profile.hiddenRows
        let id = editor.insert(content, style: style, hidden: &hidden)
        let layout = editor.layout
        update { $0.home = layout; $0.hiddenRows = hidden }
        let at = (layout.index(of: id) ?? layout.rows.count - 1) + 1
        RemoteLog.info("home", "Reihe hinzugefügt an \(at) (\(via)): \(title)")
    }

    /// Anzeigename einer Reihe (Log, Verwalter, Handy-Seite).
    func homeRowTitle(_ c: RowContent) -> String {
        switch c {
        case .list(let s): s.title
        case .collection(let id): collection(id)?.title ?? "Collection"
        }
    }
}
