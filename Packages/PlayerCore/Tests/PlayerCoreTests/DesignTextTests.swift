import Testing
@testable import PlayerCore

@Test func designMetaLineSkipsEmptyParts() {
    #expect(DesignText.metaLine(["2018", "97 min", nil, " ", "FSK 0", "Animation"]) == "2018 · 97 min · FSK 0 · Animation")
    #expect(DesignText.metaLine([" 2018 ", "\n"]) == "2018")
    #expect(DesignText.metaLine([]) == "")
    #expect(DesignText.metaLine([nil, ""]) == "")
}

@Test func designDecimalUsesGermanComma() {
    #expect(DesignText.decimal(7.1) == "7,1")
    #expect(DesignText.decimal(7.06) == "7,1")
    #expect(DesignText.decimal(8) == "8,0")
    #expect(DesignText.decimal(63, fractionDigits: 0) == "63")
    #expect(DesignText.decimal(8.4, fractionDigits: 2) == "8,40")
    #expect(DesignText.decimal(-0.01) == "0,0")
    #expect(DesignText.decimal(-1.5) == "-1,5")
    #expect(DesignText.decimal(.nan) == "")
    #expect(DesignText.decimal(.infinity) == "")
    #expect(DesignText.decimal(1.5, fractionDigits: -3) == "2")
}

@Test func designRatingText() {
    #expect(DesignText.rating(source: "IMDb", value: 7.1) == "IMDb 7,1")
    #expect(DesignText.rating(source: "RT", value: 63, fractionDigits: 0, suffix: " %") == "RT 63 %")
    #expect(DesignText.rating(source: nil, value: 7.1) == "7,1")
    #expect(DesignText.rating(source: "IMDb", value: .nan) == "")
}

@Test func designAccessibilityLabelJoinsInReadingOrder() {
    #expect(DesignText.accessibilityLabel(["Tonsprache", "Deutsch → Englisch", nil, "Welche Tonspur zuerst gewählt wird."])
            == "Tonsprache, Deutsch → Englisch, Welche Tonspur zuerst gewählt wird.")
    #expect(DesignText.accessibilityLabel(["", " "]) == "")
}
