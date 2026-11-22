import Foundation
import Testing
@testable import PlayerCore

@Test func parsesRemuxTraits() {
    let s = StreamItem(name: "[TB⚡] AIOStreams 2160p", description: "Breaking.Bad.S01E02.2160p.DV.HDR.TrueHD.Atmos 🇩🇪 🇬🇧 💾 45.2 GB", url: "https://x/y.mkv")
    let t = StreamTraits.parse(s)
    #expect(t.resolution == "2160p")
    #expect(t.hdr == ["DV", "HDR"])
    #expect(t.audio == ["Atmos", "TrueHD"])
    #expect(t.languages == ["de", "en"])
    #expect(t.sizeBytes == 45_200_000_000)
    #expect(t.cached == true)
}

@Test func cachedFlags() {
    #expect(StreamTraits.parse(StreamItem(name: "[TB⏳] 1080p")).cached == false)
    #expect(StreamTraits.parse(StreamItem(name: "[TB download] 1080p")).cached == false)
    #expect(StreamTraits.parse(StreamItem(name: "Usenet 1080p")).cached == nil)
}

@Test func tokenDoesNotMatchInsideWords() {
    let t = StreamTraits.parse(StreamItem(description: "Movie.DVDRip.x264.DDP5.1"))
    #expect(t.hdr.isEmpty)
    #expect(t.audio == ["DD+"])
}

@Test func playableFilterKeepsOrder() {
    let a = StreamItem(name: "a", url: "https://a/1.mkv")
    let b = StreamItem(name: "b", infoHash: "abc")
    let c = StreamItem(name: "c", url: "nicht eine url")
    let d = StreamItem(name: "d", url: "http://d/2.mp4")
    #expect(playableStreams([a, b, c, d]) == [a, d])
}

@Test func preferredAudioTrackPicksGermanThenEnglish() {
    let tracks = [AudioTrackInfo(id: 0, language: "jpn"), AudioTrackInfo(id: 1, language: "eng", channels: 6),
                  AudioTrackInfo(id: 2, language: "ger", channels: 2), AudioTrackInfo(id: 3, language: "deu", channels: 6)]
    #expect(preferredAudioTrack(tracks, priority: ["de", "en", "orig"])?.id == 3)
    #expect(preferredAudioTrack(Array(tracks.prefix(2)), priority: ["de", "en", "orig"])?.id == 1)
    #expect(preferredAudioTrack([tracks[0]], priority: ["de", "en", "orig"])?.id == 0)
    #expect(preferredAudioTrack([], priority: ["de"]) == nil)
}

@Test func preferredAudioTrackPrefersPassthroughSurround() {
    let tracks = [AudioTrackInfo(id: 1, language: "ger", channels: 6, codec: "dts"),
                  AudioTrackInfo(id: 2, language: "ger", channels: 6, codec: "eac3"),
                  AudioTrackInfo(id: 3, language: "ger", channels: 2, codec: "aac"),
                  AudioTrackInfo(id: 4, language: "eng", channels: 8, codec: "truehd")]
    #expect(preferredAudioTrack(tracks, priority: ["de", "en"])?.id == 2)
    // Surround schlägt Stereo, auch wenn Stereo durchreichbar wäre.
    let t2 = [AudioTrackInfo(id: 1, language: "de", channels: 2, codec: "ac3"),
              AudioTrackInfo(id: 2, language: "de", channels: 6, codec: "dts")]
    #expect(preferredAudioTrack(t2, priority: ["de"])?.id == 2)
}

@Test func placeholderDetection() {
    #expect(isPlaceholderVideo(duration: 30, expectedRuntimeMinutes: nil))
    #expect(!isPlaceholderVideo(duration: 5400, expectedRuntimeMinutes: nil))
    #expect(isPlaceholderVideo(duration: 1800, expectedRuntimeMinutes: 117))
    #expect(!isPlaceholderVideo(duration: 6900, expectedRuntimeMinutes: 117))
    #expect(!isPlaceholderVideo(duration: 0, expectedRuntimeMinutes: nil))
}

@Test func runtimeParsing() {
    #expect(parseRuntimeMinutes("117 min") == 117)
    #expect(parseRuntimeMinutes("1h 57min") == 117)
    #expect(parseRuntimeMinutes("2 h") == 120)
    #expect(parseRuntimeMinutes(nil) == nil)
    #expect(parseRuntimeMinutes("n/a") == nil)
}

@Test func nextEpisodeSkipsUncached() {
    let a = StreamItem(name: "TB", title: "⏳ 2160p", url: "https://x/a",
                       behaviorHints: StreamBehaviorHints(bingeGroup: "g1"))
    let b = StreamItem(name: "TB", title: "⚡ 1080p", url: "https://x/b",
                       behaviorHints: StreamBehaviorHints(bingeGroup: "g2"))
    #expect(nextEpisodeStream([a, b], bingeGroup: "g1")?.url == "https://x/b")
    #expect(nextEpisodeStream([a], bingeGroup: "g1")?.url == "https://x/a")
}

@Test func lastSourceMatching() throws {
    func st(_ name: String, _ title: String, _ url: String, file: String? = nil, group: String? = nil) throws -> StreamItem {
        var o: [String: Any] = ["name": name, "title": title, "url": url]
        var h: [String: Any] = [:]
        if let file { h["filename"] = file }
        if let group { h["bingeGroup"] = group }
        if !h.isEmpty { o["behaviorHints"] = h }
        return try JSONDecoder().decode(StreamItem.self, from: JSONSerialization.data(withJSONObject: o))
    }
    let old = try st("TB 2160p", "⚡ Film.2160p.mkv", "https://x/alt", file: "Film.2160p.mkv", group: "g4k")
    let last = LastSource(stream: old, addon: "AIO", contentID: "tt1")
    // gleiche Datei mit neuer URL
    let same = try st("TB 2160p", "⚡ Film.2160p.mkv", "https://x/neu", file: "Film.2160p.mkv", group: "g4k")
    let other = try st("TB 1080p", "⚡ Film.1080p.mkv", "https://x/b", file: "Film.1080p.mkv", group: "g1080")
    #expect(last.match(in: [("AIO", other), ("AIO", same)])?.url == "https://x/neu")
    // nächste Folge: andere Datei, gleiche bingeGroup
    let ep2 = try st("TB 2160p", "⚡ Serie.S01E02.2160p.mkv", "https://x/e2", file: "Serie.S01E02.2160p.mkv", group: "g4k")
    #expect(last.match(in: [("AIO", other), ("AIO", ep2)])?.url == "https://x/e2")
    // nichts Passendes
    #expect(last.match(in: [("AIO", try st("XY", "720p", "https://x/c"))]) == nil)
    // altes Fortschrittsformat ohne `sources` lädt weiter
    let book = try JSONDecoder().decode(ProgressBook.self, from: Data(#"{"schemaVersion":1,"entries":{}}"#.utf8))
    #expect(book.lastSource(for: "tt1:1:2") == nil)
    var b2 = book; b2.rememberSource(old, addon: "AIO", for: "tt1:1:2")
    #expect(b2.lastSource(for: "tt1")?.contentID == "tt1:1:2")
}

/// Re-Review R1-I1: 🎫 ist im Prism-Formatter das 1080p-Symbol und sagt nichts über den Cache.
@Test func ticketSaysNothingAboutCache() {
    #expect(StreamTraits.parse(StreamItem(name: "🎫 1080p", title: "Film", url: "https://x")).cached == nil)
    #expect(StreamTraits.parse(StreamItem(name: "🎫 1080p", url: "https://x")).cached == nil)
}

// MARK: Welle F-i: Cache-Zustand aus echten AIOStreams-Formattern

@Test func cacheStatusFromAIOStreamsFormatters() {
    func c(_ name: String, _ desc: String = "") -> Bool? { StreamTraits.parse(StreamItem(name: name, description: desc, url: "https://u")).cached }
    // Prism: Zeile „⚡Ready (TB)“ bzw. „❌ Not Ready (TB)“ unten in der Beschreibung.
    #expect(c("🔥4K UHD", "🎬 Pixels (2015)\n📦 4.91 GB\n⚡Ready (TB) 🔍AIOStreams") == true)
    #expect(c("🔥4K UHD", "🎬 Pixels (2015)\n📦 4.91 GB 🌱 1\n❌ Not Ready (TB) 🔍AIOStreams") == false)
    // Torrentio-Stil: „[TB+]“ / „[TB download]“, auch andere Dienste.
    #expect(c("[TB+] AIOStreams 2160p") == true)
    #expect(c("[AD+] AIOStreams 1080p") == true)
    #expect(c("[TB download] AIOStreams 2160p") == false)
    #expect(c("[RD download] AIOStreams 2160p") == false)
    // GDrive-Stil: „[TB⚡]“ / „[TB⏳]“.
    #expect(c("[TB⚡] AIOStreams 2160p") == true)
    #expect(c("[TB⏳] AIOStreams 2160p") == false)
    // TorBox-Stil: „(Instant TB)“; ohne „Instant“ unbekannt.
    #expect(c("AIOStreams (Instant TB) (2160p)") == true)
    #expect(c("AIOStreams (TB) (2160p)") == nil)
    // Wörter: „Uncached“ enthält „Cached“ und ist trotzdem ungecacht.
    #expect(c("AIO 1080p", "Uncached") == false)
    #expect(c("AIO 1080p", "Not cached") == false)
    #expect(c("AIO 1080p", "Cached (TB)") == true)
    #expect(c("AIO 1080p", "[TB Cached]") == true)
    #expect(c("AIO 1080p", "📡 DMM\n⏬ Uncached") == false)
    // Allgemeine Dienstkürzel, aber nicht „[HDR10+]“.
    #expect(c("[EN+] AIOStreams 1080p") == true)
    #expect(c("AIO 2160p [HDR10+]") == nil)
    // Ton und Bild in Klammern sind keine Dienste (R1-M1).
    #expect(c("AIO 1080p [DD+]") == nil)
    #expect(c("AIO 2160p [DV+]") == nil)
    #expect(c("[DD+] AIO 1080p", "[DV+] HEVC") == nil)
    // Ohne Merkmal: unbekannt.
    #expect(c("🍿 4K • 🌈 DV", "🎬 Pixels (2015)\n💿 WEB-DL ⚙️ HEVC\n💾 12.1 GB") == nil)
    // Strukturiertes Feld geht vor dem Text.
    let hinted = StreamItem(name: "❌ Not Ready", url: "https://u", behaviorHints: StreamBehaviorHints(cached: true))
    #expect(StreamTraits.parse(hinted).cached == true)
}

/// Review F-i I1/M1: Filmtitel und Dateinamen mit Status-Wörtern kippen den Cache-Zustand nicht.
@Test func cacheStatusIgnoresStatusWordsInTitles() {
    func c(_ name: String, _ desc: String, file: String? = nil) -> Bool? {
        var h = StreamBehaviorHints(); h.filename = file
        return StreamTraits.parse(StreamItem(name: name, description: desc, url: "https://u", behaviorHints: h)).cached
    }
    let title = "🎬 I'm Not Ready for Christmas (2015)\n💿 WEB-DL ⚙️ HEVC\n💾 2.1 GB"
    #expect(c("🚀 FHD", title + "\n⚡Ready (TB) 🔍AIOStreams") == true)
    #expect(c("🚀 FHD", title + "\n❌ Not Ready (TB) ✤ Meteor") == false)
    #expect(c("🚀 FHD", title) == nil)
    // „Download“ als Titel oder Dateiname: unbekannt, nur „[TB download]“ zählt.
    #expect(c("🚀 FHD", "🎬 The Download (2019)\n💾 2.1 GB", file: "The.Download.2019.1080p.mkv") == nil)
    #expect(c("AIO 1080p", "Download (2019)") == nil)
    // Torrentio-Beschreibung: Release-Name am Zeilenanfang ist keine Statuszeile (R1-M2).
    #expect(c("Torrentio\n4k", "Not Ready to Make Nice.2023.1080p.WEB-DL.x264\n👤 12 💾 2.1 GB") == nil)
    #expect(c("AIO 1080p", "Not Ready to Make Nice 2023 1080p") == nil)
    // Statuszeile ohne Release-Namen oder mit Statussymbol zählt weiter.
    #expect(c("AIO 1080p", "Not Ready 2.1 GB") == false)
    #expect(c("AIO 1080p", "✖ Not Ready Film.2023.1080p") == false)
    // Dateiname mit Status-Wort zählt nicht.
    #expect(c("AIO 1080p", "💾 2 GB", file: "Not Ready (2020) [Uncached].mkv") == nil)
    // ⚡ geht vor ⏳ (⏳ in anderer Bedeutung).
    #expect(c("[TB⚡] 1080p", "⏳ 2h 10m") == true)
}
