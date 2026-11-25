import Foundation
import Testing
@testable import PlayerCore

// Build 4 follow-up 2, device test 1 (P3, user decision option a): the home hero backdrop decodes at most
// 1920×1080 px on every TV (it is dimmed by two gradients). On a 4K TV the old full-screen target decoded a 4K original
// at 3840×2160 (≈ 31.6 MiB per swap); the detail page backdrop keeps its own size.

@Test func heroBackdropTargetIsFixed1080pFill() {
    let t = ImageTarget.heroBackdrop
    #expect(t.width == 1920)
    #expect(t.height == 1080)
    #expect(t.fit == false)
    #expect(t.cacheKey == "1920x1080c")
}

@Test func heroBackdropDecodesA4KOriginalAt1920x1080() {
    let t = ImageTarget.heroBackdrop
    // 3840×2160 → longer side 1920, so the bitmap is 1920×1080 (4 bytes per pixel ≈ 7.9 MiB instead of ≈ 31.6 MiB).
    #expect(t.decodeMaxPixels(imageWidth: 3840, imageHeight: 2160) == 1920)
    #expect(t.decodeMaxPixels(imageWidth: 1920, imageHeight: 1080) == 1920)
    // Never larger than the original.
    #expect(t.decodeMaxPixels(imageWidth: 1280, imageHeight: 720) == 1280)
    // A wider original still covers 1080 rows (fill): 4096×2160 → 2048×1080.
    #expect(t.decodeMaxPixels(imageWidth: 4096, imageHeight: 2160) == 2048)
}

@Test func heroBackdropIsSmallerThanTheOld4KTarget() {
    // The old target on a 4K TV: 1920×1080 points × 2, stepped to 3840×2560.
    let old = ImageTarget(points: 1920, 1080, scale: 2, fit: false)
    #expect(old?.cacheKey == "3840x2560c")
    #expect(old?.decodeMaxPixels(imageWidth: 3840, imageHeight: 2160) == 3840)
    #expect(ImageTarget.heroBackdrop.cacheKey != old?.cacheKey)
}

@Test func heroBackdropStillAsksTMDBForTheOriginal() {
    // No TMDB width between 1280 and the original reaches 1920, so the download stays the original; only the decode is
    // capped. A w1280 address is not narrowed below the target.
    let t = ImageTarget.heroBackdrop
    #expect(t.neededSourceWidth == 1920)
    let url = "https://image.tmdb.org/t/p/w1280/abc.jpg"
    #expect(ImageURLVariant.candidates(for: url, neededWidth: t.neededSourceWidth)
        == ["https://image.tmdb.org/t/p/original/abc.jpg", url])
}

@Test func heroBackdropKeepsTheOtherSideWholeForTallerOriginals() {
    // P3 review 2 (M1): fill covers 1920×1080, so the cap is exact only for 16:9. Pinned as is, not changed.
    let t = ImageTarget.heroBackdrop
    // 4:3 original 2880×2160 → 1920 columns kept → 1920×1440.
    #expect(t.decodeMaxPixels(imageWidth: 2880, imageHeight: 2160) == 1920)
    // Portrait poster fallback (`background ?? poster`) 2000×3000 → 1920×2880 (≈ 21 MiB; before 2000×3000).
    #expect(t.decodeMaxPixels(imageWidth: 2000, imageHeight: 3000) == 2880)
    // 21:9 original 3840×1600 → 1080 rows kept → 2592×1080.
    #expect(t.decodeMaxPixels(imageWidth: 3840, imageHeight: 1600) == 2592)
}
