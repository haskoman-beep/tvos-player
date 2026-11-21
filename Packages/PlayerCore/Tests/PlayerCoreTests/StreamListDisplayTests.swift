import Foundation
import Testing
@testable import PlayerCore

// Welle E-b: Quellenliste folgt dem Addon (Reihenfolge, Text, Dubletten, kompakte Plaketten).

private func hints(file: String? = nil, size: Int64? = nil, cached: Bool? = nil) -> StreamBehaviorHints {
    var h = try! JSONDecoder().decode(StreamBehaviorHints.self, from: Data("{}".utf8))
    h.filename = file; h.videoSize = size; h.cached = cached
    return h
}

private let de = SourceRankContext(primaryLanguage: "de", av1Hardware: false)

@Test func dedupeByFilenameAndSizeKeepsFirstAndIds() {
    // Foto Build 35: dieselbe Datei zweimal von AIOStreams, verschiedene (verschlüsselte) Abspiel-Adressen.
    let a = StreamItem(name: "AIO ⚡", description: "🎬 Hotel 3\n💾 5.93 GB", url: "https://aio/p/1/x.mkv",
                       behaviorHints: hints(file: "Hotel.3.1080p.mkv", size: 5_930_000_000))
    let b = StreamItem(name: "AIO ⚡", description: "🎬 Hotel 3\n💾 5.93 GB", url: "https://aio/p/2/x.mkv",
                       behaviorHints: hints(file: "Hotel.3.1080p.mkv", size: 5_930_000_000))
    let c = StreamItem(name: "AIO ⚡", description: "🎬 Hotel 3\n💾 1.42 GB", url: "https://aio/p/3/y.mkv",
                       behaviorHints: hints(file: "Hotel.3.1080p.AV1.mkv", size: 1_420_000_000))
    let list: [(addon: String, stream: StreamItem)] = [("AIO", a), ("AIO", b), ("AIO", c)]
    let out = StreamDedupe.unique(list)
    #expect(out.map(\.stream.id) == [a.id, c.id])
    // Andere Datei gleicher Größe ist keine Dublette.
    let d = StreamItem(name: "AIO", url: "https://aio/p/4", behaviorHints: hints(file: "Other.mkv", size: 5_930_000_000))
    #expect(StreamDedupe.unique([("AIO", a), ("AIO", d)]).count == 2)
}

@Test func dedupeByUrlAndInfoHashWithFileIdx() {
    let u1 = StreamItem(name: "A", description: "x", url: "https://cdn/1")
    let u1b = StreamItem(name: "A", description: "x 👤 47", url: "https://cdn/1")   // Seeder anders → andere id
    #expect(StreamDedupe.unique([("A", u1), ("A", u1b)]).count == 1)
    // Gleicher Torrent, andere Datei (Staffelpaket) bleibt; gleiche Datei (Groß/Klein im Hash egal) fällt weg.
    let h0 = StreamItem(name: "T", description: "e1", infoHash: "ABC", fileIdx: 0)
    let h1 = StreamItem(name: "T", description: "e2", infoHash: "abc", fileIdx: 1)
    let h0b = StreamItem(name: "T", description: "e1 again", infoHash: "abc", fileIdx: 0)
    #expect(StreamDedupe.unique([("T", h0), ("T", h1), ("T", h0b)]).map(\.stream.id) == [h0.id, h1.id])
    // Ohne Schlüssel (kein Hash, keine Adresse, keine Datei+Größe) bleibt alles.
    let n1 = StreamItem(name: "N", description: "a"), n2 = StreamItem(name: "N", description: "b")
    #expect(StreamDedupe.unique([("N", n1), ("N", n2)]).count == 2)
}

@Test func dedupeIsPerAddonButIdsStayUnique() {
    let s = StreamItem(name: "X", description: "same", url: "https://cdn/1")
    let t = StreamItem(name: "Y", description: "other", url: "https://cdn/1")
    // Gleiche Adresse bei zwei Addons: je Addon die erste bleibt.
    #expect(StreamDedupe.unique([("A", s), ("B", t)]).count == 2)
    // Gleiche id nie doppelt (ForEach-Identität), auch über Addons.
    #expect(StreamDedupe.unique([("A", s), ("B", s)]).count == 1)
    // Transitiv: B gleich A über die Datei, C gleich B über die Adresse → C fällt auch weg.
    let a = StreamItem(name: "1", url: "https://u/a", behaviorHints: hints(file: "f.mkv", size: 10))
    let b = StreamItem(name: "2", url: "https://u/b", behaviorHints: hints(file: "f.mkv", size: 10))
    let c = StreamItem(name: "3", url: "https://u/b")
    #expect(StreamDedupe.unique([("A", a), ("A", b), ("A", c)]).map(\.stream.id) == [a.id])
}

@Test func fileIdxDecodesLeniently() throws {
    let json = #"{"streams":[{"name":"a","infoHash":"h","fileIdx":3},{"name":"b","infoHash":"h","fileIdx":"4"},{"name":"c","infoHash":"h","fileIdx":"x"},{"name":"d","url":"https://u"}]}"#
    let s = try JSONDecoder().decode(StreamsResponse.self, from: Data(json.utf8)).streams
    #expect(s.map(\.fileIdx) == [3, 4, nil, nil])
    // Rundreise (Cache auf der Platte) behält das Feld; `id` hängt nicht davon ab.
    let back = try JSONDecoder().decode(StreamItem.self, from: JSONEncoder().encode(s[0]))
    #expect(back == s[0])
    var other = s[0]; other.fileIdx = 9
    #expect(other.id == s[0].id)
}

@Test func orderModeAddonKeepsDeliveryOrderSmartRanks() {
    let en = StreamItem(name: "A 1080p", description: "🇬🇧", url: "https://x/1")
    let ger = StreamItem(name: "B 1080p GERMAN", description: "🇩🇪", url: "https://x/2")
    let list: [(addon: String, stream: StreamItem)] = [("X", en), ("Y", ger)]
    #expect(StreamListOrder.display(list, mode: .addon, context: de).map(\.addon) == ["X", "Y"])
    #expect(StreamListOrder.display(list, mode: .smart, context: de).map(\.addon) == ["Y", "X"])
    // Automatische Wahl ordnet immer klug, auch wenn die Anzeige dem Addon folgt.
    #expect(StreamListOrder.automatic(list, context: de).map(\.addon) == ["Y", "X"])
    // Beide entfernen Dubletten.
    #expect(StreamListOrder.display([("X", en), ("X", en)], mode: .addon, context: de).count == 1)
    #expect(StreamListOrder.automatic([("X", en), ("X", en)], context: de).count == 1)
}

@Test func orderSettingsDecodeDefaults() throws {
    // Altes Profil mit dem früheren Feld smartOrder: neuer Standard „Wie Addon“, kompakte Plaketten.
    let s = try JSONDecoder().decode(SourceSettings.self, from: Data(#"{"smartOrder":true,"tvmazeAirtimes":false}"#.utf8))
    #expect(s.order == .addon && s.appBadges == .compact && !s.tvmazeAirtimes)
    let bad = try JSONDecoder().decode(SourceSettings.self, from: Data(#"{"order":"quatsch","appBadges":"off"}"#.utf8))
    #expect(bad.order == .addon && bad.appBadges == .off)
    var q = SourceSettings(); q.order = .smart; q.appBadges = .off
    #expect(try JSONDecoder().decode(SourceSettings.self, from: JSONEncoder().encode(q)) == q)
    #expect(StreamOrderMode.addon.label == "Wie Addon" && StreamOrderMode.smart.label == "Smart (App)")
    #expect(StreamListBadgeMode.off.label == "Aus" && StreamListBadgeMode.compact.label == "Kompakt")
}

@Test func rowTextKeepsFormatterLinesAndCapsAtFour() {
    let s = StreamItem(name: "[TB⚡] AIO\r\n4K DV", description: "🎬 Film (2018)\n📀 WEB-DL ⚙ HEVC\n💾 21.01 GB\n🔊 TrueHD 7.1\n🌐 DE EN\n", url: "https://u")
    let t = StreamRowText(s)
    #expect(t.name == "[TB⚡] AIO\n4K DV")
    #expect(t.body == "🎬 Film (2018)\n📀 WEB-DL ⚙ HEVC\n💾 21.01 GB\n🔊 TrueHD 7.1 …")
    // Ältere Addons: `title`; ohne Text der Dateiname.
    #expect(StreamRowText(StreamItem(name: "n", title: "Alt\nZeile", url: "https://u")).body == "Alt\nZeile")
    #expect(StreamRowText(StreamItem(url: "https://u", behaviorHints: hints(file: "a.mkv"))).body == "a.mkv")
    #expect(StreamRowText.capped("a\nb", lines: 4) == "a\nb")
}

@Test func compactBadgesOnlyWhenAddonTextLacksThem() {
    let settings = BadgeSettings()
    // Addon-Text ohne Cache-Marker und ohne Größe → „sofort“ + Größe.
    let bare = StreamItem(name: "AIO", description: "🎬 Film", url: "https://u", behaviorHints: hints(size: 5_930_000_000, cached: true))
    #expect(StreamListBadges.badges(bare, mode: .compact, settings: settings).map(\.text) == ["⚡ sofort", "5,93 GB"])
    // Text zeigt beides schon → keine App-Plakette.
    let full = StreamItem(name: "[TB⚡] AIO", description: "💾 5.93 GB", url: "https://u", behaviorHints: hints(size: 5_930_000_000, cached: true))
    #expect(StreamListBadges.badges(full, mode: .compact, settings: settings).isEmpty)
    // Aus → nie; abgeschaltete Typen in den Plaketten-Einstellungen bleiben aus.
    #expect(StreamListBadges.badges(bare, mode: .off, settings: settings).isEmpty)
    var noSize = settings; noSize.size = false
    #expect(StreamListBadges.badges(bare, mode: .compact, settings: noSize).map(\.text) == ["⚡ sofort"])
    // Nur „sofort“, nie „lädt erst“.
    let pending = StreamItem(name: "AIO", description: "x", url: "https://u", behaviorHints: hints(cached: false))
    #expect(StreamListBadges.badges(pending, mode: .compact, settings: settings).isEmpty)
}

@Test func addonTextDetection() {
    #expect(StreamListBadges.showsCached("[RD+] Torrentio"))
    #expect(StreamListBadges.showsCached("Instant ✓"))
    #expect(!StreamListBadges.showsCached("Uncached"))
    #expect(StreamListBadges.showsSize("💾 1,4 GiB"))
    #expect(StreamListBadges.showsSize("850MB"))
    #expect(!StreamListBadges.showsSize("1080p HEVC 7.1"))
}

@Test func refreshAdditionsSkipDuplicatesOfShownRows() {
    // D-b-Übernahme: dieselbe Datei kommt mit neuer Abspiel-Adresse zurück → keine zweite Zeile.
    let shown = StreamItem(name: "AIO", url: "https://aio/p/1", behaviorHints: hints(file: "f.mkv", size: 10))
    let again = StreamItem(name: "AIO", url: "https://aio/p/9", behaviorHints: hints(file: "f.mkv", size: 10))
    let new = StreamItem(name: "AIO", url: "https://aio/p/2", behaviorHints: hints(file: "g.mkv", size: 11))
    let added = StreamListMerge.additions(to: [("AIO", shown)], from: [("AIO", again), ("AIO", new)])
    #expect(added.map(\.stream.id) == [new.id])
}
