import SwiftUI

/// Welle C-b (#8): Schalter für den Hänger-Wächter (Gerät, nicht Profil).
struct DiagnosticsSettings: View {
    @AppStorage(MainThreadWatchdog.settingKey) private var hitchLog = true

    var body: some View {
        Section("Diagnose") {
            Toggle("Ruckler protokollieren", isOn: $hitchLog)
                .onChange(of: hitchLog) { MainThreadWatchdog.apply() }
            Text("Schreibt ins Ereignis-Log, wenn die Oberfläche länger als 250 ms hängt (mit letzter Aktion und Speicherverbrauch).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
