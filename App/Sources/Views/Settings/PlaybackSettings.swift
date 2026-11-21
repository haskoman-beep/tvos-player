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
            Picker("Untertitel", selection: model.binding(\.subtitleMode)) {
                Text("Aus").tag(SubtitleMode.off)
                Text("Nur erzwungene").tag(SubtitleMode.forcedOnly)
                Text("Immer").tag(SubtitleMode.always)
            }
            Toggle("Nächste Folge automatisch starten", isOn: model.binding(\.autoplayNext))
            Toggle("Quellen vorladen", isOn: model.binding(\.appearance.prefetchStreams))
            DiskCacheSettingsRows()
            Picker("Fortschritt & Gesehen", selection: model.binding(\.progressSource)) {
                Text("Lokal").tag(ProgressSource.local); Text("Trakt").tag(ProgressSource.trakt); Text("Simkl").tag(ProgressSource.simkl)
            }
        }
    }
}

/// „Plattencache“ an/aus und Größe (Welle B-d). Aus = Wiedergabe wie ohne Cache.
private struct DiskCacheSettingsRows: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Toggle("Plattencache (Film zwischenspeichern)", isOn: model.binding(\.diskCache.enabled))
        if model.profile.diskCache.enabled {
            Picker("Plattencache höchstens", selection: model.binding(\.diskCache.limitGB)) {
                ForEach(DiskCacheSettings.sizeChoices, id: \.self) { Text("\($0) GB").tag($0) }
            }
            Text("Speichert den laufenden Film auf dem Gerät: Zurückspulen und kurze Netzaussetzer ohne Neuladen. "
                 + "Lässt immer mindestens 2 GB frei; wird beim Schließen des Players gelöscht. Nicht für HLS-Quellen.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
