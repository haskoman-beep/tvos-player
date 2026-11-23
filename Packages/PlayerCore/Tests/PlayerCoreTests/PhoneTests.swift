import Foundation
import Testing
@testable import PlayerCore

private func req(_ s: String) -> HTTPRequest {
    guard case .complete(let r) = HTTPRequest.parse(Data(s.utf8)) else { fatalError("parse") }
    return r
}

@Test func parsesInChunksAndRespectsLength() {
    let full = "POST /submit?t=abc HTTP/1.1\r\nHost: x\r\nContent-Length: 11\r\n\r\naddon=a%2Fb"
    #expect(HTTPRequest.parse(Data(full.dropLast(3).utf8)) == .incomplete)
    let r = req(full)
    #expect(r.method == "POST" && r.path == "/submit" && r.query["t"] == "abc")
    #expect(r.form["addon"] == "a/b")
    #expect(HTTPRequest.parse(Data("GET / HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n".utf8)) == .tooLarge)
    #expect(HTTPRequest.parse(Data("MÜLL\r\n\r\n".utf8)) == .invalid)
}

@Test func formDecodesPlusAndEmpty() {
    let r = req("POST /submit HTTP/1.1\r\nContent-Length: 21\r\n\r\nkey_tmdb=a+b&addon=&x")
    #expect(r.form["key_tmdb"] == "a b" && r.form["addon"] == "")
}

/// Task 1.4: access is decided on the request head (`PhoneSession`, PhoneSessionTests); the page carries no token.
@Test func pageEscapesNameAndCarriesNoToken() {
    let page = PhoneInputPage()
    let (ok, _) = page.handle(req("GET /?t=tok HTTP/1.1\r\n\r\n"), profileName: "<Ich>") { Data() }
    let html = String(data: ok.body, encoding: .utf8)!
    #expect(ok.status == 200 && html.contains("&lt;Ich&gt;") && html.contains("action=\"/submit\"") && !html.contains("tok"))
}

@Test func submitProducesCommandsAndRedirects() {
    let page = PhoneInputPage()
    let body = "addon=+https%3A%2F%2Fa%2Fmanifest.json+&key_tmdb=K1&key_tvdb=&tmdb_link=list%3A5&nuvio_json=%7B%7D"
    let (resp, cmds) = page.handle(req("POST /submit?t=tok HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"), profileName: "Ich") { Data() }
    #expect(resp.status == 303 && resp.extraHeaders["Location"] == "/?ok=4")
    #expect(cmds == [.addAddon("https://a/manifest.json"), .setKey(service: "tmdb", value: "K1"),
                     .importCollectionCode(Data("{}".utf8)), .addTMDBLink("list:5")])
}

@Test func exportServesBackup() {
    let page = PhoneInputPage()
    let (resp, _) = page.handle(req("GET /export?t=tok HTTP/1.1\r\n\r\n"), profileName: "Ich") { Data("{\"a\":1}".utf8) }
    #expect(resp.contentType == "application/json" && resp.body == Data("{\"a\":1}".utf8))
    let raw = String(data: resp.serialized, encoding: .utf8)!
    #expect(raw.hasPrefix("HTTP/1.1 200 OK\r\n") && raw.contains("Content-Length: 7\r\n") && raw.hasSuffix("\r\n\r\n{\"a\":1}"))
    #expect(PhoneInputPage.randomToken().count == 10)
}

@Test func sharedImportFieldDetects() {
    #expect(PhoneImportDetect.detect(" https://a.example/x/manifest.json ") == .command(.addAddon("https://a.example/x/manifest.json")))
    #expect(PhoneImportDetect.detect("stremio://a.example/manifest.json") == .command(.addAddon("https://a.example/manifest.json")))
    #expect(PhoneImportDetect.detect("https://www.themoviedb.org/list/5") == .command(.addTMDBLink("https://www.themoviedb.org/list/5")))
    // Wave F-o round 2: JSON links and pasted collection code are detected on the TV (content decides).
    #expect(PhoneImportDetect.detect("https://raw.githubusercontent.com/u/fusion-kit/main/json/a.json") == .command(.importCollectionLink("https://raw.githubusercontent.com/u/fusion-kit/main/json/a.json")))
    #expect(PhoneImportDetect.detect("https://x.example/nuvio-collections.json") == .command(.importCollectionLink("https://x.example/nuvio-collections.json")))
    let nuvio = #"[{"title":"A","folders":[]}]"#
    #expect(PhoneImportDetect.detect(nuvio) == .command(.importCollectionCode(Data(nuvio.utf8))))
    let pack = #"[{"id":"1","title":"Netflix","videoURL":"https://example.invalid/n.mp4"}]"#
    #expect(PhoneImportDetect.detect(pack) == .command(.importCollectionCode(Data(pack.utf8))))
    let widgets = #"{"exportType":"fusionWidgets","widgets":[]}"#
    #expect(PhoneImportDetect.detect(widgets) == .command(.importCollectionCode(Data(widgets.utf8))))
    #expect(PhoneImportDetect.detect(#"{"profiles":[]}"#) == .refused(.backup))
    #expect(PhoneImportDetect.detect("stremio://a.example/catalog") == .unknown)
    #expect(PhoneImportDetect.detect("hallo") == .unknown)
    // Über die Seite: unerkannt → eigene Rückmeldung, kein Befehl.
    let page = PhoneInputPage()
    let body = "import=hallo"
    let (resp, cmds) = page.handle(req("POST /submit?t=tok HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"), profileName: "Ich") { Data() }
    #expect(cmds.isEmpty && resp.extraHeaders["Location"] == "/?imp=unknown")
    // Rückmeldung bleibt, auch wenn ein anderes Feld etwas liefert; die Seite zeigt den Grund.
    let body2 = "import=%7B%22profiles%22%3A%5B%5D%7D&key_tmdb=K"
    let (resp2, cmds2) = page.handle(req("POST /submit?t=tok HTTP/1.1\r\nContent-Length: \(body2.utf8.count)\r\n\r\n\(body2)"), profileName: "Ich") { Data() }
    #expect(cmds2 == [.setKey(service: "tmdb", value: "K")] && resp2.extraHeaders["Location"] == "/?ok=1&imp=backup")
    let (shown, _) = page.handle(req("GET /?t=tok&ok=1&imp=backup HTTP/1.1\r\n\r\n"), profileName: "Ich") { Data() }
    #expect(String(data: shown.body, encoding: .utf8)!.contains("Sicherung wiederherstellen“ nutzen"))
}
