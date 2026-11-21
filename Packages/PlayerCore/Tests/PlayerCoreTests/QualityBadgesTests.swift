import Foundation
import Testing
@testable import PlayerCore

@Test func badgeSettingsDefaultsAndMigration() throws {
    // Altes Aussehen ohne Plaketten-Feld: alles an außer Videocodec, Logo-Stil, Poster an.
    let old = try JSONDecoder().decode(Appearance.self, from: Data(#"{"accent":"green"}"#.utf8))
    #expect(old.badges == BadgeSettings())
    let d = BadgeSettings()
    #expect(d.style == .logo && !d.videoCodec)
    #expect(BadgeType.allCases.filter { !d.shows($0) } == [.videoCodec])
    // Teilweise vorhandene Plaketten-Daten: Rest Standard.
    let partial = try JSONDecoder().decode(BadgeSettings.self, from: Data(#"{"size":false,"style":"text"}"#.utf8))
    #expect(!partial.size && partial.style == .text && partial.languages)
    // Rundreise über Appearance.
    var a = Appearance()
    a.badges.set(.languages, false)
    a.badges.style = .text
    let back = try JSONDecoder().decode(Appearance.self, from: JSONEncoder().encode(a))
    #expect(back == a)
    #expect(!back.badges.shows(.languages))
}

@Test func streamBadgesFollowSettingsAndStyle() {
    let s = StreamItem(name: "[TB⚡] 2160p", description: "Film.2160p.REMUX.DV.HDR10.TrueHD.Atmos.DTS-HD.MA.7.1.HEVC 🇩🇪 💾 45.2 GB", url: "https://x")
    let t = StreamTraits.parse(s)
    let all = QualityBadges.forStream(t, settings: BadgeSettings(videoCodec: true))
    #expect(all.map(\.text) == ["4K", "DV", "HDR10", "REMUX", "HEVC", "Atmos", "TrueHD", "DTS-HD MA", "7.1", "DE", "45,20 GB", "⚡ sofort"])
    #expect(all.compactMap(\.logo) == [.uhd4K, .dolbyVision, .hdr10, .remux, .dolbyAtmos, .dtsHDMA])
    #expect(all.last?.tone == .ready)
    #expect(all.dropLast().allSatisfy { $0.tone == .neutral })
    // Standard: kein Videocodec.
    #expect(!QualityBadges.forStream(t, settings: BadgeSettings()).contains { $0.type == .videoCodec })
    // Text-Stil: keine Logos, gleiche Texte.
    let text = QualityBadges.forStream(t, settings: BadgeSettings(videoCodec: true, style: .text))
    #expect(text.map(\.text) == all.map(\.text))
    #expect(text.allSatisfy { $0.logo == nil })
    // Einzelne Typen aus.
    var off = BadgeSettings()
    for ty in BadgeType.allCases { off.set(ty, false) }
    #expect(QualityBadges.forStream(t, settings: off).isEmpty)
    off.set(.cacheStatus, true)
    let pending = StreamTraits.parse(StreamItem(name: "[TB⏳] 1080p"))
    #expect(QualityBadges.forStream(pending, settings: off) == [QualityBadge(type: .cacheStatus, text: "lädt erst", tone: .pending)])
}

@Test func bestQualityOverCachedStreams() {
    let s = [StreamItem(name: "⚡ 1080p", title: "Film.1080p.HDR10.DDP.5.1", url: "https://a"),
             StreamItem(name: "⚡ 2160p", title: "Film.2160p.DV.TrueHD.Atmos.7.1", url: "https://b"),
             StreamItem(name: "🎫 2160p", title: "Film.2160p.HDR10+.DTS-X", url: "https://c")]
    let b = BestQuality.from(s)
    #expect(b == BestQuality(resolution: "2160p", dolbyVision: true, hdr: "HDR10", atmos: true, dtsX: false, channels: "7.1"))
    // REMUX und DTS-HD MA aus gecachten Quellen.
    let r = BestQuality.from([StreamItem(name: "⚡ 2160p", title: "Film.2160p.REMUX.DTS-HD.MA.5.1", url: "https://d")])
    #expect(r?.remux == true && r?.dtsHDMA == true && r?.dtsX == false)
    // Nur ungecachte Quellen: die zählen dann.
    let u = BestQuality.from([s[2]])
    #expect(u?.hdr == "HDR10+" && u?.dtsX == true && u?.resolution == "2160p")
    #expect(BestQuality.from([StreamItem]()) == nil)
}

@Test func posterBadges() {
    let b = BestQuality(resolution: "2160p", dolbyVision: true, hdr: "HDR10+", atmos: true, dtsX: true, dtsHDMA: true, remux: true, channels: "7.1")
    // Poster: höchstens 3, DV vor HDR.
    let p = QualityBadges.poster(b, settings: BadgeSettings())
    #expect(p.map(\.logo) == [.uhd4K, .dolbyVision, .dolbyAtmos])
    #expect(p.map(\.text) == ["4K", "DV", "Atmos"])
    // Ohne DV: HDR-Art; ohne Atmos: nur 2.
    let p2 = QualityBadges.poster(BestQuality(resolution: "1080p", hdr: "HDR"), settings: BadgeSettings())
    #expect(p2.map(\.text) == ["HD", "HDR"] && p2.allSatisfy { $0.logo == nil })
    // Schalter: Typ aus, Text-Stil.
    #expect(QualityBadges.poster(b, settings: BadgeSettings(hdr: false)).map(\.text) == ["4K", "Atmos"])
    #expect(QualityBadges.poster(b, settings: BadgeSettings(style: .text)).allSatisfy { $0.logo == nil })
}

@Test func sizeFormatting() {
    #expect(QualityBadges.formatSize(30_710_000_000) == "30,71 GB")
    #expect(QualityBadges.formatSize(854_000_000) == "854 MB")
    #expect(QualityBadges.formatSize(1_200_000_000_000) == "1,20 TB")
}
