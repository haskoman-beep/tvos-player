import SwiftUI
import PlayerCore

/// Unterseite „System › Erweitert“ (§2.2): Diagnose (Welle C-b, Gerät statt Profil), Log-Empfänger, Zeitgrenze je Addon,
/// Dolby Vision fest/FEL, Icon-Satz, Katalog-Zwischenspeicher leeren (mit Rückfrage, E6).
struct AdvancedSettingsPage: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var icons = RatingIconStore.shared
    @AppStorage(MainThreadWatchdog.settingKey) private var hitchLog = true
    @State private var confirmClear = false
    @State private var cleared = false

    private let tint = SettingsCategory.system.tint

    var body: some View {
        SettingsSubpage(title: "Erweitert", summary: "Diagnose, Addons, Bild, Zwischenspeicher") {
            SettingsSection("Diagnose") {
                SettingsToggleRow(symbol: "waveform.path.ecg", tint: tint, title: "Ruckler protokollieren",
                                  detail: "Schreibt ins Ereignis-Log, wenn die Oberfläche länger als 250 ms hängt (mit letzter Aktion und Speicherverbrauch).",
                                  reserveDetailSpace: false, isOn: $hitchLog)
                    .onChange(of: hitchLog) { MainThreadWatchdog.apply() }
                SettingsInfoRow(symbol: "antenna.radiowaves.left.and.right", tint: tint, title: "Log-Empfänger",
                                detail: "Das Ereignis-Log geht automatisch an ein Log-Programm im Heimnetz (Bonjour `_playerlog._tcp`). "
                                    + "Ohne Empfänger bleiben die letzten 500 Zeilen im Speicher.",
                                value: RemoteLog.shared.hasReceiver ? "Gefunden" : "Nur Speicher")
            }
            SettingsSection("Addons") {
                AddonTimeoutPicker()
            }
            SettingsSection("Bild") {
                DisplayModeSettingsRows(part: .advanced, tint: tint)
            }
            SettingsSection("Plaketten") {
                SettingsLinkRow(symbol: "photo.on.rectangle", tint: tint, title: "Bewertungs-Icon-Satz",
                                value: RatingIconSettingsPage.value(model.profile.sources.ratingIconSetURL, status: icons.status)) {
                    RatingIconSettingsPage()
                }
            }
            SettingsSection("Zwischenspeicher") {
                SettingsRow(symbol: "trash", tint: Theme.Tone.error.color,
                            title: cleared ? "Katalog-Zwischenspeicher geleert" : "Katalog-Zwischenspeicher leeren …",
                            detail: "Kataloge und Reihen werden danach neu geladen.", reserveDetailSpace: false) {
                    confirmClear = true
                }
                .disabled(cleared)
            }
        }
        .settingsConfirmation("Katalog-Zwischenspeicher leeren?", isPresented: $confirmClear,
                              message: "Alle Reihen laden beim nächsten Öffnen neu; das kann kurz dauern.",
                              verb: "Leeren") {
            model.clearCatalogCache()
            RemoteLog.info("einstellung", "Katalog-Zwischenspeicher geleert")
            cleared = true
        }
    }
}
