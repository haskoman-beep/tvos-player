import SwiftUI
import PlayerCore

/// Welle F-b2: eine Sitzung im Verwalter „Reihen & Collections“ samt Hinzufügen-Browser.
/// Hält den `HomeManager` (PlayerCore), schreibt jede Aktion sofort ins Profil (`home`, `hiddenRows`) und loggt sie.
/// Kit-Reihen laufen über die Kit-Auswahl (`FusionKitStore`), weil der Kit-Abgleich nicht gewählte Kit-Reihen
/// wieder von der Startseite nimmt.
@MainActor @Observable
final class HomeRowsSession {
    private(set) var manager: HomeManager
    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private let kit = FusionKitStore.shared

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

    func moveToTop(_ id: UUID) -> HomeManager.Focus { apply(manager.moveToTop(id)) }
    func moveToBottom(_ id: UUID) -> HomeManager.Focus { apply(manager.moveToBottom(id)) }
    func move(_ id: UUID, toPosition p: Int) -> HomeManager.Focus { apply(manager.move(id, toPosition: p)) }
    func cycleStyle(_ id: UUID) -> HomeManager.Focus { apply(manager.cycleStyle(id)) }
    func hide(_ id: UUID) -> HomeManager.Focus { apply(manager.hide(id)) }

    func restore(_ id: UUID) -> HomeManager.Focus {
        let o = manager.restore(id)
        let focus = apply(o)
        if case .restored(let row, _)? = o.event { reselectKit(row) }
        return focus
    }

    func beginMove(_ id: UUID) -> Bool { manager.beginMove(id) }
    func step(up: Bool) -> Bool { manager.step(up: up) }
    func endMove() -> HomeManager.Focus { apply(manager.endMove()) }
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

    func catalog() -> RowCatalog {
        RowCatalog(layout: manager.layout, addons: model.profile.addons, collections: model.profile.collections,
                   kitSources: kit.sources, kitContents: kit.contents,
                   traktID: model.hasTraktID, traktLogin: model.isConnected("trakt"))
    }

    func toggle(_ entry: RowCatalogEntry) -> BrowserResult {
        if case .unavailable(let why) = entry.status { return .unavailable(why) }
        switch entry.action {
        case .content(let c):
            return browserToggle(c)
        case .package(let pkg):
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

    /// Kit-Reihe: Wahl in der Kit-Auswahl, der Abgleich hängt sie unten an (und schaltet das Kit an, falls aus).
    private func toggleKit(rowID: String, source: FusionKitSource, key: String) -> BrowserResult {
        if let row = manager.layout.row(withKey: key) {
            guard manager.isNew(row.id) else { return .confirmHide(row) }
            let at = manager.layout.index(of: row.id) ?? 0
            kit.select(rowID, false, source: source)
            adoptProfile()
            RemoteLog.info("home", HomeManager.Event.removed(row, at: at).logText(title: title(row)))
            return .done
        }
        if !kit.settings.enabled { kit.setEnabled(true) }
        kit.select(rowID, true, source: source)
        adoptProfile()
        guard let row = manager.markAdded(key: key), let at = manager.layout.index(of: row.id) else {
            RemoteLog.info("home", "Kit-Reihe nicht übernommen: \(rowID)")
            return .unavailable("Kit-Reihe noch nicht geladen")
        }
        RemoteLog.info("home", HomeManager.Event.added(row, at: at).logText(title: title(row)))
        return .done
    }
}
