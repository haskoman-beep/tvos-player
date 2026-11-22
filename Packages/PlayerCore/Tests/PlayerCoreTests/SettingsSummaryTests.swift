import Foundation
import Testing
@testable import PlayerCore

// MARK: Tonsprache (E5)

@Test func audioPresetsMapToStoredPriority() {
    #expect(AudioLanguagePreset.germanFirst.priority == ["de", "en", "orig"])
    #expect(AudioLanguagePreset.originalFirst.priority == ["orig", "de"])
    #expect(AudioLanguagePreset.englishFirst.priority == ["en", "de", "orig"])
    // Standard des Presets = Standard eines neuen Profils.
    #expect(AudioLanguagePreset.standard.priority == Profile(name: "x").audioPriority)
    #expect(AudioLanguagePreset.germanFirst.label == "Deutsch → Englisch → Original")
    #expect(AudioLanguagePreset.originalFirst.label == "Original → Deutsch")
    #expect(AudioLanguagePreset.englishFirst.label == "Englisch → Deutsch → Original")
    #expect(AudioLanguagePreset.germanFirst.shortLabel == "Deutsch → Englisch")
    #expect(AudioLanguagePreset.originalFirst.shortLabel == "Original → Deutsch")
    #expect(AudioLanguagePreset.englishFirst.shortLabel == "Englisch → Deutsch")
}

@Test func audioPresetMatchingIgnoresCaseAndSpace() {
    #expect(AudioLanguagePreset.matching(["DE", " en ", "Orig"]) == .germanFirst)
    #expect(AudioLanguagePreset.matching(["orig", "de"]) == .originalFirst)
    #expect(AudioLanguagePreset.matching(["de", "en"]) == nil)
    #expect(AudioLanguagePreset.matching([]) == nil)
}

@Test func audioCustomOrderRoundTripsUnchanged() {
    let old = ["fr", "orig"]
    #expect(AudioLanguageChoice.of(old) == .custom)
    #expect(AudioLanguageChoice.valueText(old) == "Eigene Reihenfolge")
    #expect(AudioLanguageChoice.shortText(old) == "Eigene Reihenfolge")
    #expect(AudioLanguagePreset.describe(old) == "Französisch → Original")
    #expect(AudioLanguagePreset.describe(["xx", "de"]) == "XX → Deutsch")
    // „Eigene Reihenfolge“ steht nur zur Wahl, wenn der Wert kein Preset ist, und ändert nichts.
    #expect(AudioLanguageChoice.choices(for: old).last == .custom)
    #expect(AudioLanguageChoice.choices(for: old).count == 4)
    #expect(AudioLanguageChoice.choices(for: ["de", "en", "orig"]).count == 3)
    #expect(AudioLanguageChoice.custom.apply(to: old) == old)
    #expect(AudioLanguageChoice.preset(.englishFirst).apply(to: old) == ["en", "de", "orig"])
    // Rundreise über das gespeicherte Profil: der alte Wert überlebt Kodieren und Dekodieren unverändert.
    var p = Profile(name: "x")
    p.audioPriority = AudioLanguageChoice.of(old).apply(to: old)
    let back = try? JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(p))
    #expect(back?.audioPriority == old)
    #expect(AudioLanguageChoice.of(back?.audioPriority ?? []) == .custom)
}

@Test func subtitleLanguageChoiceKeepsUnknownValue() {
    #expect(SubtitleLanguageChoice.codes(for: "de") == ["de", "en"])
    #expect(SubtitleLanguageChoice.codes(for: "EN") == ["de", "en"])
    #expect(SubtitleLanguageChoice.codes(for: "fr") == ["de", "en", "fr"])
    #expect(SubtitleLanguageChoice.name("de") == "Deutsch")
    #expect(SubtitleLanguageChoice.name("EN") == "Englisch")
    #expect(SubtitleLanguageChoice.name("fr") == "Französisch")
    #expect(SubtitleLanguageChoice.name("") == "Keine")
    #expect(SubtitleLanguageChoice.apply("en", to: "de") == "en")
    #expect(SubtitleLanguageChoice.apply("fr", to: "FR") == "FR")
}

// MARK: Zusammenfassungen je Kategorie

@Test func summaryCounts() {
    #expect(SettingsSummary.addons(0) == "Kein Addon")
    #expect(SettingsSummary.addons(1) == "1 Addon")
    #expect(SettingsSummary.addons(3) == "3 Addons")
    #expect(SettingsSummary.rows(0) == "Keine Reihen")
    #expect(SettingsSummary.rows(1) == "1 Reihe")
    #expect(SettingsSummary.rows(24) == "24 Reihen")
    #expect(SettingsSummary.collections(1) == "1 Collection")
    #expect(SettingsSummary.catalogs(38) == "38 Kataloge")
    #expect(SettingsSummary.profiles(1) == "1 Profil")
    #expect(SettingsSummary.profiles(2) == "2 Profile")
    #expect(SettingsSummary.keyValue(nil) == "Fehlt · am Handy")
    #expect(SettingsSummary.keyValue("  ") == "Fehlt · am Handy")
    #expect(SettingsSummary.keyValue("abc") == "Gespeichert")
}

@Test func summaryProfileEveryAccountCombination() {
    #expect(SettingsSummary.profile(name: "Ich", trakt: true, simkl: false) == "Ich · Trakt verbunden")
    #expect(SettingsSummary.profile(name: "Ich", trakt: false, simkl: true) == "Ich · Simkl verbunden")
    #expect(SettingsSummary.profile(name: "Ich", trakt: true, simkl: true) == "Ich · Trakt und Simkl verbunden")
    #expect(SettingsSummary.profile(name: "Ich", trakt: false, simkl: false) == "Ich · kein Konto verbunden")
    #expect(SettingsSummary.profileMetrics(addons: 3, rows: 24, progress: .local) == ["3 Addons · 24 Reihen", "Fortschritt: Lokal"])
    #expect(SettingsSummary.profileMetrics(addons: 1, rows: 1, progress: .trakt) == ["1 Addon · 1 Reihe", "Fortschritt: Trakt"])
    #expect(SettingsSummary.profileMetrics(addons: 0, rows: 0, progress: .simkl) == ["Kein Addon · Keine Reihen", "Fortschritt: Simkl"])
}

@Test func summaryAccountStates() {
    #expect(SettingsSummary.AccountState.of(hasClient: false, connected: true) == .missingClient)
    #expect(SettingsSummary.AccountState.of(hasClient: true, connected: false) == .connectable)
    #expect(SettingsSummary.AccountState.of(hasClient: true, connected: true) == .connected)
    #expect(SettingsSummary.AccountState.connected.valueText == "Verbunden")
    #expect(SettingsSummary.AccountState.connectable.valueText == "Verbinden")
    #expect(SettingsSummary.AccountState.missingClient.valueText == "Client ID fehlt · am Handy")
}

@Test func summaryAddonsAndHome() {
    #expect(SettingsSummary.addons(count: 1, order: .smart) == "1 Addon · Smart sortiert")
    #expect(SettingsSummary.addons(count: 3, order: .addon) == "3 Addons · Wie Addon sortiert")
    #expect(SettingsSummary.addons(count: 0, order: .smart) == "Kein Addon")
    #expect(SettingsSummary.home(rows: 24, fusionKit: true) == "24 Reihen · Fusion-Kit an")
    #expect(SettingsSummary.home(rows: 1, fusionKit: false) == "1 Reihe · Fusion-Kit aus")
    #expect(SettingsSummary.home(rows: 0, fusionKit: false) == "Keine Reihen · Fusion-Kit aus")
}

@Test func summaryAppearanceAllValues() {
    #expect(SettingsSummary.appearance(navigation: .sidebar, accent: .blue, cardSize: .medium) == "Seitenleiste · Blau · Mittel")
    #expect(SettingsSummary.appearance(navigation: .top, accent: .white, cardSize: .large) == "Obere Leiste · Weiß · Groß")
    #expect(AccentChoice.allCases.map(SettingsSummary.accentName) == ["Blau", "Lila", "Pink", "Orange", "Grün", "Weiß"])
    #expect(CardSize.allCases.map(SettingsSummary.cardSizeName).sorted() == ["Groß", "Klein", "Mittel"])
    #expect(SettingsSummary.languageName(.de) == "Deutsch")
    #expect(SettingsSummary.languageName(.en) == "English")
}

@Test func summaryPlaybackCombinations() {
    #expect(SettingsSummary.playback(autoplayNext: true, diskCache: DiskCacheSettings()) == "Nächste Folge automatisch · Cache aus")
    #expect(SettingsSummary.playback(autoplayNext: false, diskCache: DiskCacheSettings(enabled: true, limitGB: 8))
            == "Nächste Folge von Hand · Cache 8 GB")
    #expect(SettingsSummary.stillWatchingName(0) == "Aus")
    #expect(SettingsSummary.stillWatchingName(3) == "nach 3 Folgen")
}

@Test func summaryAudioCombinations() {
    #expect(SettingsSummary.audio(audioPriority: ["de", "en", "orig"], subtitles: .forcedOnly)
            == "Deutsch → Englisch · Nur erzwungene Untertitel")
    #expect(SettingsSummary.audio(audioPriority: ["orig", "de"], subtitles: .off) == "Original → Deutsch · Untertitel aus")
    #expect(SettingsSummary.audio(audioPriority: ["en", "de", "orig"], subtitles: .always) == "Englisch → Deutsch · Untertitel immer")
    #expect(SettingsSummary.audio(audioPriority: ["fr"], subtitles: .always) == "Eigene Reihenfolge · Untertitel immer")
    #expect(SubtitleMode.allCases.map(SettingsSummary.subtitleModeName) == ["Aus", "Nur erzwungene", "Immer"])
}

@Test func summarySystemEveryUpdateState() {
    let ci = CIBuild(number: 36, commit: "abcdef1234")
    let rel = ReleaseBuild(number: 36, commit: "abcdef1234", ipaURL: URL(string: "https://example.com/a.ipa")!)
    #expect(SettingsSummary.UpdateStatus.of(nil) == .unknown)
    #expect(SettingsSummary.UpdateStatus.of(.upToDate(ci)) == .upToDate)
    #expect(SettingsSummary.UpdateStatus.of(.available(rel, latest: ci)) == .available(build: 36))
    #expect(SettingsSummary.UpdateStatus.of(.notPublished(ci)) == .unknown)
    #expect(SettingsSummary.UpdateStatus.of(.newerInstalled(main: 30)) == .newerInstalled)
    #expect(SettingsSummary.system(build: 35, update: .unknown) == "Build 35")
    #expect(SettingsSummary.system(build: 35, update: .upToDate) == "Build 35 · aktuell")
    #expect(SettingsSummary.system(build: 35, update: .available(build: 36)) == "Build 35 · Update: Build 36")
    #expect(SettingsSummary.system(build: nil, update: .available(build: nil)) == "Build ? · Update: Build ?")
    #expect(SettingsSummary.system(build: 40, update: .newerInstalled) == "Build 40 · neuer als veröffentlicht")
}

// MARK: Wertetexte

@Test func diskCacheSinglePickerRoundTrip() {
    #expect(SettingsSummary.diskCacheChoices == [0, 4, 8, 16, 32])
    let off = DiskCacheSettings(enabled: false, limitGB: 16)
    #expect(SettingsSummary.diskCacheChoice(off) == 0)
    #expect(SettingsSummary.diskCacheValue(off) == "Aus")
    let on = SettingsSummary.applyDiskCacheChoice(32, to: off)
    #expect(on == DiskCacheSettings(enabled: true, limitGB: 32))
    #expect(SettingsSummary.diskCacheValue(on) == "32 GB")
    // „Aus“ behält die Größe für das nächste Einschalten.
    #expect(SettingsSummary.applyDiskCacheChoice(0, to: on) == DiskCacheSettings(enabled: false, limitGB: 32))
    // Fremde Größe wird auf die nächste Auswahl gelegt.
    #expect(SettingsSummary.applyDiskCacheChoice(10, to: off).limitGB == 8)
    #expect(SettingsSummary.diskCacheChoice(DiskCacheSettings(enabled: true, limitGB: 30)) == 32)
}

@Test func audioValueTexts() {
    #expect(AudioShapingSettings.loudnessChoices.map(SettingsSummary.loudnessName) == ["Aus", "Wie Fernsehen", "Etwas lauter", "Laut"])
    #expect(SettingsSummary.loudnessName(-30) == "-30 LUFS")
    #expect(SettingsSummary.loudnessDetail(-24).contains("-24 LUFS"))
    #expect(!SettingsSummary.loudnessDetail(0).contains("LUFS"))
    #expect(AudioShapingSettings.dialogueChoices.map(SettingsSummary.dialogueName) == ["Aus", "+3 dB", "+6 dB", "+9 dB"])
    #expect(SettingsSummary.delayName(0) == "0 ms")
    #expect(SettingsSummary.delayName(50) == "+50 ms (Ton später)")
    #expect(SettingsSummary.delayName(-75) == "-75 ms (Ton früher)")
    #expect(SettingsSummary.soundSystemName(eARC: false) == "Über Fernseher (optisch/ARC)")
    #expect(SettingsSummary.soundSystemName(eARC: true) == "AV-Receiver mit eARC")
    #expect(ProgressSource.allCases.map(SettingsSummary.progressName) == ["Lokal", "Trakt", "Simkl"])
    #expect(SettingsSummary.navigationName(.sidebar) == "Seitenleiste")
    #expect(SettingsSummary.orderName(.addon) == "Wie Addon")
}
