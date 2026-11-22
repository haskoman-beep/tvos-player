import SwiftUI
import PlayerCore

/// Kategorie 5 „Wiedergabe & Bild“ (§2.2): Folgen, Ton & Untertitel im Player, Film zwischenspeichern, Bildschirmschoner, Bild.
/// Sprache der App → Aussehen, Tonsprache/Untertitel → Ton & Untertitel, Fortschritt → Profil & Konten,
/// Quellen vorladen/sortieren → Addons & Quellen.
struct PlaybackSettings: View {
    @EnvironmentObject var model: AppModel

    private let tint = SettingsCategory.playback.tint

    var body: some View {
        let p = model.profile
        CategoryPage(.playback, summary: SettingsSummary.playback(autoplayNext: p.autoplayNext, diskCache: p.diskCache)) {
            SettingsSection("Folgen") {
                SettingsToggleRow(symbol: "forward.end", tint: tint, title: "Nächste Folge automatisch",
                                  detail: "Startet am Ende einer Folge die nächste.",
                                  reserveDetailSpace: false, isOn: model.binding(\.autoplayNext))
                SettingsChoiceRow(symbol: "questionmark.bubble", tint: tint, title: "„Noch da?“ fragen",
                                  detail: "Fragt vor der nächsten Folge, wenn so viele Folgen ohne Tastendruck liefen.",
                                  options: StillWatchingCounter.choices, selection: model.binding(\.stillWatchingAfter),
                                  label: SettingsSummary.stillWatchingName)
                PlayerComfortSettingsRows(part: .tracks)
            }
            SettingsSection("Ton & Untertitel im Player") {
                PlayerComfortSettingsRows(part: .panelStyle)
            }
            SettingsSection("Zwischenspeichern") {
                SettingsChoiceRow(symbol: "internaldrive", tint: tint, title: "Film zwischenspeichern",
                                  detail: "Speichert den laufenden Film auf dem Gerät: Zurückspulen und kurze Netzaussetzer ohne Neuladen. "
                                      + "Lässt immer mindestens 2 GB frei; wird beim Schließen des Players gelöscht. Nicht für HLS-Quellen.",
                                  options: SettingsSummary.diskCacheChoices,
                                  selection: Binding(get: { SettingsSummary.diskCacheChoice(model.profile.diskCache) },
                                                     set: { gb in model.update { $0.diskCache = SettingsSummary.applyDiskCacheChoice(gb, to: $0.diskCache) } }),
                                  label: SettingsSummary.diskCacheChoiceName)
            }
            SettingsSection("Bildschirmschoner") {
                PlayerComfortSettingsRows(part: .screensaver)
            }
            SettingsSection("iPhone & Kontrollzentrum") {
                PlayerComfortSettingsRows(part: .remote)
            }
            SettingsSection("Bild") {
                DisplayModeSettingsRows(part: .basic, tint: tint)
                SettingsFootnote("Dolby Vision fest angeben und FEL einrechnen: System › Erweitert.")
            }
        }
    }
}
