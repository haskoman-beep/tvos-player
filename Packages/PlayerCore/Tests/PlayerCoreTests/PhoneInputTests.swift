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

private func layout() -> HomeLayout {
    HomeLayout(rows: [HomeRow(id: a, content: .list(.continueWatching)),
                      HomeRow(id: b, content: .list(.watchlist)),
                      HomeRow(id: c, content: .collection(id: "x"))])
}

private let options: [RowContent] = [.collection(id: "x"), .collection(id: "y"), .list(.continueWatching),
                                     .list(.upcoming), .collection(id: "y")]

private func state() -> PhoneHomeState {
    PhoneHomeState.make(layout: layout(), options: options, title: { o in
        switch o { case .list(let s): s.title; case .collection(let id): id == "y" ? "<Kino & Co>" : "Coll \(id)" }
    }, detail: { o in if case .collection = o { "Collection" } else { "Liste" } })
}

@Test func phoneSectionsInTargetOrderWithAnchors() {
    #expect(PhoneSection.allCases.map(\.title) == ["Schnell-Import", "Addons & Quellen", "Konten & Schlüssel", "Startseite", "System"])
    #expect(PhoneSection.allCases.map(\.rawValue) == ["import", "addon", "keys", "home", "system"])
    #expect(PhoneSection.url("http://h/?t=x", section: .home) == "http://h/?t=x#home")
    #expect(PhoneSection.url("http://h/?t=x", section: nil) == "http://h/?t=x")
    let page = PhoneInputPage(token: "tok")
    let (resp, _) = page.handle(req("GET /?t=tok HTTP/1.1\r\n\r\n"), profileName: "Ich", home: state()) { Data() }
    let html = String(data: resp.body, encoding: .utf8)!
    let pos = ["id=import>", "id=addon>", "id=keys>", "id=home>", "id=order>", "id=system>"].map { html.range(of: $0)?.lowerBound }
    #expect(pos.allSatisfy { $0 != nil })
    #expect(pos.compactMap { $0 } == pos.compactMap { $0 }.sorted())
    // Bestehende Felder bleiben (Namen unverändert), Schlüssel im Abschnitt „Konten & Schlüssel“, TorBox bei Addons.
    for name in ["import", "addon", "key_tmdb", "key_mdblist", "key_tvdb", "key_trakt_id", "key_trakt_secret", "key_simkl_id",
                 "key_torbox", "key_atvloadly", "nuvio_url", "nuvio_json", "tmdb_link", "kit_url", "backup_json"] {
        #expect(html.contains("name=\(name)"), "Feld \(name)")
    }
    // Schlüsselfelder sind leer: die Seite gibt nie gespeicherte Werte zurück.
    #expect(!html.contains("value=\"K"))
}

@Test func orderSectionListsRowsEscapedWithButtons() {
    let page = PhoneInputPage(token: "tok")
    let (resp, cmds) = page.handle(req("GET /?t=tok HTTP/1.1\r\n\r\n"), profileName: "Ich", home: state()) { Data() }
    let html = String(data: resp.body, encoding: .utf8)!
    #expect(cmds.isEmpty)
    #expect(html.contains("Startseite ordnen") && html.contains("action=\"/home?t=tok\""))
    #expect(html.contains("value=\"up:\(b.uuidString)\"") && html.contains("value=\"hide:\(c.uuidString)\""))
    #expect(html.contains("value=\"top:\(a.uuidString)\" aria-label=\"Ganz nach oben\" title=\"Ganz nach oben\" disabled"))
    #expect(html.contains("value=\"bottom:\(c.uuidString)\" aria-label=\"Ganz nach unten\" title=\"Ganz nach unten\" disabled"))
    // Ausgeblendet: nur Angebote, die nicht auf der Startseite liegen, ohne Doppelte; Titel maskiert.
    #expect(state().hidden.map(\.id) == ["collection:y", "list:builtin.upcoming"])
    #expect(html.contains("&lt;Kino &amp; Co&gt;") && !html.contains("<Kino"))
    #expect(html.contains("Ausgeblendet (2)"))
    #expect(html.contains("pointerdown"))
}

@Test func orderSectionEmptyAndNotes() {
    let page = PhoneInputPage(token: "tok")
    let (r1, _) = page.handle(req("GET /?t=tok&ok=home HTTP/1.1\r\n\r\n"), profileName: "Ich") { Data() }
    let h1 = String(data: r1.body, encoding: .utf8)!
    #expect(h1.contains("Keine Reihen auf der Startseite.") && h1.contains("✓ Am Fernseher geändert.") && !h1.contains("Eingabe(n)"))
    // Die Rückmeldung `ok` wird nicht roh in die Seite geschrieben.
    let (r2, _) = page.handle(req("GET /?t=tok&ok=%3Cscript%3E HTTP/1.1\r\n\r\n"), profileName: "Ich") { Data() }
    #expect(!String(data: r2.body, encoding: .utf8)!.contains("<script>x") && String(data: r2.body, encoding: .utf8)!.contains("&lt;script&gt;"))
}

@Test func homePostProducesOneCommandAndRedirectsToOrder() {
    let page = PhoneInputPage(token: "tok")
    func run(_ op: String) -> (HTTPResponse, [PhoneCommand]) {
        page.handle(post("/home?t=tok", "op=" + op.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!), profileName: "Ich", home: state()) { Data() }
    }
    let (resp, cmds) = run("up:\(b.uuidString)")
    #expect(cmds == [.moveRow(id: b, to: 0)] && resp.status == 303 && resp.extraHeaders["Location"] == "/?t=tok&ok=home#order")
    #expect(run("down:\(b.uuidString)").1 == [.moveRow(id: b, to: 2)])
    #expect(run("top:\(c.uuidString)").1 == [.moveRow(id: c, to: 0)])
    #expect(run("bottom:\(a.uuidString)").1 == [.moveRow(id: a, to: 2)])
    #expect(run("to:\(a.uuidString):1").1 == [.moveRow(id: a, to: 1)])
    #expect(run("to:\(a.uuidString.lowercased()):99").1 == [.moveRow(id: a, to: 2)])
    #expect(run("hide:\(b.uuidString)").1 == [.removeRow(b)])
    #expect(run("show:list:builtin.upcoming").1 == [.addRow(key: "list:builtin.upcoming")])
    // Leerlauf und Unbekanntes: kein Befehl, eigene Rückmeldung.
    let (r0, c0) = run("up:\(a.uuidString)")
    #expect(c0.isEmpty && r0.extraHeaders["Location"] == "/?t=tok&ok=home0#order")
    for bad in ["show:list:builtin.continue", "show:collection:zz", "hide:\(UUID().uuidString)", "up:kaputt", "to:\(a.uuidString):x", "fly:\(a.uuidString)", "", "top"] {
        #expect(run(bad).1.isEmpty, "\(bad)")
    }
    // Ohne Token kein Befehl.
    let (forbidden, none) = page.handle(post("/home?t=falsch", "op=hide:\(b.uuidString)"), profileName: "Ich", home: state()) { Data() }
    #expect(forbidden.status == 403 && none.isEmpty)
    #expect(cmds.allSatisfy(\.isHomeEdit) && !PhoneCommand.addAddon("x").isHomeEdit && PhoneCommand.removeRow(a).isHomeEdit)
}

@Test func layoutAppliesPhoneCommands() {
    var l = layout()
    #expect(l.applyPhone(.moveRow(id: c, to: 0), options: options) == .moved(from: 2, to: 0))
    #expect(l.rows.map(\.id) == [c, a, b])
    #expect(l.applyPhone(.moveRow(id: c, to: -5), options: options) == nil)
    #expect(l.applyPhone(.moveRow(id: c, to: 99), options: options) == .moved(from: 0, to: 2))
    #expect(l.rows.map(\.id) == [a, b, c])
    #expect(l.applyPhone(.removeRow(b), options: options) == .removed(at: 1))
    #expect(l.rows.map(\.id) == [a, c])
    #expect(l.applyPhone(.removeRow(b), options: options) == nil)
    // Einblenden hängt unten an (Nutzerentscheidung), keine Doppelten, nur bekannte Angebote.
    #expect(l.applyPhone(.addRow(key: "collection:y"), options: options) == .added(at: 2))
    #expect(l.rows.last?.content == .collection(id: "y") && l.rows.last?.style == .collectionTiles)
    #expect(l.applyPhone(.addRow(key: "collection:y"), options: options) == nil)
    #expect(l.applyPhone(.addRow(key: "collection:nix"), options: options) == nil)
    #expect(l.applyPhone(.addAddon("x"), options: options) == nil)
    #expect(l.rows.count == 3)
}
