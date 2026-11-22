import SwiftUI
import PlayerCore

/// Unterseite „System › Erweitert“ (§2.2): Diagnose (Welle C-b, Gerät statt Profil), Log-Empfänger, Zeitgrenze je Addon,
/// Dolby Vision fest/FEL, Icon-Satz, Katalog-Zwischenspeicher leeren (mit Rückfrage, E6).
struct AdvancedSettingsPage: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var icons = RatingIconStore.shared
    @AppStorage(MainThreadWatchdog.settingKey) private var hitchLog = true
    @AppStorage(XRayProbe.settingKey) private var xrayProbe = false
    @State private var confirmClear = false
    @State private var cleared = false
    /// Review F-a M4: RemoteLog ist kein ObservableObject; die Seite fragt den Empfänger alle 2 s neu ab.
    @State private var receiver = RemoteLog.shared.hasReceiver

    private let tint = SettingsCategory.system.tint

    var body: some View {
        SettingsSubpage(title: "Erweitert", summary: "Diagnose, Addons, Bild, Zwischenspeicher") {
            SettingsSection("Diagnose") {
                SettingsToggleRow(symbol: "waveform.path.ecg", tint: tint, title: "Ruckler protokollieren",
                                  detail: "Schreibt ins Ereignis-Log, wenn die Oberfläche länger als 250 ms hängt (mit letzter Aktion und Speicherverbrauch).",
                                  reserveDetailSpace: false, isOn: $hitchLog)
                    .onChange(of: hitchLog) { MainThreadWatchdog.apply() }
                SettingsToggleRow(symbol: "person.crop.rectangle", tint: tint, title: "Gesichter bei Pause prüfen (Test)",
                                  detail: "Entwicklung: Bei jeder Pause sucht das Gerät Gesichter im Standbild und schreibt Zeiten und Größen ins Ereignis-Log (xray). Nichts wird angezeigt oder gespeichert.",
                                  reserveDetailSpace: false, isOn: $xrayProbe)
                SettingsInfoRow(symbol: "antenna.radiowaves.left.and.right", tint: tint, title: "Log-Empfänger",
                                detail: "Das Ereignis-Log geht automatisch an ein Log-Programm im Heimnetz (Bonjour, Dienst _playerlog._tcp). "
                                    + "Ohne Empfänger bleiben die letzten 500 Zeilen im Speicher.",
                                value: receiver ? "Gefunden" : "Nur Speicher")
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
                    if !cleared { confirmClear = true }
                }
                .settingsUnavailable(cleared)
            }
        }
        .task {
            while !Task.isCancelled {
                receiver = RemoteLog.shared.hasReceiver
                try? await Task.sleep(for: .seconds(2))
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
