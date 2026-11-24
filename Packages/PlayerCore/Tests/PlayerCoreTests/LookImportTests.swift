import Foundation
import Testing
@testable import PlayerCore

// Task 4.3 (04-system-design §8.4): a configurator export (`schema` "player.appearance.preset") comes in through the
// phone page. Its `preset` is not taken over; `values` become overrides against "Mein Look" (`.appleTV`).

private func importFixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func post(_ path: String, _ body: String) -> HTTPRequest {
    let s = "POST \(path) HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
    guard case .complete(let r) = HTTPRequest.parse(Data(s.utf8)) else { fatalError("parse") }
    return r
}

private func formEncoded(_ s: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
}

/// The example of 07-design-analyse §5.2 (configurator preset "edel").
private let edelExport = """
{"schema":"player.appearance.preset","version":1,"preset":"edel","modified":false,"exportedAt":"2026-11-22T21:00:00.000Z",
 "values":{
  "global":{"navigation":"seitenleiste","clock":true,"settingsLayout":"spalten","accent":"champagner","background":"graphit",
            "typeScale":"standard","typeCharacter":"editorial","motion":"dezent"},
  "home":{"heroStyle":"vollbild","heroInfo":"standard","heroTitle":"logo","backdropFollowsFocus":true,"cardShape":"mischung",
          "cardSize":"mittel","corners":"weich","rowSpacing":"luftig","rowTitle":"dezent","cardTitles":"fokus","expandPosters":false,
          "focusScale":"dezent","focusBorder":"weiss","focusShadow":"weich","focusGlow":false},
  "detail":{"layout":"links","descriptionLines":3,"cast":"kreise","badgeStyle":"umriss","ratingStyle":"symbole","sourceList":"karten"},
  "player":{"controlBar":"standard","badges":"kompakt","timeDisplay":"rest","trackPanel":"seite","upNext":"karte","stillWatching":"karte"}}}
"""

@Test func lookImportIgnoresForeignSchemaAndHigherVersion() throws {
    let foreign = Data(#"{"schema":"player.widgets","version":1,"values":{}}"#.utf8)
    #expect(throws: LookImport.Failure.foreignSchema("player.widgets")) { try LookImport.parse(foreign) }
    #expect(LookImport.Failure.foreignSchema("player.widgets").text.contains("player.widgets"))
    let future = Data(#"{"schema":"player.appearance.preset","version":7,"preset":"appletv","future":{"x":1},"values":{"global":{"accent":"blau","glass":"hell"},"home":{"cardSize":"mittel"},"extra":{"a":1}}}"#.utf8)
    let (look, report) = try LookImport.parse(future)
    #expect(look.version == LookSchema.current)
    #expect(look.overrides.global.accent == .blau && look.overrides.home.cardSize == .mittel)
    #expect(look.overrides.count == 2)
    #expect(report.isEmpty)   // unknown keys are ignored, not reported
}

@Test func lookImportRejectsWhatIsNoExport() {
    for raw in ["", "nicht json", "[1,2]", #"{"version":1,"values":{}}"#, #"{"schema":5}"#,
                #"{"schema":"player.appearance.preset","version":1}"#] {
        #expect(throws: LookImport.Failure.notAnExport, "\(raw)") { try LookImport.parse(Data(raw.utf8)) }
    }
    #expect(!LookImport.Failure.notAnExport.text.isEmpty)
}

@Test func lookImportOfMeinLookExportHasNoOverrides() throws {
    let (look, report) = try LookImport.parse(try importFixture("konfigurator-export.json"))
    #expect(look == Look())
    #expect(look.overrides.isEmpty && report.isEmpty)
    #expect(look.resolved() == LookPreset.values(.appleTV))
}

@Test func lookImportIgnoresUnknownValuesAndReportsThem() throws {
    let raw = #"{"schema":"player.appearance.preset","version":1,"preset":"kino","values":{"global":{"accent":"neon","navigation":"seitenleiste"},"home":{"cardSize":"riesig","focusGlow":"ja"},"detail":{"descriptionLines":4}}}"#
    let (look, report) = try LookImport.parse(Data(raw.utf8))
    #expect(look.preset == .appleTV)
    #expect(look.overrides.count == 1 && look.overrides.global.navigation == .seitenleiste)
    #expect(look.resolved().global.accent == LookPreset.values(.appleTV).global.accent)
    #expect(Set(report.ignored) == ["values.global.accent", "values.home.cardSize", "values.home.focusGlow",
                                    "values.detail.descriptionLines"])
}

@Test func importFromOtherPresetBecomesOverrides() throws {
    let (look, report) = try LookImport.parse(Data(edelExport.utf8))
    #expect(look.preset == .appleTV)
    #expect(report.isEmpty)
    // Every value of the edel example that differs from "Mein Look" (07 §5.2 against export.json).
    #expect(look.overrides.count == 26)
    let v = look.resolved()
    #expect(v.global.accent == .champagner && v.home.cardShape == .mischung && v.detail.descriptionLines == .three)
    #expect(v.player.stillWatching == .karte && v.home.rowSpacing == .luftig)
    #expect(look.overrides.home.rowSpacing == nil)   // same as Mein Look: no override
    #expect(Look(preset: .appleTV, overrides: look.overrides).resolved() == v)
}

@Test func phoneImportDetectRecognizesLookExport() throws {
    guard case .command(let cmd) = PhoneImportDetect.detect("  " + edelExport + "\n") else {
        Issue.record("not detected"); return
    }
    let expected = try LookImport.parse(Data(edelExport.utf8)).look
    #expect(cmd == .look(expected))
    #expect(cmd.sensitivity == .plain)
    #expect(PhoneImportDetect.detect(#"{"schema":"player.appearance.preset","version":1}"#) == .refused(.lookInvalid))
    // Other JSON still goes where it went before.
    #expect(PhoneImportDetect.detect(#"{"schema":"player.widgets"}"#) != .refused(.lookInvalid))
}

@Test func phoneLookFieldsSendCommandAndReportBack() throws {
    let page = PhoneInputPage()
    let raw = #"{"schema":"player.appearance.preset","version":1,"preset":"edel","values":{"global":{"accent":"neon","navigation":"seitenleiste"},"home":{"cardSize":"mittel","focusGlow":"ja"}}}"#
    for field in ["look_json", "import"] {
        let (resp, cmds) = page.handle(post("/submit?t=tok", "\(field)=\(formEncoded(raw))"), profileName: "Ich") { Data() }
        #expect(cmds == [.look(try LookImport.parse(Data(raw.utf8)).look)], "\(field)")
        let loc = try #require(resp.extraHeaders["Location"])
        #expect(loc.contains("lk=2") && loc.contains("lku=2"), "\(loc)")
        let q = Dictionary(uniqueKeysWithValues: (URLComponents(string: loc)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let html = page.page(profileName: "Ich", note: q["ok"], importNote: q["imp"], lookNote: q["lk"], lookUnknown: q["lku"])
        #expect(html.contains("Aussehen übernommen · 2 Abweichungen"))
        #expect(html.contains("2 Werte kannte diese App-Version nicht"))
    }
    // A broken file in the look field: nothing sent, the page says why.
    let (resp, cmds) = page.handle(post("/submit?t=tok", "look_json=\(formEncoded(#"{"schema":"x.y"}"#))"), profileName: "Ich") { Data() }
    #expect(cmds.isEmpty)
    let loc = try #require(resp.extraHeaders["Location"])
    #expect(loc.contains("lk=fremd"), "\(loc)")
    #expect(page.page(profileName: "Ich", note: nil, lookNote: "fremd").contains("Aussehen nicht übernommen"))
    // The page offers the field.
    #expect(page.page(profileName: "Ich", note: nil).contains("name=look_json"))
}

@Test func importedLookWritesOldFieldsWhereTheyMap() {
    var o = LookOverrides()
    o.global.navigation = .seitenleiste; o.global.accent = .salbei
    o.home.cardSize = .klein; o.home.heroStyle = .aus; o.home.expandPosters = true
    o.detail.badgeStyle = .logos; o.player.trackPanel = .mitte
    var appearance = Appearance(); var player = PlayerComfortSettings()
    appearance.navigation = .top; appearance.badges.style = .text
    let look = Look(overrides: o)
    look.writeOldFields(appearance: &appearance, player: &player)
    #expect(appearance.navigation == .sidebar && appearance.accent == .green && appearance.cardSize == .small)
    #expect(!appearance.heroEnabled && appearance.expandPosters && appearance.badges.style == .logo)
    #expect(player.trackPanelStyle == .menu)
    // Mapped back, the old fields migrate to the same look.
    #expect(Look.migrated(from: appearance, player: player, sources: SourceSettings()) == look)
    // Values without an old counterpart leave the old field as it was; koralle keeps pink.
    var a2 = Appearance(); a2.accent = .pink; a2.badges.style = .text
    var p2 = PlayerComfortSettings()
    var o2 = LookOverrides(); o2.global.accent = .koralle; o2.detail.badgeStyle = .umriss
    Look(overrides: o2).writeOldFields(appearance: &a2, player: &p2)
    #expect(a2.accent == .pink && a2.badges.style == .text)
    var a3 = Appearance(); a3.accent = .blue
    var o3 = LookOverrides(); o3.global.accent = .champagner
    Look(overrides: o3).writeOldFields(appearance: &a3, player: &p2)
    #expect(a3.accent == .blue)
    var a4 = Appearance(); a4.accent = .blue
    var o4 = LookOverrides(); o4.global.accent = .koralle
    Look(overrides: o4).writeOldFields(appearance: &a4, player: &p2)
    #expect(a4.accent == .orange)
}
