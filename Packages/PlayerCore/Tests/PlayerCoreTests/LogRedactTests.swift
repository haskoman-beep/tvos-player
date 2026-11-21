import Foundation
import Testing
@testable import PlayerCore

// Schlüssel in diesen Tests sind erfunden.

@Test func redactTorrentioKeyInPath() {
    let u = "https://torrentio.strem.fun/providers=yts,eztv|debridoptions=nodownloadlinks|realdebrid=ABCDEF1234567890XYZ/stream/movie/tt0111161.json"
    let r = LogRedact.url(u)
    #expect(r == "https://torrentio.strem.fun/…/tt0111161.json")
    #expect(!r.contains("ABCDEF1234567890XYZ"))
}

@Test func redactTorrentioResolveLinkKeepsNothingSecret() {
    // Auflöse-Link: Schlüssel und Infohash im Pfad, letzte Komponente Dateiname.
    let u = "https://torrentio.strem.fun/resolve/realdebrid/ABCDEF1234567890XYZ/0123456789abcdef0123456789abcdef01234567/null/0/Film.Name.2023.2160p.WEB-DL.mkv"
    let r = LogRedact.url(u)
    #expect(r == "https://torrentio.strem.fun/…/Film.Name.2023.2160p.WEB-DL.mkv")
    #expect(!r.contains("ABCDEF1234567890XYZ"))
}

@Test func redactTorBoxTokenInQuery() {
    let u = "https://api.torbox.app/v1/api/torrents/requestdl?token=0a1b2c3d-4e5f-6789-abcd-ef0123456789&torrent_id=123&file_id=4&redirect=true"
    let r = LogRedact.url(u)
    #expect(r == "https://api.torbox.app/…/requestdl")
    #expect(!r.contains("token"))
}

@Test func redactTorBoxCDNUUIDAsLastComponent() {
    let u = "https://store-031.weur.tb-cdn.st/zip/0a1b2c3d-4e5f-6789-abcd-ef0123456789?token=abc"
    #expect(LogRedact.url(u) == "https://store-031.weur.tb-cdn.st/…")
}

@Test func redactRealDebridDownload() {
    let u = "https://abc12.download.real-debrid.com/d/QWERTYUIOP12345/Serie.S01E02.German.DL.1080p.mkv"
    let r = LogRedact.url(u)
    #expect(r == "https://abc12.download.real-debrid.com/…/Serie.S01E02.German.DL.1080p.mkv")
    #expect(!r.contains("QWERTYUIOP12345"))
}

@Test func redactRealDebridAPIWithAuthQuery() {
    let u = "https://api.real-debrid.com/rest/1.0/unrestrict/link?auth_token=SECRETSECRET123"
    #expect(LogRedact.url(u) == "https://api.real-debrid.com/…/link")
}

@Test func redactAIOStreamsUUIDAndConfig() {
    let u = "https://aiostreams.example.org/stremio/0a1b2c3d-4e5f-6789-abcd-ef0123456789/eyJhbGciOiJIUzI1NiJ9eyJjb25maWciOnRydWV9/manifest.json"
    let r = LogRedact.url(u)
    #expect(r == "https://aiostreams.example.org/…/manifest.json")
    #expect(!r.contains("eyJ"))
    #expect(!r.contains("0a1b2c3d"))
}

@Test func redactAIOStreamsPlaybackTokenLast() {
    let u = "https://aiostreams.example.org/api/v1/debrid/playback/eyJhbGciOiJIUzI1NiJ9eyJjb25maWciOnRydWV9"
    #expect(LogRedact.url(u) == "https://aiostreams.example.org/…")
}

@Test func redactEncodedKeyValueLast() {
    // realdebrid%3DKEY entschlüsselt = realdebrid=KEY → Schlüssel
    #expect(LogRedact.url("https://h.example/realdebrid%3DSHORT") == "https://h.example/…")
}

@Test func redactCredentialsPortFragmentAndCase() {
    #expect(LogRedact.url("HTTP://user:pw@Media.Example.com:8080/a/b/c.mp4#t=10") == "http://media.example.com:8080/…/c.mp4")
    #expect(LogRedact.url("https://example.com") == "https://example.com")
    #expect(LogRedact.url("https://example.com/") == "https://example.com")
    #expect(LogRedact.url("https://example.com/?apikey=1") == "https://example.com")
    #expect(LogRedact.url("https://example.com/watch") == "https://example.com/watch")
    #expect(LogRedact.url(URL(string: "https://example.com/x/y.json?k=1")!) == "https://example.com/…/y.json")
}

@Test func redactShortensLongLastComponent() {
    let name = "Ein.Sehr.Langer.Filmname.Mit.Vielen.Teilen.2023.2160p.UHD.BluRay.mkv"
    let r = LogRedact.url("https://cdn.example.com/\(name)")
    #expect(r.hasPrefix("https://cdn.example.com/Ein.Sehr.Langer"))
    #expect(r.hasSuffix("…"))
    #expect(r.count == "https://cdn.example.com/".count + LogRedact.maxLastComponent)
}

@Test func redactLeavesNonURLsAlone() {
    #expect(LogRedact.url("kein Link") == "kein Link")
    #expect(LogRedact.text("Laden fehlgeschlagen: Zeitüberschreitung") == "Laden fehlgeschlagen: Zeitüberschreitung")
}

@Test func redactTextFindsAllURLs() {
    let line = "Error Domain=NSURLErrorDomain Code=-1001 UserInfo={NSErrorFailingURLStringKey=https://api.torbox.app/v1/api/torrents/requestdl?token=SECRET123&x=1, NSErrorFailingURLKey=https://api.torbox.app/v1/api/torrents/requestdl?token=SECRET123&x=1}"
    let r = LogRedact.text(line)
    #expect(!r.contains("SECRET123"))
    #expect(r == "Error Domain=NSURLErrorDomain Code=-1001 UserInfo={NSErrorFailingURLStringKey=https://api.torbox.app/…/requestdl, NSErrorFailingURLKey=https://api.torbox.app/…/requestdl}")
}

@Test func redactTextKeepsTrailingPunctuationAndQuotes() {
    #expect(LogRedact.text("open url=\"https://h.example/a/b.mkv?sig=XYZ\".") == "open url=\"https://h.example/…/b.mkv\".")
    #expect(LogRedact.text("(siehe https://h.example/watch).") == "(siehe https://h.example/watch).")
}

@Test func redactIsIdempotent() {
    let samples = [
        "Engine öffnet https://torrentio.strem.fun/realdebrid=ABCDEF1234567890XYZ/stream/movie/tt0111161.json jetzt",
        "a https://abc12.download.real-debrid.com/d/QWERTYUIOP12345/Ein.Sehr.Langer.Filmname.Mit.Vielen.Teilen.2023.2160p.mkv b",
        "x https://aiostreams.example.org/api/v1/debrid/playback/eyJhbGciOiJIUzI1NiJ9eyJjb25maWciOnRydWV9 y",
        "https://example.com/watch",
    ]
    for s in samples {
        let once = LogRedact.text(s)
        #expect(LogRedact.text(once) == once)
    }
}

// MARK: Fix-Runde 1

@Test func redactTextTorrentioFullConfig() {
    let raw = "Laden https://torrentio.strem.fun/providers=yts,eztv|debridoptions=nodownloadlinks|realdebrid=ABCDEF1234567890XYZ/stream/movie/tt0111161.json fertig"
    #expect(LogRedact.text(raw) == "Laden https://torrentio.strem.fun/…/tt0111161.json fertig")
    let enc = "Laden https://torrentio.strem.fun/providers=yts,eztv%7Cdebridoptions=nodownloadlinks%7Crealdebrid=ABCDEF1234567890XYZ/stream/movie/tt0111161.json fertig"
    #expect(LogRedact.text(enc) == "Laden https://torrentio.strem.fun/…/tt0111161.json fertig")
    #expect(LogRedact.text("https://torrentio.strem.fun/providers=yts|realdebrid=ABCDEF1234567890XYZ") == "https://torrentio.strem.fun/…")
}

@Test func redactTextSchemelessAddonURL() {
    let line = "Addon torrentio.strem.fun/providers=yts|realdebrid=ABCDEF1234567890XYZ/manifest.json hinzugefügt"
    #expect(LogRedact.text(line) == "Addon torrentio.strem.fun/…/manifest.json hinzugefügt")
    #expect(LogRedact.text("Port aio.example.org:8443/0a1b2c3d-4e5f-6789-abcd-ef0123456789/x") == "Port aio.example.org:8443/…/x")
    // Kein Host → nichts anfassen
    #expect(LogRedact.text("Laden 3/4 · Fehler 1/2") == "Laden 3/4 · Fehler 1/2")
}

@Test func redactIPv6Host() {
    #expect(LogRedact.url("http://[FE80::1]:11470/realdebrid=ABCDEF1234567890XYZ/stream/movie/tt1.json")
            == "http://[fe80::1]:11470/…/tt1.json")
    #expect(LogRedact.text("open http://[fe80::1]:11470/realdebrid=ABCDEF1234567890XYZ/stream.json.")
            == "open http://[fe80::1]:11470/…/stream.json.")
}

@Test func redactUserinfoWithQueryAndHashChars() {
    #expect(LogRedact.url("https://user:p?a#ss@Host.example/a/b.mkv?x=1") == "https://host.example/…/b.mkv")
    #expect(LogRedact.text("x https://user:p?a#ss@host.example/b.mkv y") == "x https://host.example/b.mkv y")
}

@Test func redactKeyValuePairsInText() {
    let poll = DevicePoll.success(SyncToken(accessToken: "abcdef123", refreshToken: "ghijkl456", expiresAt: nil))
    let r = LogRedact.text("trakt Login: \(poll)")
    #expect(!r.contains("abcdef123"))
    #expect(!r.contains("ghijkl456"))
    #expect(r.contains("refreshToken: Optional(\"…\")"))
    #expect(LogRedact.text("token=abc123&x=1") == "token=…&x=1")
    #expect(LogRedact.text("TOKEN = ABC") == "TOKEN = …")
    #expect(LogRedact.text(#"{"api_key":"xyz789","n":1}"#) == #"{"api_key":"…","n":1}"#)
    #expect(LogRedact.text("apiKey: qwe, password=hunter2; secret:s3cr3t") == "apiKey: …, password=…; secret:…")
    #expect(LogRedact.text("auth_token=a1 access-token: b2") == "auth_token=… access-token: …")
    // Keine Paare → unverändert
    #expect(LogRedact.text("Befehle: key torbox, nuvio-url") == "Befehle: key torbox, nuvio-url")
    #expect(LogRedact.text("Token abgelaufen · NSErrorFailingURLStringKey") == "Token abgelaufen · NSErrorFailingURLStringKey")
    #expect(LogRedact.text(LogRedact.text("trakt Login: \(poll)")) == r)
}

@Test func redactOpaqueRunsInText() {
    let key32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345"
    #expect(LogRedact.text("RD-Schlüssel \(key32) gesetzt") == "RD-Schlüssel … gesetzt")
    let k31 = String(key32.dropLast())
    #expect(LogRedact.text("kurz \(k31) ok") == "kurz \(k31) ok")
    #expect(LogRedact.text("Hash 0123456789abcdef0123456789abcdef01234567") == "Hash …")
}

@Test func redactLooksSecretExtendedChars() {
    #expect(LogRedact.looksSecret("abc+def~ghi123jklmno"))
    #expect(LogRedact.looksSecret("Ab1!Ab1!Ab1!Ab1!Ab1!Ab1!"))
    #expect(!LogRedact.looksSecret("Ab1!Ab1!Ab1!Ab1!Ab1!"))
    #expect(!LogRedact.looksSecret("Serie.S01E02.German.DL.1080p.mkv"))
    #expect(!LogRedact.looksSecret("manifest.json"))
}

// MARK: Nachtrag 2

@Test func redactLongRunIsFastAndCapped() {
    let run = String(repeating: "a-", count: 10_000) + "key"          // 20 003 Zeichen
    let line = "token=geheim1 " + run + "=wert9"
    let clock = ContinuousClock()
    var r = ""
    let took = clock.measure { r = LogRedact.text(line) }
    #expect(took < .milliseconds(500))
    #expect(r.hasPrefix("token=… "))
    #expect(!r.contains("geheim1"))
    #expect(r.hasSuffix(LogRedact.cutMarker))
    #expect(r.utf8.count <= LogRedact.maxLineBytes)
    #expect(LogRedact.text(r) == r)
}

@Test func redactLongRunBelowCapIsFastAndMasked() {
    let line = String(repeating: "a-", count: 3_500) + "key=wert9"      // < 8 KB, kein Kürzen
    let clock = ContinuousClock()
    var r = ""
    let took = clock.measure { r = LogRedact.text(line) }
    #expect(took < .milliseconds(500))
    #expect(!r.contains("wert9"))
    #expect(!r.contains(LogRedact.cutMarker))
    // Ohne Schlüssel: lange Folge mit „/“ (Adress-Zweige laufen) bleibt ebenfalls schnell.
    let noKey = String(repeating: "a-b.", count: 2_000) + "/x"
    #expect(clock.measure { _ = LogRedact.text(noKey) } < .milliseconds(500))
}

@Test func redactBearerQuoted() {
    #expect(LogRedact.text(#"Authorization: Bearer "abc def""#) == "Authorization: Bearer …")
    #expect(LogRedact.text("Authorization: Bearer 'abc'") == "Authorization: Bearer …")
}

// MARK: Nachtrag 3

@Test func redactUnterminatedQuotedValues() {
    // Ungekürzt, Anführungszeichen nicht geschlossen
    #expect(!LogRedact.text(#"password: "my secret pass"#).contains("secret pass"))
    #expect(!LogRedact.text("apikey: 'abc def").contains("abc"))
    #expect(!LogRedact.text(#"Authorization: Bearer "abc def"#).contains("abc"))
    // Vorgabe aus dem Review (knapp unter der Grenze)
    #expect(!LogRedact.text(String(repeating: "a", count: 8170) + #" password: "geheim ab"#).contains("geheim"))
    // Kürzung mitten im gequoteten Wert: schließendes Anführungszeichen abgeschnitten
    let cut = LogRedact.text(String(repeating: "a", count: 8150) + #" password: "geheim abcdefghijklmnopqrstuvwxyz0123456789" ende"#)
    #expect(!cut.contains("geheim"))
    #expect(cut.hasSuffix(LogRedact.cutMarker))
    #expect(LogRedact.text(cut) == cut)
}

@Test func redactGrowthStaysWithinCapAndIdempotent() {
    for n in [1_300, 1_500] {                       // 7 800 B (wächst über 8 KB) und 9 000 B (schon zu lang)
        let x = String(repeating: "key=a,", count: n)
        let once = LogRedact.text(x)
        #expect(once.utf8.count <= LogRedact.maxLineBytes)
        #expect(once.hasSuffix(LogRedact.cutMarker))
        #expect(LogRedact.text(once) == once)
    }
}

// MARK: Nachtrag

@Test func redactQuotedValuesWithSpaces() {
    #expect(LogRedact.text("apikey: 'abc def'") == "apikey: '…'")
    #expect(LogRedact.text(#"password: "my secret pass", n=1"#) == #"password: "…", n=1"#)
    #expect(LogRedact.text(#"secret='a b c'"#) == #"secret='…'"#)
    let once = LogRedact.text(#"password: "my secret pass""#)
    #expect(LogRedact.text(once) == once)
}

@Test func redactPrefixedAndCamelCaseKeys() {
    #expect(LogRedact.text("x_api_key=abc1 userToken: t2 clientSecret=s3 session_key=k4")
            == "x_api_key=… userToken: … clientSecret=… session_key=…")
    #expect(LogRedact.text("x-api-key: k5") == "x-api-key: …")
    // Kein `:`/`=` direkt nach dem Schlüssel → unverändert
    #expect(LogRedact.text("Taste keyboard: K95, Keyboard=an, Schlüssel fehlt") == "Taste keyboard: K95, Keyboard=an, Schlüssel fehlt")
    // Schon gekürzte Adresse als Wert bleibt lesbar (NSError-UserInfo)
    #expect(LogRedact.text("NSErrorFailingURLStringKey=https://api.torbox.app/v1/x/requestdl?token=S1")
            == "NSErrorFailingURLStringKey=https://api.torbox.app/…/requestdl")
}

@Test func redactSchemelessIPAndLocalhost() {
    #expect(LogRedact.text("Addon 10.0.0.5:7000/realdebrid=ABCDEF1234567890XYZ/manifest.json neu")
            == "Addon 10.0.0.5:7000/…/manifest.json neu")
    #expect(LogRedact.text("Addon 10.0.0.7/0a1b2c3d-4e5f-6789-abcd-ef0123456789") == "Addon 10.0.0.7/…")
    #expect(LogRedact.text("lokal localhost:7000/abc/def/stream.json?k=1") == "lokal localhost:7000/…/stream.json")
    #expect(LogRedact.text("Version 0.4.0/1 bleibt") == "Version 0.4.0/1 bleibt")
    let once = LogRedact.text("Addon 10.0.0.5:7000/realdebrid=ABCDEF1234567890XYZ/manifest.json")
    #expect(LogRedact.text(once) == once)
}

@Test func redactBearer() {
    #expect(LogRedact.text("Authorization: Bearer eyJabc.def-ghi_jkl") == "Authorization: Bearer …")
    #expect(LogRedact.text("header authorization: bearer abc123") == "header authorization: bearer …")
    #expect(LogRedact.text(LogRedact.text("Authorization: Bearer x1")) == "Authorization: Bearer …")
}

@Test func imageBudgetScalesWithAvailableMemory() {
    let mb = ImageCacheBudget.mb
    // Unbekannt → bisherige feste Grenze
    #expect(ImageCacheBudget.limit(availableBytes: 0, playback: false) == ImageCacheBudget.maximum)
    #expect(ImageCacheBudget.limit(availableBytes: 0, playback: true) == ImageCacheBudget.playbackMaximum)
    // Viel frei → gedeckelt
    #expect(ImageCacheBudget.limit(availableBytes: UInt64(2000 * mb), playback: false) == 160 * mb)
    // 400 MB frei + 40 MB im Cache → 25 % von 440 MB = 110 MB
    #expect(ImageCacheBudget.limit(availableBytes: UInt64(400 * mb), cachedBytes: 40 * mb, playback: false) == 110 * mb)
    // Knapp → Untergrenze
    #expect(ImageCacheBudget.limit(availableBytes: UInt64(20 * mb), playback: false) == ImageCacheBudget.minimum)
    // Wiedergabe → höchstens 24 MB, auch bei viel freiem Speicher
    #expect(ImageCacheBudget.limit(availableBytes: UInt64(2000 * mb), playback: true) == 24 * mb)
    #expect(ImageCacheBudget.limit(availableBytes: UInt64(70 * mb), playback: true) == 17 * mb + mb / 2)
}

@Test func imageBudgetChangeThreshold() {
    let mb = ImageCacheBudget.mb
    #expect(!ImageCacheBudget.changedEnough(old: 100 * mb, new: 104 * mb))
    #expect(ImageCacheBudget.changedEnough(old: 100 * mb, new: 90 * mb))
    #expect(ImageCacheBudget.changedEnough(old: 20 * mb, new: 16 * mb))
    #expect(!ImageCacheBudget.changedEnough(old: 16 * mb, new: 16 * mb))
}
