import SwiftUI
import PlayerCore

/// Kategorie „Wiedergabe“: Sprache, Tonspur, Untertitel, nächste Folge, Fortschrittsquelle.
struct PlaybackSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Section("Wiedergabe") {
            Picker("Sprache der App", selection: model.binding(\.language)) {
                Text("Deutsch").tag(AppLanguage.de); Text("English").tag(AppLanguage.en)
            }
            Text("Tonspur-Vorrang: " + model.profile.audioPriority.map { $0 == "orig" ? "Original" : $0.uppercased() }.joined(separator: " → "))
            Toggle("Untertitel automatisch an", isOn: model.binding(\.subtitlesEnabled))
            Toggle("Nächste Folge automatisch starten", isOn: model.binding(\.autoplayNext))
            Picker("Fortschritt & Gesehen", selection: model.binding(\.progressSource)) {
                Text("Lokal").tag(ProgressSource.local); Text("Trakt").tag(ProgressSource.trakt); Text("Simkl").tag(ProgressSource.simkl)
            }
        }
    }
}
