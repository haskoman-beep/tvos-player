import Testing
@testable import PlayerCore

@Test func ratingDisplayValueUsesGermanComma() {
    func badge(_ text: String, _ source: String = "imdb") -> RatingBadge {
        RatingBadge(source: source, label: source, text: text, score: 0)
    }
    #expect(badge("7.4").displayValue == "7,4")
    #expect(badge("3.95").displayValue == "3,95")
    #expect(badge("85%", "trakt").displayValue == "85\u{00A0}%")
    #expect(badge("76", "metacritic").displayValue == "76")
    #expect(badge("n/a").displayValue == "n/a")
    #expect(badge("7.4").accessibilityText == "IMDb 7,4")
    #expect(RatingBadge(source: "tomatoes", label: "🍅", text: "90%", score: 90).accessibilityText == "Rotten Tomatoes 90 %")
    // Gespeicherter Text bleibt unverändert (bestehende Tests und Caches).
    let x = ExternalRatings(values: ["imdb": 7.4, "trakt": 85])
    #expect(MDBList.badges(x).map(\.displayValue) == ["7,4", "85\u{00A0}%"])
    #expect(MDBList.badges(x).map(\.text) == ["7.4", "85%"])
}

@Test func qualityBadgeSpokenAndDisplayText() {
    #expect(QualityBadge(type: .hdr, text: "DV").spokenText == "Dolby Vision")
    #expect(QualityBadge(type: .audio, text: "Atmos").spokenText == "Dolby Atmos")
    #expect(QualityBadge(type: .hdr, text: "Dolby Vision", logo: .dolbyVision).spokenText == "Dolby Vision")
    #expect(QualityBadge(type: .resolution, text: "4K", logo: .uhd4K).spokenText == "4K Ultra HD")
    let ready = QualityBadge(type: .cacheStatus, text: "⚡ Sofort bereit", tone: .ready)
    #expect(ready.isStatus && ready.displayText == "Sofort bereit" && ready.spokenText == "sofort bereit")
    let pending = QualityBadge(type: .cacheStatus, text: "Nicht gecacht", tone: .pending)
    #expect(pending.isStatus && pending.displayText == "Nicht gecacht" && pending.spokenText == "nicht gecacht")
    #expect(!QualityBadge(type: .size, text: "30,71 GB").isStatus)
    #expect(QualityLogoKind.allCases.allSatisfy { !$0.wordmark.isEmpty && !$0.spokenName.isEmpty })
    #expect(QualityLogoKind.dolbyAtmos.wordmark == "ATMOS")
}

@Test func streamListSummaryText() {
    #expect(StreamListSummary.text(count: 161, milliseconds: 8400) == "161 Quellen · 8,4 s")
    #expect(StreamListSummary.text(count: 1, milliseconds: 850) == "1 Quelle · 0,8 s")
    #expect(StreamListSummary.text(count: 12, milliseconds: nil) == "12 Quellen")
}

@Test func searchProgressElapsedIsLongestAnswer() {
    let a = badgeTestAddon("a", "A")
    let b = badgeTestAddon("b", "B")
    var p = AddonSearchProgress(addons: [(index: 0, addon: a), (index: 1, addon: b)])
    #expect(p.elapsedMilliseconds == nil)
    p.finish(index: 0, addon: a, outcome: .streams([]), milliseconds: 850)
    #expect(p.elapsedMilliseconds == 850)
    p.finish(index: 1, addon: b, outcome: .timedOut, milliseconds: 15000)
    #expect(p.elapsedMilliseconds == 15000)
}

@Test func commaHelpersKeepTheirOutput() {
    // F-0 M9: alte Komma-Ersetzungen laufen über DesignText, Ausgabe unverändert.
    #expect(QualityBadges.formatSize(30_710_000_000) == "30,71 GB")
    #expect(QualityBadges.formatSize(1_200_000_000_000) == "1,20 TB")
    #expect(QualityBadges.formatSize(854_000_000) == "854 MB")
    #expect(QualityBadges.formatSize(0) == "0 MB")
    #expect(SubtitleOffset.label(-0.04) == "0,0 s")
    #expect(SubtitleOffset.label(-12.3) == "\u{2212}12,3 s")
    #expect(SubtitleOffset.stepLabel(0.5) == "+0,5")
}

private func badgeTestAddon(_ host: String, _ name: String) -> InstalledAddon {
    InstalledAddon(manifestURL: "https://\(host)/manifest.json",
                   manifest: AddonManifest(id: host, name: name, version: "1", resources: [AddonResource(name: "stream")],
                                           types: ["movie"], idPrefixes: ["tt"]))
}
