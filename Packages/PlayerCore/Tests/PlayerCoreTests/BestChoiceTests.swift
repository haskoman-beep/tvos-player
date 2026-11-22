import Foundation
import Testing
@testable import PlayerCore

private func st(_ name: String, _ desc: String = "", hints: StreamBehaviorHints? = nil, url: String? = nil) -> StreamItem {
    StreamItem(name: name, description: desc, url: url ?? "https://x/\(name.hashValue)/\(desc.hashValue)", behaviorHints: hints)
}

private let de = SourceRankContext(primaryLanguage: "de", av1Hardware: false)
private func entries(_ s: [StreamItem], addon: String = "A") -> [(addon: String, stream: StreamItem)] { s.map { (addon, $0) } }

// MARK: Wahl

@Test func bestChoicePrefersDolbyVisionInSameTier() {
    let hdr = st("[TB⚡] 2160p", "German HDR10 DDP5.1")
    let dv = st("[TB⚡] 2160p", "German DV HDR10 DDP5.1")
    let p = BestChoice.pick(entries([hdr, dv]), context: de, last: nil, isFailed: { _ in false })
    #expect(p?.stream == dv)
    #expect(p?.reason == .best)
}

@Test func bestChoicePrefersGermanAudioOverBetterTechnik() {
    let en = st("[TB⚡] 2160p", "English DV Atmos 7.1")
    let ger = st("[TB⚡] 1080p", "German DD5.1")
    let p = BestChoice.pick(entries([en, ger]), context: de, last: nil, isFailed: { _ in false })
    #expect(p?.stream == ger)
}

@Test func bestChoicePrefersCachedOverUncached() {
    let uncached = st("[TB⏳] 2160p", "German DV")
    let cached = st("[TB⚡] 1080p", "German")
    let p = BestChoice.pick(entries([uncached, cached]), context: de, last: nil, isFailed: { _ in false })
    #expect(p?.stream == cached)
    // Sicher gecacht schlägt unbekannt innerhalb derselben Stufe, auch bei kleinerer Auflösung.
    let unknown = st("2160p", "German DV")
    #expect(BestChoice.pick(entries([unknown, cached]), context: de, last: nil, isFailed: { _ in false })?.stream == cached)
}

@Test func bestChoiceSkipsRecentlyFailed() {
    let a = st("[TB⚡] 2160p", "German DV")
    let b = st("[TB⚡] 2160p", "German HDR")
    var book = FailedLinkBook()
    let now = Date()
    book.noteFailure(a, title: "tt1", now: now)
    let p = BestChoice.pick(entries([a, b]), context: de, last: nil,
                            isFailed: { book.isRecentlyFailed($0, title: "tt1", now: now) })
    #expect(p?.stream == b)
    // Nach 8 h wieder wählbar.
    let later = now.addingTimeInterval(FailedLinkBook.lifetime + 1)
    let q = BestChoice.pick(entries([a, b]), context: de, last: nil,
                            isFailed: { book.isRecentlyFailed($0, title: "tt1", now: later) })
    #expect(q?.stream == a)
}

@Test func bestChoiceNilWithoutPlayableSource() {
    let noURL = StreamItem(name: "x", description: "German", infoHash: "abc")
    let magnet = st("y", "German", url: "magnet:?xt=urn:btih:abc")
    #expect(BestChoice.pick(entries([noURL, magnet]), context: de, last: nil, isFailed: { _ in false }) == nil)
    #expect(BestChoice.pick([], context: de, last: nil, isFailed: { _ in false }) == nil)
    let a = st("[TB⚡] 1080p", "German")
    #expect(BestChoice.pick(entries([a]), context: de, last: nil, isFailed: { _ in true }) == nil)
}

@Test func bestChoiceUsesLastSourceFirst() {
    let best = st("[TB⚡] 2160p", "German DV", hints: StreamBehaviorHints(filename: "Film.2160p.DV.mkv"))
    let old = st("[TB⚡] 1080p", "German", hints: StreamBehaviorHints(filename: "Film.1080p.mkv"))
    let last = LastSource(stream: old, addon: "A", contentID: "tt1")
    let p = BestChoice.pick(entries([best, old]), context: de, last: last, isFailed: { _ in false })
    #expect(p?.stream == old)
    #expect(p?.reason == .lastSource)
    // Letzte Quelle fehlgeschlagen: beste Wahl statt ihrer.
    let q = BestChoice.pick(entries([best, old]), context: de, last: last, isFailed: { $0 == old })
    #expect(q?.stream == best)
    #expect(q?.reason == .best)
}

@Test func bestChoiceKeepsAddonOrderOnTie() {
    let a = st("[TB⚡] 2160p", "German DV 5.1 A")
    let b = st("[TB⚡] 2160p", "German DV 5.1 B")
    #expect(BestChoice.pick(entries([a, b]), context: de, last: nil, isFailed: { _ in false })?.stream == a)
}

@Test func bestChoicePrefersHigherResolutionAndSurround() {
    let hd = st("[TB⚡] 1080p", "German DV 5.1")
    let uhd = st("[TB⚡] 2160p", "German HDR 2.0")
    #expect(BestChoice.pick(entries([hd, uhd]), context: de, last: nil, isFailed: { _ in false })?.stream == uhd)
    let stereo = st("[TB⚡] 2160p", "German DV 2.0")
    let surround = st("[TB⚡] 2160p", "German DV 7.1")
    #expect(BestChoice.pick(entries([stereo, surround]), context: de, last: nil, isFailed: { _ in false })?.stream == surround)
}

// MARK: Text

@Test func bestChoiceDetailText() {
    let s = st("[TB⚡] 2160p", "German DV HDR10 DDP5.1", hints: StreamBehaviorHints(videoSize: 12_300_000_000, service: "torbox", cached: true))
    #expect(BestChoice.detail(s, primaryLanguage: "de") == "4K DV · Deutsch 5.1 · 12,3 GB · TorBox ⚡")
    let plain = st("1080p", "Multi HDR 7.1 800 MB")
    #expect(BestChoice.detail(plain, primaryLanguage: "de") == "1080p HDR · Multi 7.1 · 800 MB")
    let bare = StreamItem(name: "Quelle X\nZeile 2", url: "https://x/1")
    #expect(BestChoice.detail(bare, primaryLanguage: "de") == "Quelle X")
    let cachedNoService = st("1080p", "⚡")
    #expect(BestChoice.detail(cachedNoService, primaryLanguage: nil) == "1080p · ⚡ Sofort bereit")
}

@Test func bestChoiceTitle() {
    #expect(BestChoice.title(.best) == "Sofort abspielen")
    #expect(BestChoice.title(.lastSource) == "Weiter mit letzter Quelle")
    #expect(BestChoice.title(.best, resumeText: "1:02:03") == "Sofort abspielen ab 1:02:03")
    #expect(BestChoice.noSourceText == "Keine Quelle gefunden – Quellen ansehen")
}

// MARK: Schnellsuchlauf

@Test func fastSeekSpeedSteps() {
    #expect(FastSeek.speed(heldFor: 0) == 2)
    #expect(FastSeek.speed(heldFor: 0.99) == 2)
    #expect(FastSeek.speed(heldFor: 1) == 4)
    #expect(FastSeek.speed(heldFor: 2.5) == 8)
    #expect(FastSeek.speed(heldFor: 3) == 16)
    #expect(FastSeek.speed(heldFor: 5) == 32)
    #expect(FastSeek.speed(heldFor: 60) == 64)
    #expect(FastSeek.speed(heldFor: -1) == 2)
    #expect(FastSeek.speed(heldFor: .nan) == 2)
    #expect(FastSeek.label(speed: 8) == "▶▶ 8×")
    #expect(FastSeek.label(speed: -4) == "◀◀ 4×")
}

@Test func fastSeekUpperLimit() {
    // Ohne Abspann: Dateiende − 5 s.
    #expect(FastSeek.upperLimit(duration: 6000, creditsStart: nil, origin: 100) == 5995)
    // Abspann bekannt: 10 s davor.
    #expect(FastSeek.upperLimit(duration: 6000, creditsStart: 5600, origin: 100) == 5590)
    // Schon im Abspann (bzw. hinter der Haltestelle): nur das Dateiende.
    #expect(FastSeek.upperLimit(duration: 6000, creditsStart: 5600, origin: 5595) == 5995)
    // Unbekannte Dauer: keine Obergrenze außer dem Abspann.
    #expect(FastSeek.upperLimit(duration: 0, creditsStart: nil, origin: 0) == .greatestFiniteMagnitude)
}

@Test func fastSeekOriginDropsOwnArrowJump() {
    // Derselbe Druck hat schon +10 s gesammelt: fällt weg.
    #expect(FastSeek.origin(pending: 110, current: 100, lastArrowForward: true, lastArrowAge: 0.4, forward: true) == 100)
    // Älterer Druck bleibt erhalten.
    #expect(FastSeek.origin(pending: 120, current: 100, lastArrowForward: true, lastArrowAge: 2, forward: true) == 120)
    // Andere Richtung: nichts abziehen.
    #expect(FastSeek.origin(pending: 90, current: 100, lastArrowForward: false, lastArrowAge: 0.4, forward: true) == 90)
    // Zurück: −10 s desselben Drucks fällt weg.
    #expect(FastSeek.origin(pending: 90, current: 100, lastArrowForward: false, lastArrowAge: 0.3, forward: false) == 100)
    // Nichts gesammelt: laufende Stelle.
    #expect(FastSeek.origin(pending: nil, current: 100, lastArrowForward: true, lastArrowAge: 0.1, forward: true) == 100)
}

@Test func plannerHoldMovesTargetWithRisingSpeed() {
    var p = ScrubPlanner()
    p.holdBegin(forward: true, position: 100, duration: 6000, upper: 5590, now: 0)
    #expect(p.isActive && p.isHolding)
    p.holdTick(now: 1)          // 1 s mit 2×
    #expect(p.target == 102)
    p.holdTick(now: 2)          // 1 s mit 4×
    #expect(p.target == 106)
    #expect(p.holdSpeed(now: 2.5) == 8)
    p.holdEnd(now: 2.5)         // 0,5 s mit 8×
    #expect(p.target == 110)
    #expect(!p.isHolding && p.isActive)
    #expect(p.holdSpeed(now: 3) == nil)
    // Losgelassen: weitere Takte bewegen nichts; Select springt.
    let moved = p.holdTick(now: 4)
    #expect(!moved)
    let t = p.confirm()
    #expect(t == 110)
}

@Test func plannerHoldStopsAtCreditsGuardAndStart() {
    var p = ScrubPlanner()
    p.holdBegin(forward: true, position: 5500, duration: 6000, upper: 5590, now: 0)
    for i in 1...200 { p.holdTick(now: Double(i) * 0.05) }   // 10 s Halten: weit über die Grenze
    #expect(p.target == 5590)
    #expect(p.holdAtLimit)
    p.holdEnd(now: 10)
    // Rücklauf bis 0, nicht darunter.
    p.holdBegin(forward: false, position: 0, duration: 6000, upper: 5590, now: 20)
    #expect(!p.holdAtLimit)
    for i in 1...4000 { p.holdTick(now: 20 + Double(i) * 0.05) }   // 200 s zurück
    #expect(p.target == 0)
    #expect(p.holdAtLimit)
}

@Test func plannerHoldSuppressesTrailingNudgeAndCancelClears() {
    var p = ScrubPlanner()
    p.holdBegin(forward: true, position: 100, duration: 6000, upper: 5995, now: 0)
    let n1 = p.nudge(10, now: 0.5)          // während des Haltens kein ±10
    #expect(!n1)
    p.holdEnd(now: 1)
    let n2 = p.nudge(10, now: 1.1)          // Nachzügler derselben Taste
    #expect(!n2)
    let n3 = p.nudge(10, now: 2)             // späterer Klick verschiebt
    #expect(n3)
    #expect(p.target == 112)
    let c = p.cancel()
    #expect(c)
    #expect(!p.isActive && !p.isHolding)
}

@Test func plannerHoldIgnoresPanAndWheel() {
    var p = ScrubPlanner()
    p.holdBegin(forward: true, position: 100, duration: 6000, upper: 5590, now: 0)
    let panned = p.pan(deltaX: 400, velocityX: 2000, position: 100, duration: 6000, now: 0.1)
    #expect(!panned)
    let touched = p.touch(x: 0.95, y: 0, position: 100, duration: 6000, now: 0.2)
    #expect(!touched)
    #expect(p.target == 100)
}

// MARK: Welle F-i: Prism-Formatter („⚡Ready“ / „❌ Not Ready“)

@Test func bestChoiceSkipsNotReadyFromPrismFormatter() {
    let notReady = st("🔥4K UHD", "🎬 Film German DV\n📦 12.1 GB 🌱 1\n❌ Not Ready (TB) 🔍AIOStreams")
    let ready = st("🚀 FHD", "🎬 Film German\n📦 4.9 GB\n⚡Ready (TB) 🔍AIOStreams")
    let p = BestChoice.pick(entries([notReady, ready]), context: de, last: nil, isFailed: { _ in false })
    #expect(p?.stream == ready)
    // Kein gecachter Kandidat: unbekannt vor sicher ungecacht, auch bei schlechterer Technik.
    let unknown = st("🚀 FHD", "🎬 Film German\n📦 4.9 GB")
    let q = BestChoice.pick(entries([notReady, unknown]), context: de, last: nil, isFailed: { _ in false })
    #expect(q?.stream == unknown)
}

/// Gerätefoto Build 41: Karte zeigte „Sofort abspielen · Deutsch · 1,8 GB“ für eine „❌ Not Ready (TB) ✤ Meteor“-Quelle.
/// Deutsch schlägt sonst die Technik, ungecacht muss aber hinter gecachte englische Quellen.
@Test func bestChoicePutsGermanNotReadyBehindCachedEnglish() {
    let notReady = st("❓ Unknown", "🎬 The Immigrant (2013)\n🗣️ 🇩🇪\n💾 1.8 GB 🌱 2\n❌ Not Ready (TB) ✤ Meteor")
    let ready = st("🎫 1080p", "🎬 The Immigrant (2013)\n💿 BluRay ⚙️ AVC\n🗣️ 🇬🇧\n💾 10.5 GB\n⚡Ready (TB) ✤ Meteor")
    let p = BestChoice.pick(entries([notReady, ready]), context: de, last: nil, isFailed: { _ in false })
    #expect(p?.stream == ready)
    #expect(BestChoice.detail(ready, primaryLanguage: "de").contains("Sofort bereit"))
}
