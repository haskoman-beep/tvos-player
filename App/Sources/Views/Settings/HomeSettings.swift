import SwiftUI
import PlayerCore

/// Kategorie „Startseite“: Collections importieren, Überblick über die Reihen.
struct HomeSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var nuvioURL = ""

    var body: some View {
        Section("Collections") {
            Text("\(model.profile.collections.count) Collections · \(model.profile.home.rows.count) Reihen auf der Startseite")
            TextField("Nuvio-Export-URL (JSON)", text: $nuvioURL)
            Button("Importieren") { Task { await model.importNuvio(from: nuvioURL); nuvioURL = "" } }.disabled(nuvioURL.isEmpty)
            Text("Reihen ordnen: auf der Startseite „Startseite bearbeiten“ wählen oder eine Kachel lange drücken.")
                .foregroundStyle(.secondary)
        }
        FusionKitSettingsView()
    }
}
