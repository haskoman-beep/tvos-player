import SwiftUI
import PlayerCore

/// Wave S: „System“ sections Diagnose (Welle C-b, Gerät statt Profil; Log-Empfänger) and Zwischenspeicher
/// (Katalog-Zwischenspeicher leeren, mit Rückfrage, E6). Was the subpage „System › Erweitert“, which is dissolved:
/// Zeitgrenze je Addon → Addons, Dolby Vision fest/FEL → Bild & Ton, Icon-Satz only under Aussehen › Plaketten.
struct SystemMaintenanceRows: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(MainThreadWatchdog.settingKey) private var hitchLog = true
    @State private var confirmClear = false
    @State private var cleared = false
    /// Review F-a M4: RemoteLog ist kein ObservableObject; die Seite fragt den Empfänger alle 2 s neu ab.
    @State private var receiver = RemoteLog.shared.hasReceiver

    private let tint = SettingsCategory.system.tint

    var body: some View {
        // A VStack, not a Group: modifiers on a Group would run once per section (two polls, two covers).
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SettingsSection("Diagnose") {
                SettingsToggleRow(symbol: "waveform.path.ecg", tint: tint, title: "Ruckler protokollieren",
                                  detail: "Schreibt ins Ereignis-Log, wenn die Oberfläche länger als 250 ms hängt (mit letzter Aktion und Speicherverbrauch).",
                                  reserveDetailSpace: false, isOn: $hitchLog)
                    .onChange(of: hitchLog) { MainThreadWatchdog.apply() }
                SettingsInfoRow(symbol: "antenna.radiowaves.left.and.right", tint: tint, title: "Log-Empfänger",
                                detail: "Das Ereignis-Log geht automatisch an ein Log-Programm im Heimnetz (Bonjour, Dienst _playerlog._tcp). "
                                    + "Ohne Empfänger bleiben die letzten 500 Zeilen im Speicher.",
                                value: receiver ? "Gefunden" : "Nur Speicher")
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
