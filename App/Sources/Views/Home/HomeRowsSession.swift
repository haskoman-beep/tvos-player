import SwiftUI
import PlayerCore

/// Welle F-b2: eine Sitzung im Verwalter „Reihen & Collections“ samt Hinzufügen-Browser.
/// Hält den `HomeManager` (PlayerCore), schreibt jede Aktion sofort ins Profil (`home`, `hiddenRows`) und loggt sie.
/// Kit-Reihen laufen über die Kit-Auswahl (`FusionKitStore`), weil der Kit-Abgleich nicht gewählte Kit-Reihen
/// wieder von der Startseite nimmt. Vor jeder Änderung wird der aktuelle Profilstand übernommen (Handy-Seite und
/// Fernseher überschreiben sich nicht, F-b2-Review M2).
@MainActor @Observable
final class HomeRowsSession {
    private(set) var manager: HomeManager
    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private let kit = FusionKitStore.shared
    /// In dieser Sitzung als Collection angelegte fertige Pakete: bleiben in „Fertige Pakete“ stehen (Review I2).
    private var touchedPackages: Set<String> = []
    /// Katalog des letzten Stands (Review M12): neu gebaut nur, wenn sich eine Eingabe geändert hat.
    @ObservationIgnored private var cached: (inputs: CatalogInputs, catalog: RowCatalog)?

    init(model: AppModel) {
        self.model = model
        manager = HomeManager(layout: model.profile.home, hidden: model.profile.hiddenRows)
    }

    /// Änderungen von außen (Handy-Seite, Kit-Abgleich) übernehmen; die eigenen sind schon drin.
    func adoptProfile() {
        manager.adopt(layout: model.profile.home, hidden: model.profile.hiddenRows)
    }

    func title(_ row: HomeRow) -> String { model.homeRowTitle(row.content) }

    func info(_ row: HomeRow) -> ManagedRowInfo {
        let addons = model.profile.addons
        return ManagedRowInfo(row: row) { id in addons.first { $0.manifest.id == id }?.manifest.name }
    }

    // MARK: Aktionsleiste

    func moveToTop(_ id: UUID) -> HomeManager.Focus { adoptProfile(); return apply(manager.moveToTop(id)) }
    func moveToBottom(_ id: UUID) -> HomeManager.Focus { adoptProfile(); return apply(manager.moveToBottom(id)) }
    func move(_ id: UUID, toPosition p: Int) -> HomeManager.Focus { adoptProfile(); return apply(manager.move(id, toPosition: p)) }
    func cycleStyle(_ id: UUID) -> HomeManager.Focus { adoptProfile(); return apply(manager.cycleStyle(id)) }
    func hide(_ id: UUID) -> HomeManager.Focus { adoptProfile(); return apply(manager.hide(id)) }

    func restore(_ id: UUID) -> HomeManager.Focus {
        adoptProfile()
        let o = manager.restore(id)
        let focus = apply(o)
        if case .restored(let row, _)? = o.event { reselectKit(row) }
        return focus
    }

    func beginMove(_ id: UUID) -> Bool { adoptProfile(); return manager.beginMove(id) }
    func step(up: Bool) -> Bool { manager.step(up: up) }
    /// Ablegen auf dem aktuellen Profilstand: eine Handy-Änderung während des Verschiebens bleibt erhalten,
    /// nur die verschobene Reihe wird gesetzt (F-b2-Review m3).
    func endMove() -> HomeManager.Focus {
        apply(manager.endMove(onto: model.profile.home, hidden: model.profile.hiddenRows))
    }
    /// Menu im Verschiebemodus: die alte Stelle steht nie im Profil (erst `endMove` speichert).
    func cancelMove() -> HomeManager.Focus { manager.cancelMove().focus }

    /// Speichert und loggt eine Aktion mit Wirkung (sonst bleibt das Profil unberührt).
    @discardableResult
    private func apply(_ o: HomeManager.Outcome) -> HomeManager.Focus {
        if let e = o.event {
            persist()
            RemoteLog.info("home", e.logText(title: title(e.row)))
        } else if manager.hidden != model.profile.hiddenRows {
            persist()   // Wiedereinblenden eines schon gezeigten Inhalts: nur „Ausgeblendet“ aufgeräumt
        }
        return o.focus
    }

    private func persist() {
        let layout = manager.layout, hidden = manager.hidden
        model.update { $0.home = layout; $0.hiddenRows = hidden }
    }

    /// Kit-Reihe wieder eingeblendet: in der Kit-Auswahl wählen, sonst nimmt der Abgleich sie gleich wieder weg.
    /// Bei ausgeschaltetem Kit kommt nur diese Reihe zurück (Review I1).
    private func reselectKit(_ row: HomeRow) {
        guard FusionImport.kitID(of: row) != nil else { return }
        model.reselectKitRow(row)
        adoptProfile()
    }

    // MARK: Browser

    /// Ergebnis von OK auf einem Browser-Eintrag.
    enum BrowserResult {
        /// Hinzugefügt bzw. zurückgenommen (Rückmeldung in der Zeile).
        case done
        /// Lag schon vorher auf der Startseite: Rückfrage, dann `hide`.
        case confirmHide(HomeRow)
        /// Lässt sich gerade nicht hinzufügen (Text sagt, was fehlt).
        case unavailable(String)
    }

    /// Eingaben des Katalogs; Kit-Inhalte über Schlüssel und Reihenzahl (ein Neuladen derselben Datei mit gleicher
    /// Reihenzahl baut den Katalog erst beim nächsten anderen Anlass neu).
    private struct CatalogInputs: Equatable {
        var layout: HomeLayout
        var addons: [InstalledAddon]
        var collections: [MediaCollection]
        var kitSources: [FusionKitSource]
        var kitRows: [String: Int]
        var kitErrors: [String: String]
        var traktID: Bool
        var traktLogin: Bool
        var tmdb: Bool
        var keep: Set<String>
    }

    func catalog() -> RowCatalog {
        let inputs = CatalogInputs(layout: manager.layout, addons: model.profile.addons, collections: model.profile.collections,
                                   kitSources: kit.sources, kitRows: kit.contents.mapValues(\.rows.count), kitErrors: kit.errors,
                                   traktID: model.hasTraktID, traktLogin: model.isConnected("trakt"), tmdb: !(model.profile.apiKeys["tmdb"] ?? "").isEmpty,
                                   keep: touchedPackages)
        if let c = cached, c.inputs == inputs { return c.catalog }
        let catalog = RowCatalog(layout: inputs.layout, addons: inputs.addons, collections: inputs.collections,
                                 kitSources: inputs.kitSources, kitContents: kit.contents,
                                 traktID: inputs.traktID, traktLogin: inputs.traktLogin,
                                 keepPackages: inputs.keep, tmdb: inputs.tmdb, kitErrors: inputs.kitErrors)
        cached = (inputs, catalog)
        return catalog
    }

    func toggle(_ entry: RowCatalogEntry) -> BrowserResult {
        if case .unavailable(let why) = entry.status { return .unavailable(why) }
        adoptProfile()
        switch entry.action {
        case .content(let c):
            return browserToggle(c)
        case .package(let pkg):
            // Paket bleibt in seiner Gruppe stehen: Fokus bleibt, nochmal OK nimmt es zurück (Review I2).
            touchedPackages.insert(pkg.id)
            if model.collection(pkg.id) == nil { model.addCollection(pkg) }
            return browserToggle(.collection(id: pkg.id))
        case .kit(let rowID, let src):
            return toggleKit(rowID: rowID, source: src, key: entry.id)
        }
    }

    private func browserToggle(_ content: RowContent) -> BrowserResult {
        switch manager.toggle(content) {
        case .added(let row, let at):
            persist(); RemoteLog.info("home", HomeManager.Event.added(row, at: at).logText(title: title(row)))
            return .done
        case .removed(let row, let at):
            persist(); RemoteLog.info("home", HomeManager.Event.removed(row, at: at).logText(title: title(row)))
            return .done
        case .confirmHide(let row):
            return .confirmHide(row)
        }
    }

    /// Kit-Reihe: Wahl in der Kit-Auswahl, der Abgleich hängt sie unten an. Ist das Kit aus, geht es an und nur diese
    /// Reihe kommt (alte Auswahl verworfen, Review I1); sie ist „neu“ markiert.
    private func toggleKit(rowID: String, source: FusionKitSource, key: String) -> BrowserResult {
        if let row = manager.layout.row(withKey: key) {
            guard manager.isNew(row.id) else { return .confirmHide(row) }
            let at = manager.layout.index(of: row.id) ?? 0
            kit.select(rowID, false, source: source)
            adoptProfile()
            RemoteLog.info("home", HomeManager.Event.removed(row, at: at).logText(title: title(row)))
            return .done
        }
        kit.choose(rowID, source: source)
        adoptProfile()
        guard let row = manager.markAdded(key: key), let at = manager.layout.index(of: row.id) else {
            RemoteLog.info("home", "Kit-Reihe nicht übernommen: \(rowID)")
            return .unavailable("Kit-Reihe noch nicht geladen")
        }
        RemoteLog.info("home", HomeManager.Event.added(row, at: at).logText(title: title(row)))
        return .done
    }
}
