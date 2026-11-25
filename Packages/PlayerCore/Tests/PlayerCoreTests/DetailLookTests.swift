import Foundation
import Testing
@testable import PlayerCore

// Task 5.3 (Build 5b): the rules behind the detail page options (`LookDetail` plus the two profile-owned extras
// `episodes` and `titleArt`, ruling 24.11.).

@Test func detailLayoutPicksOneVariant() {
    let links = DetailLook.layout(.links, contentLeading: 80)
    #expect(links.alignment == .leading)
    #expect(links.leadingInset == 80)
    #expect(links.infoWidth == 1100)
    #expect(links.anchorsBottom == false)
    #expect(links.shades == [.leading, .bottom])

    let centred = DetailLook.layout(.zentriert, contentLeading: 80)
    #expect(centred.alignment == .center)
    #expect(centred.leadingInset == 260 && centred.trailingInset == 260)
    #expect(centred.castWidth == 860)
    #expect(centred.anchorsBottom == false)
    #expect(centred.shades == [.fromBottom([.init(0, 1.0), .init(0.45, 0.8), .init(1.0, 0.25)])])

    let cinema = DetailLook.layout(.kino, contentLeading: 150)
    #expect(cinema.alignment == .leading)
    #expect(cinema.leadingInset == 150)
    #expect(cinema.infoWidth == 900)
    #expect(cinema.bottomInset == 70)
    #expect(cinema.anchorsBottom)
    #expect(cinema.shades == [.fromBottom([.init(0, 0.96), .init(0.30, 0.5), .init(0.55, 0)])])

    // Every value gives its own variant.
    let all = LookDetailLayout.allCases.map { DetailLook.layout($0, contentLeading: 80) }
    #expect(Set(all.map(\.variant)).count == LookDetailLayout.allCases.count)
}

@Test func detailGradientsMatchTheTokens() {
    #expect(DetailShade.leading == .fromLeading([.init(0, 0.92), .init(0.38, 0.55), .init(0.70, 0)]))
    #expect(DetailShade.bottom == .fromBottom([.init(0, 1.0), .init(0.22, 0.75), .init(0.45, 0)]))
}

@Test func descriptionLineLimit() {
    #expect(DetailLook.descriptionLineLimit(.two, layout: .links) == 2)
    #expect(DetailLook.descriptionLineLimit(.three, layout: .zentriert) == 3)
    #expect(DetailLook.descriptionLineLimit(.five, layout: .links) == 5)
    // The cinema layout keeps the text short over the picture (configurator: at most 3 lines).
    #expect(DetailLook.descriptionLineLimit(.five, layout: .kino) == 3)
    #expect(DetailLook.descriptionLineLimit(.two, layout: .kino) == 2)
}

@Test func castTextJoinsNames() {
    #expect(DetailLook.castLine(["A", "B", "C"]) == "Mit A, B, C")
    #expect(DetailLook.castLine(["A"]) == "Mit A")
    #expect(DetailLook.castLine([]) == nil)
    #expect(DetailLook.castLine(["", " "]) == nil)
    // One line: at most five names.
    #expect(DetailLook.castLine(["A", "B", "C", "D", "E", "F", "G"]) == "Mit A, B, C, D, E")
}

@Test func logoBadgesFallBackToFilledInPlayer() {
    #expect(DetailLook.badgeStyle(.logos, inPlayer: true) == .gefuellt)
    #expect(DetailLook.badgeStyle(.logos, inPlayer: false) == .logos)
    for s in [LookBadgeStyle.umriss, .gefuellt, .text] {
        #expect(DetailLook.badgeStyle(s, inPlayer: true) == s)
        #expect(DetailLook.badgeStyle(s, inPlayer: false) == s)
    }
}

@Test func ratingStyleTilesBecomeSymbolsInCinema() {
    #expect(DetailLook.ratingStyle(.kacheln, layout: .kino) == .symbole)
    #expect(DetailLook.ratingStyle(.kacheln, layout: .links) == .kacheln)
    #expect(DetailLook.ratingStyle(.text, layout: .kino) == .text)
}

@Test func ratingLineUsesNamesAndGermanNumbers() {
    let r = [RatingBadge(source: "imdb", label: "IMDb", text: "7.9", score: 79),
             RatingBadge(source: "tomatoes", label: "🍅", text: "92%", score: 92),
             RatingBadge(source: "trakt", label: "Trakt", text: "81%", score: 81)]
    #expect(DetailLook.ratingLine(r) == "IMDb 7,9   Tomatometer 92\u{00A0}%   Trakt 81\u{00A0}%")
    #expect(DetailLook.ratingLine([]) == nil)
    #expect(DetailLook.ratingName(RatingBadge(source: "popcorn", label: "🍿", text: "80%", score: 80)) == "Popcornmeter")
}

@Test func episodesRowStartsAtFirstUnwatched() {
    let eps = [EpisodeRef(season: 2, episode: 1), EpisodeRef(season: 2, episode: 2), EpisodeRef(season: 2, episode: 3)]
    #expect(DetailLook.episodeRowStart(eps, isWatched: { $0.episode == 1 }) == EpisodeRef(season: 2, episode: 2))
    #expect(DetailLook.episodeRowStart(eps, isWatched: { _ in false }) == EpisodeRef(season: 2, episode: 1))
    // All watched: the row starts at the first episode.
    #expect(DetailLook.episodeRowStart(eps, isWatched: { _ in true }) == EpisodeRef(season: 2, episode: 1))
    #expect(DetailLook.episodeRowStart([], isWatched: { _ in false }) == nil)
    // A gap in the watched run counts: the first unwatched one, not the one after the last watched.
    #expect(DetailLook.episodeRowStart(eps, isWatched: { $0.episode == 1 || $0.episode == 3 })
            == EpisodeRef(season: 2, episode: 2))
}

@Test func titleArtFallsBackToPosterWithoutLogo() {
    let withLogo = DetailLook.titleArt(.logo, logo: "https://example.invalid/logo.png")
    #expect(withLogo == DetailTitleArt(logo: "https://example.invalid/logo.png", showsPoster: false))
    let noLogo = DetailLook.titleArt(.logo, logo: nil)
    #expect(noLogo == DetailTitleArt(logo: nil, showsPoster: true))
    #expect(DetailLook.titleArt(.logo, logo: "  ") == DetailTitleArt(logo: nil, showsPoster: true))
    // Poster: always the poster; a logo still replaces the text title (today's page).
    #expect(DetailLook.titleArt(.poster, logo: "https://example.invalid/l.png")
            == DetailTitleArt(logo: "https://example.invalid/l.png", showsPoster: true))
    #expect(DetailLook.titleArt(.poster, logo: nil) == DetailTitleArt(logo: nil, showsPoster: true))
}

@Test func missingDetailExtrasDecodeToDefaults() throws {
    // Build 4 profile: no `detailExtras` key.
    let url = try #require(Bundle.module.url(forResource: "build4-profiles-look.json", withExtension: nil,
                                             subdirectory: "Fixtures"))
    let (stored, report) = try ProfileStore.decodeReporting(try Data(contentsOf: url))
    for p in stored.profiles {
        #expect(p.detailExtras == LookDetailExtras())
        #expect(p.detailExtras.episodes == .reihe)
        #expect(p.detailExtras.titleArt == .logo)
    }
    #expect(report.ignored.allSatisfy { !$0.contains("detailExtras") })

    // Unknown values fall back one by one and are noted; the rest of the profile loads.
    let json = #"{"id":"00000000-0000-0000-0000-000000000001","name":"X","detailExtras":{"episodes":"kacheln","titleArt":"poster"}}"#
    let (p, r) = try JSONDecoder().decodeReporting(Profile.self, from: Data(json.utf8))
    #expect(p.detailExtras.episodes == .reihe)
    #expect(p.detailExtras.titleArt == .poster)
    #expect(r.ignored.contains { $0.contains("detailExtras") && $0.contains("episodes") })

    // Wrong type for the whole field: defaults, noted.
    let bad = #"{"id":"00000000-0000-0000-0000-000000000001","name":"X","detailExtras":5}"#
    let (q, r2) = try JSONDecoder().decodeReporting(Profile.self, from: Data(bad.utf8))
    #expect(q.detailExtras == LookDetailExtras())
    #expect(r2.ignored.contains { $0.contains("detailExtras") })
}

@Test func detailExtrasAreWrittenOnlyWhenChanged() throws {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    var p = Profile(name: "X")
    let plain = try #require(try JSONSerialization.jsonObject(with: enc.encode(p)) as? [String: Any])
    #expect(plain["detailExtras"] == nil)
    p.detailExtras.episodes = .liste
    let data = try enc.encode(p)
    let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let extras = try #require(obj["detailExtras"] as? [String: Any])
    #expect(extras["episodes"] as? String == "liste")
    #expect(try JSONDecoder().decode(Profile.self, from: data).detailExtras.episodes == .liste)
}

@Test func detailExtraRowsReadAndWriteTheProfileField() {
    var p = Profile(name: "X")
    #expect(LookOptionCatalog.extras.map(\.key) == ["episodes", "titleArt"])
    #expect(LookOptionCatalog.rows.count == LookOptionCatalog.all.count + 2)
    #expect(LookOptionCatalog.all.count == 35)
    #expect(p.lookRawValue("episodes") == "reihe")
    #expect(p.lookRawValue("titleArt") == "logo")
    #expect(!p.isLookOverridden("episodes"))
    let lookBefore = p.look
    p.setLook("episodes", to: "liste")
    #expect(p.detailExtras.episodes == .liste)
    #expect(p.isLookOverridden("episodes"))
    #expect(p.look == lookBefore)
    p.setLook("titleArt", to: "bogus")
    #expect(p.detailExtras.titleArt == .logo)
    p.setLook("episodes", to: nil)
    #expect(p.detailExtras.episodes == .reihe)
    p.setLook("titleArt", to: "poster")
    p.resetLook()
    #expect(p.detailExtras == LookDetailExtras())
}

@Test func detailRowsAreActiveInBuild5b() {
    let v = LookPreset.baseline
    for key in ["layout", "descriptionLines", "cast", "badgeStyle", "ratingStyle", "sourceList", "episodes", "titleArt"] {
        #expect(LookOptionCatalog.isEnabled(key, in: v) == (true, nil), "\(key)")
    }
    // Without the implemented set the build rule still says when an option comes.
    #expect(LookOptionCatalog.isEnabled("sourceList", in: v, implemented: []).reason == "kommt mit Build 5b")
}

// Review fix round (W1, W4): the title slot while the meta loads and after a failed logo.
@Test func titleArtHoldsThePosterUntilTheMetaIsKnown() {
    // titleArt = logo, meta not there yet: neither poster nor logo; the slot is kept so nothing jumps later.
    let pending = DetailLook.titleArt(.logo, logo: nil, metaKnown: false, logoFailed: false)
    #expect(pending == DetailTitleArt(logo: nil, showsPoster: false, reservesLogoSlot: true))
    // Meta came with a logo: the logo fills the kept slot, the poster never showed.
    #expect(DetailLook.titleArt(.logo, logo: "https://example.invalid/l.png", metaKnown: true, logoFailed: false)
            == DetailTitleArt(logo: "https://example.invalid/l.png", showsPoster: false, reservesLogoSlot: true))
    // Meta without a logo: poster and text title (today's page).
    #expect(DetailLook.titleArt(.logo, logo: nil, metaKnown: true, logoFailed: false)
            == DetailTitleArt(logo: nil, showsPoster: true))
    // Poster style never waits.
    #expect(DetailLook.titleArt(.poster, logo: nil, metaKnown: false, logoFailed: false)
            == DetailTitleArt(logo: nil, showsPoster: true))
}

@Test func failedLogoBringsBackPosterAndTextTitle() {
    let url = "https://example.invalid/l.png"
    #expect(DetailLook.titleArt(.logo, logo: url, metaKnown: true, logoFailed: true)
            == DetailTitleArt(logo: nil, showsPoster: true))
    #expect(DetailLook.titleArt(.poster, logo: url, metaKnown: true, logoFailed: true)
            == DetailTitleArt(logo: nil, showsPoster: true))
}

// Review fix round (W3): the kino head from the measured scroll area, not a 1080 constant.
@Test func kinoHeadHeightUsesTheMeasuredArea() {
    // Movie: area minus the top padding and the bottom inset of the info.
    #expect(DetailLook.kinoHeadHeight(area: 960, topPadding: 60, bottomInset: 70, series: false) == 830)
    // Series: 420 pt stay for the season bar and the episodes.
    #expect(DetailLook.kinoHeadHeight(area: 960, topPadding: 60, bottomInset: 70, series: true) == 410)
    // Not measured yet (0) or too small: no minimum height.
    #expect(DetailLook.kinoHeadHeight(area: 0, topPadding: 60, bottomInset: 70, series: false) == nil)
    #expect(DetailLook.kinoHeadHeight(area: 500, topPadding: 60, bottomInset: 70, series: true) == nil)
}
