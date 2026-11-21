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

@Test func designDecimalRoundingIsPinned() {
    // String(format:) rundet exakte Hälften auf die gerade Ziffer; dieses Verhalten ist gewollt festgehalten.
    #expect(DesignText.decimal(0.25) == "0,2")
    #expect(DesignText.decimal(0.35) == "0,3")  // 0.35 ist binär 0,34999…, darum abgerundet (gemessen, festgehalten)
    #expect(DesignText.decimal(2.5, fractionDigits: 0) == "2")
    #expect(DesignText.decimal(3.5, fractionDigits: 0) == "4")
    #expect(DesignText.decimal(0.75) == "0,8")
}

@Test func designDecimalParsingAndTextRating() {
    #expect(DesignText.decimal(parsing: "7.1") == "7,1")
    #expect(DesignText.decimal(parsing: " 7,1 ") == "7,1")
    #expect(DesignText.decimal(parsing: "8") == "8,0")
    #expect(DesignText.decimal(parsing: "") == nil)
    #expect(DesignText.decimal(parsing: nil) == nil)
    #expect(DesignText.decimal(parsing: "n/a") == nil)
    #expect(DesignText.decimal(parsing: "inf") == nil)
    #expect(DesignText.rating(source: "IMDb", text: "7.1") == "IMDb 7,1")
    #expect(DesignText.rating(source: "IMDb", text: nil) == "")
    #expect(DesignText.rating(source: nil, text: "6.85", fractionDigits: 1) == "6,8")  // 6.85 ist binär 6,84999… (gemessen, festgehalten)
}
