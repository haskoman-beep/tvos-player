import Foundation
import Testing
@testable import PlayerCore

private func req(_ s: String) -> HTTPRequest {
    guard case .complete(let r) = HTTPRequest.parse(Data(s.utf8)) else { fatalError("parse") }
    return r
}

private func post(_ path: String, _ body: String) -> HTTPRequest {
    req("POST \(path) HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)")
}

private let a = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
private let b = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
private let c = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!
private let d = UUID(uuidString: "00000000-0000-0000-0000-00000000000D")!
private let hiddenRow = HomeRow(id: d, content: .list(CatalogSource(id: "tmdb:list:7", title: "Meine Liste", kind: .continueWatching, mediaType: .both)),
                                style: .top10)

private func layout() -> HomeLayout {
    HomeLayout(rows: [HomeRow(id: a, content: .list(.continueWatching)),
                      HomeRow(id: b, content: .list(.watchlist)),
                      HomeRow(id: c, content: .collection(id: "x"))])
}

private let options: [RowContent] = [.collection(id: "x"), .collection(id: "y"), .list(.continueWatching),
                                     .list(.upcoming), .collection(id: "y")]

private func state() -> PhoneHomeState {
    PhoneHomeState.make(layout: layout(), hiddenRows: [hiddenRow], options: options, title: { o in
        switch o { case .list(let s): s.title; case .collection(let id): id == "y" ? "<Kino & Co>" : "Coll \(id)" }
    }, detail: { o in if case .collection = o { "Collection" } else { "Liste" } })
}

@Test func phoneSectionsInTargetOrderWithAnchors() {
    #expect(PhoneSection.allCases.map(\.title) == ["Schnell-Import", "Addons", "Konten & Schlüssel", "Startseite", "System"])
    #expect(PhoneSection.allCases.map(\.rawValue) == ["import", "addon", "keys", "home", "system"])
    #expect(PhoneSection.url("http://h/?t=x", section: .home) == "http://h/?t=x#home")
    #expect(PhoneSection.url("http://h/?t=x", section: nil) == "http://h/?t=x")
    let page = PhoneInputPage(token: "tok")
    let (resp, _) = page.handle(req("GET /?t=tok HTTP/1.1\r\n\r\n"), profileName: "Ich", home: state()) { Data() }
    let html = String(data: resp.body, encoding: .utf8)!
    let pos = ["id=import>", "id=addon>", "id=keys>", "id=home>", "id=order>", "id=system>"].map { html.range(of: $0)?.lowerBound }
    #expect(pos.allSatisfy { $0 != nil })
    #expect(pos.compactMap { $0 } == pos.compactMap { $0 }.sorted())
    // Bestehende Felder bleiben (Namen unverändert), alle Schlüssel samt TorBox im Abschnitt „Konten & Schlüssel“ (wave S).
    for name in ["import", "addon", "key_tmdb", "key_mdblist", "key_tvdb", "key_trakt_id", "key_trakt_secret", "key_simkl_id",
                 "key_torbox", "key_atvloadly", "key_playerlog", "nuvio_url", "nuvio_json", "tmdb_link", "kit_url", "backup_json"] {
        #expect(html.contains("name=\(name)"), "Feld \(name)")
    }
    // Wave S: the TorBox key sits with the other keys, the addon section only takes manifest URLs.
    let keys = html.range(of: "id=keys>")!.lowerBound, home = html.range(of: "id=home>")!.lowerBound
    let torbox = html.range(of: "name=key_torbox")!.lowerBound
    #expect(torbox > keys && torbox < home)
    // Schlüsselfelder sind leer: die Seite gibt nie gespeicherte Werte zurück.
    #expect(!html.contains("value=\"K"))
    #expect(html.contains("<meta name=\"referrer\" content=\"no-referrer\">"))
}

@Test func orderSectionListsRowsEscapedWithButtons() {
    let page = PhoneInputPage(token: "tok")
    let (resp, cmds) = page.handle(req("GET /?t=tok HTTP/1.1\r\n\r\n"), profileName: "Ich", home: state()) { Data() }
    let html = String(data: resp.body, encoding: .utf8)!
    #expect(cmds.isEmpty)
    #expect(html.contains("Startseite ordnen") && html.contains("action=\"/home?t=tok\""))
    // Knöpfe senden nur absolute Ziele.
    #expect(html.contains("value=\"to:\(b.uuidString):0\" aria-label=\"Nach oben\""))
    #expect(html.contains("value=\"to:\(b.uuidString):2\" aria-label=\"Nach unten\"") && html.contains("value=\"hide:\(c.uuidString)\""))
    #expect(html.contains("value=\"to:\(a.uuidString):0\" aria-label=\"Ganz nach oben\" title=\"Ganz nach oben\" disabled"))
    #expect(html.contains("value=\"to:\(c.uuidString):2\" aria-label=\"Ganz nach unten\" title=\"Ganz nach unten\" disabled"))
    #expect(!html.contains("value=\"up:") && !html.contains("value=\"top:"))
    // Ausgeblendet: gemerkte Reihe mit „Wieder einblenden“.
    #expect(state().hidden.map(\.id) == [d.uuidString])
    #expect(html.contains("value=\"restore:\(d.uuidString)\" aria-label=\"Wieder einblenden\""))
    #expect(html.contains("Ausgeblendet (1)") && html.contains("Meine Liste"))
    // Weitere Angebote: ohne Gezeigte, Ausgeblendete und Doppelte; Titel maskiert.
    #expect(state().more.map(\.id) == ["collection:y", "list:builtin.upcoming"])
    #expect(html.contains("&lt;Kino &amp; Co&gt;") && !html.contains("<Kino"))
    #expect(html.contains("Weitere Reihen (2)"))
    // Skript: Ziehen, Sperre während eines Zugs, Neuladen statt erneut senden.
    #expect(html.contains("pointerdown") && html.contains("classList.add('busy')") && html.contains("location.replace"))
    #expect(!html.contains("f.submit()"))
}

@Test func orderSectionEmptyAndNotes() {
    let page = PhoneInputPage(token: "tok")
    let (r1, _) = page.handle(req("GET /?t=tok&ok=home HTTP/1.1\r\n\r\n"), profileName: "Ich") { Data() }
    let h1 = String(data: r1.body, encoding: .utf8)!
    #expect(h1.contains("Keine Reihen auf der Startseite.") && h1.contains("✓ Am Fernseher geändert.") && !h1.contains("Eingabe(n)"))
    // Die Rückmeldung `ok` wird nicht roh in die Seite geschrieben.
    let (r2, _) = page.handle(req("GET /?t=tok&ok=%3Cimg%20onerror%3Dx%3E HTTP/1.1\r\n\r\n"), profileName: "Ich") { Data() }
    let h2 = String(data: r2.body, encoding: .utf8)!
    #expect(!h2.contains("<img") && h2.contains("&lt;img onerror=x&gt;"))
}

@Test func homePostProducesOneCommandAndRedirectsToOrder() {
    let page = PhoneInputPage(token: "tok")
    func run(_ op: String) -> (HTTPResponse, [PhoneCommand]) {
        page.handle(post("/home?t=tok", "op=" + op.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!), profileName: "Ich", home: state()) { Data() }
    }
    let (resp, cmds) = run("to:\(b.uuidString):0")
    #expect(cmds == [.moveRow(id: b, to: 0)] && resp.status == 303 && resp.extraHeaders["Location"] == "/?t=tok&ok=home#order")
    #expect(run("to:\(a.uuidString):1").1 == [.moveRow(id: a, to: 1)])
    #expect(run("to:\(a.uuidString.lowercased()):99").1 == [.moveRow(id: a, to: 2)])
    #expect(run("to:\(c.uuidString):-3").1 == [.moveRow(id: c, to: 0)])
    #expect(run("hide:\(b.uuidString)").1 == [.removeRow(b)])
    #expect(run("restore:\(d.uuidString)").1 == [.restoreRow(d)])
    #expect(run("show:list:builtin.upcoming").1 == [.addRow(key: "list:builtin.upcoming")])
    // Leerlauf und Unbekanntes: kein Befehl, eigene Rückmeldung. Relative Züge gibt es nicht mehr.
    let (r0, c0) = run("to:\(a.uuidString):0")
    #expect(c0.isEmpty && r0.extraHeaders["Location"] == "/?t=tok&ok=home0#order")
    for bad in ["show:list:builtin.continue", "show:collection:zz", "show:list:tmdb:list:7", "hide:\(UUID().uuidString)", "hide:\(d.uuidString)",
                "restore:\(a.uuidString)", "restore:kaputt", "up:\(b.uuidString)", "top:\(c.uuidString)", "to:\(a.uuidString):x",
                "to:kaputt:1", "fly:\(a.uuidString)", "", "top"] {
        #expect(run(bad).1.isEmpty, "\(bad)")
    }
    // Ohne Token kein Befehl.
    let (forbidden, none) = page.handle(post("/home?t=falsch", "op=hide:\(b.uuidString)"), profileName: "Ich", home: state()) { Data() }
    #expect(forbidden.status == 403 && none.isEmpty)
    #expect(cmds.allSatisfy(\.isHomeEdit) && !PhoneCommand.addAddon("x").isHomeEdit && PhoneCommand.removeRow(a).isHomeEdit
            && PhoneCommand.restoreRow(a).isHomeEdit)
}

@Test func layoutAppliesPhoneCommands() {
    var l = layout()
    var hidden: [HomeRow] = []
    let rowC = l.rows[2]
    #expect(l.applyPhone(.moveRow(id: c, to: 0), hidden: &hidden, options: options) == .moved(rowC, from: 2, to: 0))
    #expect(l.rows.map(\.id) == [c, a, b])
    #expect(l.applyPhone(.moveRow(id: c, to: -5), hidden: &hidden, options: options) == nil)
    #expect(l.applyPhone(.moveRow(id: c, to: 99), hidden: &hidden, options: options) == .moved(rowC, from: 0, to: 2))
    #expect(l.rows.map(\.id) == [a, b, c])
    // Ausblenden merkt die Reihe vollständig (ID und Stil).
    var styled = l.rows[1]; styled.style = .landscape; l.rows[1] = styled
    #expect(l.applyPhone(.removeRow(b), hidden: &hidden, options: options) == .removed(styled, at: 1))
    #expect(l.rows.map(\.id) == [a, c] && hidden == [styled])
    #expect(l.applyPhone(.removeRow(b), hidden: &hidden, options: options) == nil)
    // Wieder einblenden: unverändert unten an, aus „Ausgeblendet“ heraus; zweimal wirkt nicht doppelt.
    #expect(l.applyPhone(.restoreRow(b), hidden: &hidden, options: options) == .restored(styled, at: 2))
    #expect(l.rows.map(\.id) == [a, c, b] && l.rows[2].style == .landscape && hidden.isEmpty)
    #expect(l.applyPhone(.restoreRow(b), hidden: &hidden, options: options) == nil)
    // Hinzufügen eines Angebots hängt unten an, keine Doppelten, nur bekannte Angebote.
    guard case .added(let added, at: 3)? = l.applyPhone(.addRow(key: "collection:y"), hidden: &hidden, options: options) else {
        Issue.record("addRow"); return
    }
    #expect(l.rows.last == added && added.style == .collectionTiles)
    #expect(l.applyPhone(.addRow(key: "collection:y"), hidden: &hidden, options: options) == nil)
    #expect(l.applyPhone(.addRow(key: "collection:nix"), hidden: &hidden, options: options) == nil)
    #expect(l.applyPhone(.addAddon("x"), hidden: &hidden, options: options) == nil)
    #expect(l.rows.count == 4)
}

@Test func hiddenRowsCappedAndRestoreSkipsDuplicates() {
    var l = HomeLayout(rows: (0..<(HomeLayout.hiddenLimit + 5)).map { HomeRow(content: .collection(id: "c\($0)")) })
    var hidden: [HomeRow] = []
    let ids = l.rows.map(\.id)
    for id in ids { l.applyPhone(.removeRow(id), hidden: &hidden, options: []) }
    #expect(l.rows.isEmpty && hidden.count == HomeLayout.hiddenLimit && hidden.first?.id == ids[5] && hidden.last?.id == ids.last)
    // Inhalt liegt inzwischen wieder auf der Startseite: Wiederherstellen fügt nichts doppelt ein, nimmt ihn aber aus der Liste.
    let back = hidden[0]
    l.rows.append(HomeRow(content: back.content))
    #expect(l.applyPhone(.restoreRow(back.id), hidden: &hidden, options: []) == nil)
    #expect(l.rows.count == 1 && !hidden.contains { $0.id == back.id })
    // Hinzufügen eines Angebots räumt eine gemerkte Reihe mit gleichem Inhalt ab.
    let other = hidden[0]
    l.applyPhone(.addRow(key: other.content.key), hidden: &hidden, options: [other.content])
    #expect(!hidden.contains { $0.content.key == other.content.key })
}

@Test func profileDecodesHiddenRowsWithDefault() throws {
    var p = Profile.makeDefault()
    #expect(p.hiddenRows.isEmpty)
    p.hiddenRows = [hiddenRow]
    let back = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(p))
    #expect(back.hiddenRows == [hiddenRow])
    let old = try JSONDecoder().decode(Profile.self, from: Data(#"{"id":"00000000-0000-0000-0000-000000000001","name":"Alt"}"#.utf8))
    #expect(old.hiddenRows.isEmpty && old.name == "Alt")
}

// Welle F-a (E7): Icon-Satz-Adresse nur noch am Handy, im Abschnitt „System“.
@Test func phoneIconSetFieldBecomesCommand() {
    let page = PhoneInputPage(token: "tok")
    let (_, cmds) = page.handle(post("/submit?t=tok", "icon_set=+https%3A%2F%2Fexample.com%2Ficons.json+"), profileName: "Ich") { Data() }
    #expect(cmds == [.setRatingIconSet("https://example.com/icons.json")])
    let (_, none) = page.handle(post("/submit?t=tok", "icon_set=+"), profileName: "Ich") { Data() }
    #expect(none.isEmpty)
    let html = page.page(profileName: "Ich", note: nil)
    let system = html.range(of: "id=system>")?.lowerBound
    let field = html.range(of: "name=icon_set")?.lowerBound
    #expect(system != nil && field != nil && field! > system!)
    #expect(!PhoneCommand.setRatingIconSet("https://x").isHomeEdit)
}

// Welle F-f: Löschen vom Handy – Knopf mit Rückfrage, eigener Befehl, Reihe landet nicht unter „Ausgeblendet“.
@Test func phoneDeleteRowAsksAndDeletesForGood() {
    let page = PhoneInputPage(token: "tok")
    let (resp, _) = page.handle(req("GET /?t=tok HTTP/1.1\r\n\r\n"), profileName: "Ich", home: state()) { Data() }
    let html = String(data: resp.body, encoding: .utf8)!
    #expect(html.contains("value=\"delete:\(b.uuidString)\" aria-label=\"Löschen\"") && html.contains("data-confirm="))
    #expect(html.contains("window.confirm(b.dataset.confirm)"))
    func run(_ op: String) -> [PhoneCommand] {
        page.handle(post("/home?t=tok", "op=" + op.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!), profileName: "Ich", home: state()) { Data() }.1
    }
    #expect(run("delete:\(b.uuidString)") == [.deleteRow(b)])
    #expect(run("delete:\(d.uuidString)").isEmpty && run("delete:\(UUID().uuidString)").isEmpty && run("delete:kaputt").isEmpty)
    #expect(PhoneCommand.deleteRow(a).isHomeEdit)
    var l = layout()
    var hidden: [HomeRow] = []
    let rowB = l.rows[1]
    #expect(l.applyPhone(.deleteRow(b), hidden: &hidden, options: options) == .deleted(rowB, at: 1))
    #expect(l.rows.map(\.id) == [a, c] && hidden.isEmpty)
    #expect(l.applyPhone(.deleteRow(b), hidden: &hidden, options: options) == nil)
}
