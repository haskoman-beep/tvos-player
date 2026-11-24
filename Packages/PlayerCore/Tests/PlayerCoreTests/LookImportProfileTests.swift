import Foundation
import Testing
@testable import PlayerCore

// Task 4.3 fix round 1: an imported look on a real `Profile` (with the 4.2 observers on `appearance`/`player`).

private let edelValues = """
{"schema":"player.appearance.preset","version":1,"preset":"edel","values":{
 "global":{"navigation":"seitenleiste","clock":true,"settingsLayout":"spalten","accent":"champagner","background":"graphit",
           "typeScale":"standard","typeCharacter":"editorial","motion":"dezent"},
 "home":{"heroStyle":"vollbild","heroInfo":"standard","heroTitle":"logo","backdropFollowsFocus":true,"cardShape":"mischung",
         "cardSize":"mittel","corners":"weich","rowSpacing":"luftig","rowTitle":"dezent","cardTitles":"fokus","expandPosters":false,
         "focusScale":"dezent","focusBorder":"weiss","focusShadow":"weich","focusGlow":false},
 "detail":{"layout":"links","descriptionLines":3,"cast":"kreise","badgeStyle":"umriss","ratingStyle":"symbole","sourceList":"karten"},
 "player":{"controlBar":"standard","badges":"kompakt","timeDisplay":"rest","trackPanel":"seite","upNext":"karte","stillWatching":"karte"}}}
"""

@Test func importedLookOnProfileSurvivesAndWritesOldFields() throws {
    let edel = try LookImport.parse(Data(edelValues.utf8)).look
    var p = Profile.makeDefault()
    p.appearance.navigation = .top; p.appearance.accent = .blue; p.appearance.badges.style = .logo
    p.player.trackPanelStyle = .bottomBar
    p.applyImportedLook(edel)
    #expect(p.look == edel)
    #expect(p.appearance.navigation == .sidebar && p.appearance.accent == .white && p.appearance.cardSize == .medium)
    #expect(p.appearance.heroEnabled && !p.appearance.expandPosters && p.appearance.badges.style == .text)
    #expect(p.player.trackPanelStyle == .topBar)
    let back = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(p))
    #expect(back.look == edel && back.appearance.accent == .white)
    // A later edit in the old settings does not wipe the imported (non-derived) look.
    p.appearance.cardSize = .small
    p.player.trackPanelStyle = .menu
    #expect(p.look == edel)
    #expect(p.look.resolved().global.accent == .champagner)
}

@Test func importedDerivedLookFollowsLaterOldFieldEdits() throws {
    // A look that maps exactly onto the old fields stays derived: later old-field edits keep it in step.
    var o = LookOverrides(); o.global.navigation = .seitenleiste; o.home.cardSize = .klein
    let l = Look(overrides: o)
    var p = Profile.makeDefault()
    p.applyImportedLook(l)
    #expect(p.look.resolved() == l.resolved())
    #expect(p.appearance.navigation == .sidebar && p.appearance.cardSize == .small)
    p.appearance.cardSize = .large
    #expect(p.look.resolved().home.cardSize == .gross)
}
