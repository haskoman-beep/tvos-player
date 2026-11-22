import SwiftUI
import PlayerCore

/// Wave S: category „Bild & Ton“, everything that depends on TV and sound system: Bild (HDMI-Modus, Dolby Vision
/// fest, FEL), Anlage, Klang, Versatz, Gerätecheck. Rows unchanged, only moved (from Wiedergabe & Bild › Bild,
/// System › Erweitert › Bild, Ton & Untertitel, System › Gerätecheck). The values are still stored per profile;
/// the page says so (`SettingsCategory.scope`).
struct PictureSoundSettings: View {
    @EnvironmentObject var model: AppModel

    private let tint = SettingsCategory.picture.tint

    var body: some View {
        let p = model.profile
        CategoryPage(.picture, summary: SettingsSummary.picture(soundSystemEARC: p.audioShaping.hasEARCReceiver,
                                                                keepsMode: p.displayMode.keepModeBetweenEpisodes,
                                                                dolbyVisionForced: p.displayMode.panelPresentsDolbyVision,
                                                                alwaysStereo: p.audioShaping.safeStereo)) {
            SettingsSection("Bild") {
                DisplayModeSettingsRows(part: .basic, tint: tint)
                DisplayModeSettingsRows(part: .advanced, tint: tint)
            }
            AudioShapingSettingsRows()
            SettingsFootnote("Ton-Einstellungen gelten ab dem nächsten Start der Wiedergabe.")
            SettingsSection("Prüfen") {
                SettingsLinkRow(symbol: "checkmark.seal", tint: tint, title: "Gerätecheck",
                                detail: "Ist das Apple TV richtig eingestellt? Und was spielt wie?") {
                    DeviceCheckPage()
                }
            }
        }
    }
}
