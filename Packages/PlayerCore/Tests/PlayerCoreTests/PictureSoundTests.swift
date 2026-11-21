import Foundation
import Testing
@testable import PlayerCore

// Welle D-a: Untertitel-Versatz, Zeichensatz, Bildschirmschoner, Spur-Gedächtnis, Datei-Fortschritt.

// MARK: Versatz

@Test func subtitleOffsetStepsRoundAndClamp() {
    var v = 0.0
    v = SubtitleOffset.adjusted(v, by: 0.1)
    v = SubtitleOffset.adjusted(v, by: 0.1)
    v = SubtitleOffset.adjusted(v, by: 0.1)
    #expect(v == 0.3)   // kein 0.30000000000000004
    v = SubtitleOffset.adjusted(v, by: -0.5)
    #expect(v == -0.2)
    #expect(SubtitleOffset.adjusted(29.8, by: 0.5) == 30)
    #expect(SubtitleOffset.adjusted(-29.9, by: -0.5) == -30)
    #expect(SubtitleOffset.normalized(.nan) == 0)
    #expect(SubtitleOffset.adjusted(0.1, by: -0.1) == 0)
    #expect(SubtitleOffset.normalized(-0.04).sign == .plus)   // kein -0
}

@Test func subtitleOffsetLabels() {
    #expect(SubtitleOffset.label(0.3) == "+0,3 s")
    #expect(SubtitleOffset.label(-1.5) == "\u{2212}1,5 s")
    #expect(SubtitleOffset.label(0) == "0,0 s")
    #expect(SubtitleOffset.stepLabel(-0.5) == "\u{2212}0,5")
    #expect(SubtitleOffset.stepLabel(0.1) == "+0,1")
    #expect(SubtitleOffset.hint(0.5) == "Untertitel erscheinen 0,5 s später")
    #expect(SubtitleOffset.hint(-2) == "Untertitel erscheinen 2,0 s früher")
    #expect(SubtitleOffset.hint(0) == "Kein Versatz")
}

// MARK: Zeichensatz

private let srtUTF8 = "1\n00:00:01,000 --> 00:00:02,000\nSchöne Grüße aus Köln – „Straße“\n"

@Test func charsetPlainUTF8Untouched() {
    let d = SubtitleCharset.decode(Data(srtUTF8.utf8))
    #expect(d.source == .utf8)
    #expect(d.text == srtUTF8)
    #expect(d.repaired == 0)
}

@Test func charsetStripsUTF8BOM() {
    let d = SubtitleCharset.decode(Data([0xEF, 0xBB, 0xBF] + Array(srtUTF8.utf8)))
    #expect(d.source == .utf8BOM)
    #expect(d.text == srtUTF8)
    #expect(d.utf8Data.first == UInt8(ascii: "1"))
}

@Test func charsetCP1252Umlauts() {
    // "Grüße, Bär – „Öl“ für 5 €" in CP1252.
    let bytes: [UInt8] = [0x47, 0x72, 0xFC, 0xDF, 0x65, 0x2C, 0x20, 0x42, 0xE4, 0x72, 0x20, 0x96, 0x20,
                          0x84, 0xD6, 0x6C, 0x93, 0x20, 0x66, 0xFC, 0x72, 0x20, 0x35, 0x20, 0x80]
    let d = SubtitleCharset.decode(Data(bytes))
    #expect(d.source == .cp1252)
    #expect(d.text == "Grüße, Bär – „Öl“ für 5 €")
    #expect(d.repaired == 0)
}

@Test func charsetISO88591Umlauts() {
    // ISO-8859-1: ä ö ü Ä Ö Ü ß, alles im Bereich 0xA0–0xFF (gleich in CP1252).
    let bytes: [UInt8] = [0xE4, 0x20, 0xF6, 0x20, 0xFC, 0x20, 0xC4, 0x20, 0xD6, 0x20, 0xDC, 0x20, 0xDF]
    let d = SubtitleCharset.decode(Data(bytes))
    #expect(d.text == "ä ö ü Ä Ö Ü ß")
}

@Test func charsetUTF16WithBOM() {
    let text = "Übermäßig süß\n"
    var le: [UInt8] = [0xFF, 0xFE]
    for u in text.utf16 { le.append(UInt8(u & 0xFF)); le.append(UInt8(u >> 8)) }
    let dl = SubtitleCharset.decode(Data(le))
    #expect(dl.source == .utf16LE)
    #expect(dl.text == text)
    var be: [UInt8] = [0xFE, 0xFF]
    for u in text.utf16 { be.append(UInt8(u >> 8)); be.append(UInt8(u & 0xFF)) }
    let db = SubtitleCharset.decode(Data(be))
    #expect(db.source == .utf16BE)
    #expect(db.text == text)
}

@Test func charsetUTF16WithoutBOMByZeroBytes() {
    let text = "1\n00:00:01,000 --> 00:00:02,000\nHallo Welt\n"
    var le: [UInt8] = []
    for u in text.utf16 { le.append(UInt8(u & 0xFF)); le.append(UInt8(u >> 8)) }
    let d = SubtitleCharset.decode(Data(le))
    #expect(d.source == .utf16LE)
    #expect(d.text == text)
}

@Test func charsetRepairsDoubleEncodedGerman() {
    // UTF-8 von „Grüße aus Köln – „Straße““ einmal als CP1252 gelesen und wieder als UTF-8 gespeichert.
    let broken = "GrÃ¼ÃŸe aus KÃ¶ln â€“ â€žStraÃŸeâ€œ, Ã„rger, Ãœbel, Ã–l"
    let d = SubtitleCharset.decode(Data(broken.utf8))
    #expect(d.source == .utf8)
    #expect(d.text == "Grüße aus Köln – „Straße“, Ärger, Übel, Öl")
    #expect(d.repaired == 10)
}

@Test func charsetRepairsMojibakeInsideCP1252File() {
    // UTF-8-Bytes in einer Datei, die sonst nicht gültiges UTF-8 ist (gemischt): CP1252 lesen, dann reparieren.
    // "Sch" + UTF-8 "ö" (C3 B6) + "n " + CP1252 "ü" (FC).
    let bytes: [UInt8] = [0x53, 0x63, 0x68, 0xC3, 0xB6, 0x6E, 0x20, 0xFC]
    let d = SubtitleCharset.decode(Data(bytes))
    #expect(d.source == .cp1252)
    #expect(d.text == "Schön ü")
    #expect(d.repaired == 1)
}

@Test func charsetKeepsRealCapitalUmlautsAndSymbols() {
    let text = "Ärger mit Öl? Ä« nein. Ü-Wagen, Größe 2°C, Café © 2024"
    let d = SubtitleCharset.decode(Data(text.utf8))
    #expect(d.text == text)
    #expect(d.repaired == 0)
}

/// Echter deutscher Text mit „…“, „“, »« direkt nach ß/Ä/Ü (Review I1), in UTF-8 und in CP1252.
@Test func charsetKeepsGermanTypography() {
    let lines = ["Ich weiß…", "Das macht „Spaß“", "»Spaß«", "„Ä…“", "Ü… nein", "Grüße – „Straße“"]
    let cp1252: [String: [UInt8]] = [
        "Ich weiß…": [0x49, 0x63, 0x68, 0x20, 0x77, 0x65, 0x69, 0xDF, 0x85],
        "Das macht „Spaß“": [0x44, 0x61, 0x73, 0x20, 0x6D, 0x61, 0x63, 0x68, 0x74, 0x20, 0x84, 0x53, 0x70, 0x61, 0xDF, 0x93],
        "»Spaß«": [0xBB, 0x53, 0x70, 0x61, 0xDF, 0xAB],
        "„Ä…“": [0x84, 0xC4, 0x85, 0x93],
    ]
    for l in lines {
        let d = SubtitleCharset.decode(Data(l.utf8))
        #expect(d.text == l)
        #expect(d.repaired == 0)
    }
    let all = lines.joined(separator: "\n")
    #expect(SubtitleCharset.decode(Data(all.utf8)).text == all)
    // CP1252-Datei: einzelne Zeilen wie „weiß…“ (DF 85) sind zufällig gültiges UTF-8; eine echte Datei enthält
    // weitere Umlaute („für“ = 66 FC 72), die kein UTF-8 sind. Deshalb als ganze Datei prüfen.
    var file: [UInt8] = [0x66, 0xFC, 0x72, 0x0A]
    var expected = "für\n"
    for (l, bytes) in cp1252.sorted(by: { $0.key < $1.key }) { file += bytes + [0x0A]; expected += l + "\n" }
    let d = SubtitleCharset.decode(Data(file))
    #expect(d.source == .cp1252)
    #expect(d.text == expected)
    #expect(d.repaired == 0)
}

@Test func charsetRepairNeedsTypicalHits() {
    // Ein einzelnes „Ã¼“ in sonst gültigem UTF-8 reicht nicht (könnte echt sein); zwei typische Treffer schon.
    #expect(SubtitleCharset.decode(Data("Ã¼".utf8)).repaired == 0)
    #expect(SubtitleCharset.decode(Data("GrÃ¼ÃŸe".utf8)).text == "Grüße")
    // Echtes Mojibake mit „…“ und „ß“ daneben: repariert wird nur das Mojibake.
    let d = SubtitleCharset.decode(Data("Ich weiÃŸâ€¦ KÃ¶ln".utf8))
    #expect(d.text == "Ich weiß… Köln")
    #expect(d.repaired == 3)
}

@Test func charsetRepairsLatin1Mojibake() {
    // UTF-8 einmal als ISO-8859-1 gelesen: ß = C3 9F → „Ã\u{9F}“, Ä = C3 84 → „Ã\u{84}“ (C1-Steuerzeichen, Review M4).
    let d = SubtitleCharset.decode(Data("Stra\u{C3}\u{9F}e, \u{C3}\u{84}rger".utf8))
    #expect(d.text == "Straße, Ärger")
    #expect(d.repaired == 2)
}

// MARK: Bildschirmschoner

private func step(_ p: inout IdleTimerPolicy, _ busy: Bool, _ now: Date) -> Bool { p.update(busy: busy, now: now) }

@Test func idleTimerBusyAndPauseLimit() {
    var p = IdleTimerPolicy(pauseLimitMinutes: 30)
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    #expect(step(&p, true, t0))
    #expect(step(&p, false, t0))   // Pause beginnt: noch gesperrt
    #expect(step(&p, false, t0 + 29 * 60))
    #expect(!step(&p, false, t0 + 30 * 60))   // nach 30 min frei
    #expect(step(&p, true, t0 + 31 * 60))   // Puffern/Spielen sperrt wieder
    #expect(step(&p, false, t0 + 32 * 60))  // neue Pause zählt neu
    p.reset()
    #expect(p.pausedSince == nil)
}

@Test func idleTimerZeroMeansNoLockWhilePaused() {
    var p = IdleTimerPolicy(pauseLimitMinutes: 0)
    let t0 = Date(timeIntervalSince1970: 0)
    #expect(step(&p, true, t0))
    #expect(!step(&p, false, t0))
    #expect(IdleTimerPolicy.choiceLabel(0) == "Nicht sperren")
    #expect(IdleTimerPolicy.choiceLabel(30) == "30 Minuten")
    #expect(IdleTimerPolicy.pauseChoices.contains(IdleTimerPolicy.defaultPauseMinutes))
}

// MARK: Spur-Gedächtnis

private func tr(_ id: Int, _ lang: String?, forced: Bool = false, sdh: Bool = false, comm: Bool = false,
                ext: Bool = false, image: Bool = false, ch: Int? = nil) -> AudioTrackInfo {
    AudioTrackInfo(id: id, language: lang, channels: ch, isForced: forced, isHearingImpaired: sdh, isCommentary: comm,
                   isExternal: ext, isImage: image)
}

@Test func trackMemoryKeys() {
    #expect(TrackMemoryBook.key(itemID: "tt0903747") == "tt0903747")
    #expect(TrackMemoryBook.key(itemID: "tt0903747:1:2") == "tt0903747")
    #expect(TrackMemoryBook.key(itemID: "tmdb:1396:1:2") == "tmdb:1396")
    #expect(TrackMemoryBook.key(itemID: "tmdb:1396") == "tmdb:1396")
    #expect(TrackMemoryBook.key(itemID: "torbox:torrent:12:3") == "torbox:torrent:12:3")
}

@Test func trackMemoryAudioOnlyWhenTrackExists() {
    let tracks = [tr(0, "ger", ch: 2), tr(1, "eng", ch: 6), tr(2, "eng", comm: true, ch: 2)]
    #expect(TrackMemoryPlan.audio(TrackMemory(audioLanguage: "en"), tracks: tracks)?.id == 1)
    #expect(TrackMemoryPlan.audio(TrackMemory(audioLanguage: "ja"), tracks: tracks) == nil)
    #expect(TrackMemoryPlan.audio(nil, tracks: tracks) == nil)
    #expect(TrackMemoryPlan.audio(TrackMemory(subtitle: .off), tracks: tracks) == nil)
}

@Test func trackMemorySubtitleDecision() {
    let subs = [tr(10, "ger", forced: true), tr(11, "ger", image: true), tr(12, "ger"), tr(13, "eng", sdh: true),
                tr(14, "eng", ext: true), tr(15, "ger", comm: true)]
    #expect(TrackMemoryPlan.subtitle(nil, tracks: subs) == .automatic)
    #expect(TrackMemoryPlan.subtitle(TrackMemory(subtitle: .off), tracks: subs) == .off)
    #expect(TrackMemoryPlan.subtitle(TrackMemory(subtitle: .language("de", forced: false, hearingImpaired: false)), tracks: subs) == .track(12))
    #expect(TrackMemoryPlan.subtitle(TrackMemory(subtitle: .language("de", forced: true, hearingImpaired: false)), tracks: subs) == .track(10))
    #expect(TrackMemoryPlan.subtitle(TrackMemory(subtitle: .language("en", forced: false, hearingImpaired: false)), tracks: subs) == .track(14))
    #expect(TrackMemoryPlan.subtitle(TrackMemory(subtitle: .language("fr", forced: false, hearingImpaired: false)), tracks: subs) == .automatic)
    // Review I2: nur andere Art da → Ersatz (automatisch), nicht als Nutzerwahl.
    let onlyForced = [tr(20, "ger", forced: true), tr(21, "eng")]
    #expect(TrackMemoryPlan.subtitle(TrackMemory(subtitle: .language("de", forced: false, hearingImpaired: false)), tracks: onlyForced) == .fallback(20))
    #expect(TrackMemoryPlan.subtitle(TrackMemory(subtitle: .language("en", forced: false, hearingImpaired: true)), tracks: onlyForced) == .fallback(21))
    // Später geladene volle Addon-Spur ist dann ein genauer Treffer.
    let withAddon = onlyForced + [tr(22, "ger", ext: true)]
    #expect(TrackMemoryPlan.subtitle(TrackMemory(subtitle: .language("de", forced: false, hearingImpaired: false)), tracks: withAddon) == .track(22))
    #expect(TrackMemoryPlan.choice(for: nil) == .off)
    #expect(TrackMemoryPlan.choice(for: tr(1, "eng", sdh: true)) == .language("en", forced: false, hearingImpaired: true))
    #expect(TrackMemoryPlan.choice(for: tr(1, nil)) == nil)
}

@Test func trackMemoryBookUpdatesPrunesAndRoundTrips() throws {
    var b = TrackMemoryBook()
    let t0 = Date(timeIntervalSince1970: 1_000)
    for i in 0..<(TrackMemoryBook.limit + 5) {
        b.update("tt\(i)", now: t0 + Double(i)) { $0.audioLanguage = "de" }
    }
    #expect(b.entries.count == TrackMemoryBook.limit)
    #expect(b.entries["tt0"] == nil && b.entries["tt4"] == nil && b.entries["tt5"] != nil)
    b.update("tt5", now: t0 + 10_000) { $0.subtitleOffset = 0.3; $0.subtitle = .language("en", forced: false, hearingImpaired: false) }
    let m = try #require(b.memory(for: "tt5"))
    #expect(m.audioLanguage == "de" && m.subtitleOffset == 0.3)
    let data = try JSONEncoder().encode(b)
    let back = try JSONDecoder().decode(TrackMemoryBook.self, from: data)
    #expect(back == b)
    // Alte/fremde Einträge ohne Felder laden trotzdem.
    let partial = try JSONDecoder().decode(TrackMemory.self, from: Data(#"{"audioLanguage":"en"}"#.utf8))
    #expect(partial.audioLanguage == "en" && partial.subtitle == nil && partial.subtitleOffset == nil)
    #expect(b.memory(for: "unbekannt") == nil)
}

@Test func profileLoadsWithoutPlayerComfortSettings() throws {
    let p = Profile(name: "A")
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as! [String: Any]
    json["player"] = nil
    let back = try JSONDecoder().decode(Profile.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(back.player.rememberTracks)
    #expect(back.player.screensaverPauseMinutes == 30)
    let empty = try JSONDecoder().decode(PlayerComfortSettings.self, from: Data("{}".utf8))
    #expect(empty == PlayerComfortSettings())
}

// MARK: Datei-Fortschritt (TorBox)

@Test func fileProgressResumeAndFinish() {
    var b = FileProgressBook()
    let k = "torbox:torrent:1:2"
    b.record(k, position: 30, duration: 3600)
    #expect(b.resumePosition(for: k) == nil)   // unter einer Minute
    b.record(k, position: 1800, duration: 3600)
    #expect(b.resumePosition(for: k) == 1800)
    #expect(b.fraction(for: k) == 0.5)
    b.record(k, position: 3500, duration: 3600)
    #expect(b.isWatched(k))
    #expect(b.resumePosition(for: k) == nil)
    b.record(k, position: 10, duration: 0)   // ohne Laufzeit nichts
    #expect(b.isWatched(k))
}

@Test func fileProgressPrunesOldest() {
    var b = FileProgressBook()
    let t0 = Date(timeIntervalSince1970: 0)
    for i in 0..<(FileProgressBook.limit + 3) { b.record("f\(i)", position: 100, duration: 1000, now: t0 + Double(i)) }
    #expect(b.entries.count == FileProgressBook.limit)
    #expect(b.entries["f0"] == nil && b.entries["f3"] != nil)
}

@Test func trackMemoryAppliesPanelChoices() {
    var m = TrackMemory()
    m.apply(.audio(tr(1, "eng")))
    m.apply(.subtitle(tr(2, "ger", forced: true)))
    m.apply(.offset(0.30000000000000004))
    #expect(m.audioLanguage == "en")
    #expect(m.subtitle == .language("de", forced: true, hearingImpaired: false))
    #expect(m.subtitleOffset == 0.3)
    m.apply(.subtitle(nil))
    #expect(m.subtitle == .off)
    m.apply(.audio(tr(3, nil)))
    #expect(m.audioLanguage == nil)
    m.apply(.subtitle(tr(4, nil)))
    #expect(m.subtitle == nil)
}
