import SwiftUI
import PlayerCore

/// Kategorie „Über“: Version, Addons, Log-Hinweis.
struct AboutSettings: View {
    @EnvironmentObject var model: AppModel

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        Section("Über") {
            HStack { Text("Version"); Spacer(); Text(version).foregroundStyle(.secondary) }
            HStack { Text("Addons"); Spacer(); Text("\(model.profile.addons.count)").foregroundStyle(.secondary) }
            HStack { Text("Profile"); Spacer(); Text("\(model.stored.profiles.count)").foregroundStyle(.secondary) }
            Text("Das Ereignis-Log geht automatisch an ein Log-Programm im Heimnetz (Bonjour `_playerlog._tcp`). Ohne Empfänger bleiben die letzten 500 Zeilen im Speicher.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
