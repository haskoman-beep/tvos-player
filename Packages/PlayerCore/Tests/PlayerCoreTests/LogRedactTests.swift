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
