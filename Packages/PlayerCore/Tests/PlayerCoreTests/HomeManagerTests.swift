import Foundation
import Testing
@testable import PlayerCore

private func rows(_ n: Int) -> HomeLayout {
    HomeLayout(rows: (1...n).map { HomeRow(content: .collection(id: "c\($0)")) })
}

// Abnahme §6.3 Punkt 4: Reihe 20 auf Platz 1 ist eine einzige Aktion („Ganz nach oben“).
@Test func managerMovesRow20ToTopInOneAction() {
    let l = rows(24)
    var m = HomeManager(layout: l)
    let id = l.rows[19].id
    let o = m.moveToTop(id)
    #expect(m.rows.first?.id == id && m.position(of: id) == 1)
    #expect(o.focus == .row(id))
    #expect(o.event == .moved(m.rows[0], RowMove(from: 19, to: 0)))
    #expect(o.event?.logText(title: "Genres") == "Reihe verschoben 20→1: Genres")
    // Schon oben: kein Ereignis, Fokus bleibt.
    #expect(m.moveToTop(id) == HomeManager.Outcome(event: nil, focus: .row(id)))
    // Ganz nach unten und an Position (1-basiert, begrenzt).
    #expect(m.moveToBottom(id).event == .moved(m.rows[23], RowMove(from: 0, to: 23)))
    #expect(m.move(id, toPosition: 3).event?.logText(title: "x") == "Reihe verschoben 24→3: x")
    #expect(m.position(of: id) == 3)
    #expect(m.move(id, toPosition: 99).event == .moved(m.rows[23], RowMove(from: 2, to: 23)))
    #expect(m.positions == Array(1...24))
    #expect(HomeManager(layout: HomeLayout()).positions.isEmpty)
}

@Test func managerMoveModeDropsOrRestores() {
    let l = rows(4)
    var m = HomeManager(layout: l)
    let id = l.rows[2].id
    #expect(m.beginMove(id) && m.moving == HomeManager.Moving(id: id, from: 2))
    #expect(m.step(up: true) && m.step(up: true))
    #expect(!m.step(up: true))                         // schon oben
    #expect(m.position(of: id) == 1)
    // Menu: alte Stelle wieder her, kein Ereignis.
    #expect(m.cancelMove() == HomeManager.Outcome(event: nil, focus: .row(id)))
    #expect(m.rows.map(\.id) == l.rows.map(\.id) && m.moving == nil)
    // OK legt ab: ein Ereignis von→nach.
    m.beginMove(id)
    m.step(up: false)
    let o = m.endMove()
    #expect(o.event == .moved(m.rows[3], RowMove(from: 2, to: 3)) && o.focus == .row(id) && m.moving == nil)
    // Ablegen an derselben Stelle: kein Ereignis.
    m.beginMove(id)
    #expect(m.endMove().event == nil)
    #expect(!m.step(up: true))                          // ohne Verschiebemodus
    #expect(!m.beginMove(UUID()))
}

@Test func managerHidesIntoHiddenRowsAndRestoresAtBottom() {
    let l = rows(3)
    var m = HomeManager(layout: l, hidden: [])
    var styled = l.rows[1]; styled.style = .logoTiles
    m.adopt(layout: HomeLayout(rows: [l.rows[0], styled, l.rows[2]]), hidden: [])
    // Ausblenden: Fokus auf die nachrückende Reihe, Reihe vollständig gemerkt.
    let o = m.hide(styled.id)
    #expect(o.event == .hidden(styled, at: 1) && o.focus == .row(l.rows[2].id))
    #expect(m.hidden == [styled] && m.restorable == [styled])
    #expect(o.event?.logText(title: "Genres") == "Reihe ausgeblendet an 2: Genres")
    // Letzte Reihe: Fokus auf die davor; ohne Reihen auf „Reihe hinzufügen“.
    #expect(m.hide(l.rows[2].id).focus == .row(l.rows[0].id))
    #expect(m.hide(l.rows[0].id).focus == .add)
    #expect(m.restorable.map(\.id) == [l.rows[0].id, l.rows[2].id, styled.id])   // neueste zuerst
    // Wieder einblenden: unten, unverändert (ID und Stil), Fokus darauf.
    let back = m.restore(styled.id)
    #expect(back.event == .restored(styled, at: 0) && back.focus == .row(styled.id) && m.rows == [styled])
    #expect(!m.hidden.contains { $0.id == styled.id })
    // Unbekannt: nichts.
    #expect(m.hide(UUID()).event == nil)
}

@Test func managerRestoreOfContentAlreadyOnHomeOnlyCleansUp() {
    let gone = HomeRow(content: .collection(id: "c1"))
    let again = HomeRow(content: .collection(id: "c1"))
    var m = HomeManager(layout: HomeLayout(rows: [again]), hidden: [gone])
    #expect(m.restorable.isEmpty)                       // wird gar nicht erst angeboten
    #expect(m.restore(gone.id) == HomeManager.Outcome(event: nil, focus: .row(again.id)))
    #expect(m.hidden.isEmpty && m.rows == [again])
}

// Abnahme §6.3 Punkt 3: OK im Browser hängt unten an (ein Druck), Rückkehr fokussiert die oberste neue Reihe.
@Test func browserToggleAddsAtBottomAndFocusesTopmostNew() {
    let l = rows(3)
    var m = HomeManager(layout: l)
    guard case .added(let first, at: 3) = m.toggle(.collection(id: "neu1")) else { Issue.record("add"); return }
    guard case .added(let second, at: 4) = m.toggle(.list(.watchlist)) else { Issue.record("add 2"); return }
    #expect(m.rows.suffix(2).map(\.id) == [first.id, second.id] && m.isNew(first.id) && m.isNew(second.id))
    #expect(m.focusAfterBrowser(previous: .add) == .row(first.id))
    #expect(HomeManager.Event.added(first, at: 3).logText(title: "Kino") == "Reihe hinzugefügt an 4: Kino")
    // Nochmal OK auf der eben hinzugefügten: zurückgenommen, ohne „Ausgeblendet“.
    #expect(m.toggle(.collection(id: "neu1")) == .removed(first, at: 3))
    #expect(m.hidden.isEmpty && m.focusAfterBrowser(previous: .add) == .row(second.id))
    // Vorher schon da (F-b1-Review M1): nur Rückfrage, nichts geändert.
    #expect(m.toggle(.collection(id: "c2")) == .confirmHide(l.rows[1]))
    #expect(m.count == 4)
    // Nichts Neues: Fokus bleibt; verschwundene Reihe → erste Reihe.
    let plain = HomeManager(layout: l)
    #expect(plain.focusAfterBrowser(previous: .row(l.rows[2].id)) == .row(l.rows[2].id))
    #expect(plain.focusAfterBrowser(previous: .row(UUID())) == .row(l.rows[0].id))
}

@Test func managerAdoptKeepsNewMarksAndCancelsMove() {
    let l = rows(2)
    var m = HomeManager(layout: l)
    guard case .added(let added, _) = m.toggle(.collection(id: "x")) else { Issue.record("add"); return }
    m.beginMove(l.rows[0].id)
    // Handy schiebt die neue Reihe nach oben.
    let phone = HomeLayout(rows: [added] + l.rows)
    #expect(m.adopt(layout: phone, hidden: []))
    #expect(m.moving == nil && m.isNew(added.id) && m.rows.map(\.id) == phone.rows.map(\.id))
    #expect(!m.adopt(layout: phone, hidden: []))
    // Kit-Abgleich legt eine Reihe an: nachträglich als neu markieren.
    let kit = HomeRow(content: .collection(id: "fusion.genres.a"))
    m.adopt(layout: HomeLayout(rows: phone.rows + [kit]), hidden: [])
    #expect(!m.isNew(kit.id))
    #expect(m.markAdded(key: kit.content.key) == kit && m.isNew(kit.id))
    #expect(m.markAdded(key: "collection:nix") == nil)
    #expect(m.entryFocus(row: kit.id) == .row(kit.id) && m.entryFocus(row: UUID()) == .add && m.entryFocus(row: nil) == .add)
}

@Test func managerStyleCyclesAllowedStyles() {
    let l = HomeLayout(rows: [HomeRow(content: .list(.watchlist))])
    var m = HomeManager(layout: l)
    let id = l.rows[0].id
    #expect(m.cycleStyle(id).event == .styled(m.rows[0]) && m.rows[0].style == .landscape)
    #expect(m.cycleStyle(id).event?.logText(title: "Merkliste") == "Stil Hero: Merkliste")
    m.cycleStyle(id); m.cycleStyle(id)
    #expect(m.rows[0].style == .poster)
    #expect(m.cycleStyle(UUID()).event == nil)
}

@Test func managedRowInfoNamesKindStyleAndOrigin() {
    let addon = CatalogSource(id: "addon:aio:movie:top", title: "Top (AIO)", kind: .addon(addonId: "aio", catalogId: "top", type: "movie"),
                              mediaType: .movie)
    #expect(ManagedRowInfo(row: HomeRow(content: .list(addon)), addonName: { $0 == "aio" ? "AIOStreams" : nil }).origin == "AIOStreams")
    #expect(ManagedRowInfo(row: HomeRow(content: .list(addon))).origin == "Addon")
    let info = ManagedRowInfo(row: HomeRow(content: .list(.traktRecommendedMovies), style: .landscape))
    #expect(info.origin == "Trakt" && info.detail == "Liste · Querformat" && info.kind == .list)
    #expect(ManagedRowInfo(row: HomeRow(content: .list(.continueWatching))).origin == "Sonderliste")
    let kit = ManagedRowInfo(row: HomeRow(content: .collection(id: "fusion.genres.a")))
    #expect(kit.origin == "Fusion-Kit" && kit.detail == "Collection · Collection-Kacheln")
    let kitList = CatalogSource(id: "fusion.genres.b", title: "x", kind: .tmdbList(id: "1"), mediaType: .movie)
    #expect(ManagedRowInfo(row: HomeRow(content: .list(kitList))).origin == "Fusion-Kit")
    let tmdb = CatalogSource(id: "tmdb:list:1", title: "x", kind: .tmdbList(id: "1"), mediaType: .movie)
    #expect(ManagedRowInfo(row: HomeRow(content: .list(tmdb))).origin == "TMDB")
    #expect(ManagedRowInfo(row: HomeRow(content: .collection(id: "eigene"))).origin == "Eigene Collection")
    if let pkg = ReadyPackages.all.first {
        #expect(ManagedRowInfo(row: HomeRow(content: .collection(id: pkg.id))).origin == "Fertiges Paket")
    }
}

@Test func addonSourcesShareOneFormulaAndSkipRequiredExtras() {
    let manifest = AddonManifest(id: "aio", name: "AIOStreams", version: "1", resources: [], types: ["movie", "series"], catalogs: [
        CatalogDescriptor(type: "movie", id: "top", name: "Top"),
        CatalogDescriptor(type: "series", id: "s", name: "Serien"),
        CatalogDescriptor(type: "movie", id: "search", name: "Suche", extra: [CatalogExtra(name: "search", isRequired: true)]),
    ])
    let sources = RowCatalog.addonSources([InstalledAddon(manifestURL: "https://example.invalid/manifest.json", manifest: manifest)])
    #expect(sources.map(\.id) == ["addon:aio:movie:top", "addon:aio:series:s"])
    #expect(sources.map(\.title) == ["Top (AIOStreams)", "Serien (AIOStreams)"])
    #expect(sources[1].mediaType == .series)
}

@Test func phoneStateOffersOnlyRestorableHiddenRows() {
    // F-e N1: liegt der Inhalt einer ausgeblendeten Reihe wieder auf der Startseite, bietet das Handy kein
    // „Wieder einblenden“ an; ein veralteter Knopf ergibt keinen Befehl („Nichts geändert“ statt „geändert“).
    let gone = HomeRow(content: .collection(id: "x"))
    let other = HomeRow(content: .collection(id: "y"))
    let layout = HomeLayout(rows: [HomeRow(content: .collection(id: "x"))])
    let state = PhoneHomeState.make(layout: layout, hiddenRows: [gone, other], options: [], title: { $0.key })
    #expect(state.hidden.map(\.id) == [other.id.uuidString])
    #expect(state.command(op: "restore:\(gone.id.uuidString)") == nil)
    #expect(state.command(op: "restore:\(other.id.uuidString)") == .restoreRow(other.id))
}
