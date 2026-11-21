import SwiftUI
import PlayerCore

/// Kategorie „Über“: Version, Build, Addons, Log-Hinweis, darunter „App aktualisieren“ und die Lizenzen.
struct AboutSettings: View {
    @EnvironmentObject var model: AppModel

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }

    var body: some View {
        Section("Über") {
            HStack { Text("Version"); Spacer(); Text(version).foregroundStyle(.secondary) }
            HStack { Text("Build"); Spacer(); Text(AppUpdater.shared.current.buildLabel).foregroundStyle(.secondary) }
            HStack { Text("Addons"); Spacer(); Text("\(model.profile.addons.count)").foregroundStyle(.secondary) }
            HStack { Text("Profile"); Spacer(); Text("\(model.stored.profiles.count)").foregroundStyle(.secondary) }
            Text("Das Ereignis-Log geht automatisch an ein Log-Programm im Heimnetz (Bonjour `_playerlog._tcp`). Ohne Empfänger bleiben die letzten 500 Zeilen im Speicher.")
                .font(.caption).foregroundStyle(.secondary)
        }
        UpdateSettings()
        Section("Danksagungen / Lizenzen") {
            // Zeilen als Knöpfe ohne Aktion: so erreicht der Fokus sie und die Liste scrollt bis ans Ende.
            ForEach(Self.credits, id: \.name) { c in
                Button {} label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.name)
                        Text(c.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Die vollständigen Lizenztexte stehen in THIRD_PARTY_NOTICES.md im Quellcode-Repository; jedes Release verweist darauf.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Mitgelieferte Fremdkomponenten (Stand Engine 7.71.2); Volltexte in THIRD_PARTY_NOTICES.md.
    private struct Credit { let name: String; let detail: String }
    private static let credits: [Credit] = [
        Credit(name: "Player (diese App)", detail: "App: MIT · die Komponenten unten behalten ihre eigenen Lizenzen"),
        Credit(name: "AetherEngine 7.71.2", detail: "© 2026 Vincent Herbst · LGPL-3.0 mit App-Store-/DRM-Ausnahme · github.com/superuser404notfound/AetherEngine"),
        Credit(name: "FFmpeg n8.1.3 (FFmpegBuild 3.16)", detail: "© die FFmpeg-Entwickler · LGPL-2.1 oder neuer, als austauschbare dynamische Frameworks · Quelle: github.com/superuser404notfound/FFmpegBuild"),
        Credit(name: "libzvbi", detail: "LGPL-2.0 oder neuer (unter LGPL-2.1), ure.c MIT"),
        Credit(name: "dav1d", detail: "© 2018-2019 VideoLAN und die dav1d-Autoren · BSD-2-Clause"),
        Credit(name: "zimg", detail: "WTFPL"),
        Credit(name: "libdovi (dovi_tool)", detail: "© quietvoid und Mitwirkende · MIT"),
        Credit(name: "Anime4K", detail: "© 2019-2021 bloc97 · MIT"),
    ]
}
