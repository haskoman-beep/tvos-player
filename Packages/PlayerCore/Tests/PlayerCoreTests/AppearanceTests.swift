import Foundation
import Testing
@testable import PlayerCore

@Test func appearanceDefaultsFromOldProfile() throws {
    let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Alt"}"#
    let p = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
    #expect(p.appearance.navigation == .sidebar)
    #expect(p.appearance.heroEnabled)
    #expect(p.appearance == Appearance())
    // Teilweise vorhandene Aussehen-Daten: Rest bekommt Standardwerte.
    let partial = try JSONDecoder().decode(Appearance.self, from: Data(#"{"accent":"pink"}"#.utf8))
    #expect(partial.accent == .pink)
    #expect(partial.cardSize == .medium)
    #expect(partial.expandPosters)
    #expect(CardSize.large.scale == 1.2)
}

@Test func heroSourcePrefersExplicitThenHeroStyleThenFirstList() {
    let cw = HomeRow(content: .list(.continueWatching), style: .landscape)
    let coll = HomeRow(content: .collection(id: "c1"))
    let wl = HomeRow(content: .list(.watchlist), style: .poster)
    let hero = HomeRow(content: .list(.upcoming), style: .hero)

    // 1. explizit gewählte Reihe
    let l1 = HomeLayout(rows: [cw, wl, hero])
    #expect(l1.heroSource(Appearance(heroRowID: wl.id))?.id == wl.id)
    // 2. erste Hero-Reihe (auch bei unbekannter heroRowID)
    #expect(l1.heroSource(Appearance())?.id == hero.id)
    #expect(l1.heroSource(Appearance(heroRowID: UUID()))?.id == hero.id)
    // 3. erste Liste, die nicht Weiterschauen ist
    let l3 = HomeLayout(rows: [cw, coll, wl])
    #expect(l3.heroSource(Appearance())?.id == wl.id)
}

@Test func heroSourceNilWhenDisabledOrNoList() {
    let hero = HomeRow(content: .list(.watchlist), style: .hero)
    #expect(HomeLayout(rows: [hero]).heroSource(Appearance(heroEnabled: false)) == nil)
    let l = HomeLayout(rows: [HomeRow(content: .list(.continueWatching)), HomeRow(content: .collection(id: "c1"))])
    #expect(l.heroSource(Appearance()) == nil)
    #expect(HomeLayout().heroSource(Appearance()) == nil)
}

@Test func rowsBelowHeroHidesHeroStyleRow() {
    let cw = HomeRow(content: .list(.continueWatching), style: .landscape)
    let wl = HomeRow(content: .list(.watchlist), style: .poster)
    let hero = HomeRow(content: .list(.upcoming), style: .hero)
    let l = HomeLayout(rows: [cw, hero, wl])
    #expect(l.rowsBelowHero(Appearance()).map(\.id) == [cw.id, wl.id])
    // Hero-Quelle ist eine normale Liste: bleibt als Reihe sichtbar.
    #expect(l.rowsBelowHero(Appearance(heroRowID: wl.id)).map(\.id) == [cw.id, hero.id, wl.id])
    // Hero aus: nichts wird ausgeblendet.
    #expect(l.rowsBelowHero(Appearance(heroEnabled: false)).map(\.id) == [cw.id, hero.id, wl.id])
}
