import SwiftUI
import PlayerCore

/// Kategorie „Addons“: installierte Addons entfernen, neue per Manifest-URL hinzufügen.
struct AddonSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var addonURL = ""
    @State private var busy = false

    var body: some View {
        Section("Addons") {
            ForEach(model.profile.addons) { a in
                Button("\(a.manifest.name) \(a.manifest.version) – entfernen", role: .destructive) {
                    model.update { $0.addons.removeAll { $0.manifestURL == a.manifestURL } }
                    model.clearCatalogCache()   // Reihen des Addons nicht aus dem Plattencache zurückholen
                }
            }
            TextField("Manifest-URL (z. B. AIOStreams)", text: $addonURL)
            Button(busy ? "Lädt …" : "Addon hinzufügen") {
                busy = true
                Task { await model.installAddon(addonURL); addonURL = ""; busy = false }
            }
            .disabled(addonURL.isEmpty || busy)
            AddonTimeoutPicker()   // Welle C-a
        }
    }
}
