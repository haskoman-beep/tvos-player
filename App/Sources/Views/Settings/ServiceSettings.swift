import SwiftUI
import PlayerCore

/// Kategorie „Dienste & Schlüssel“: Handy-Eingabe, TMDB-Key, Trakt/Simkl.
struct ServiceSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var tmdbKey = ""

    var body: some View {
        Section {
            NavigationLink("📱 Am Handy eingeben (QR-Code)") { PhoneInputView() }
        }
        Section("Dienste") {
            SecureField(model.profile.apiKeys["tmdb"].map { _ in "TMDB-Key (gespeichert)" } ?? "TMDB-API-Key", text: $tmdbKey)
            Button("TMDB-Key speichern") { model.update { $0.apiKeys["tmdb"] = tmdbKey }; tmdbKey = "" }.disabled(tmdbKey.isEmpty)
            ForEach(AppModel.syncServices, id: \.self) { s in
                let name = s == "trakt" ? "Trakt" : "Simkl"
                if !model.hasClient(s) {
                    Text("\(name): Client ID über die Handy-Seite eintragen").foregroundStyle(.secondary)
                } else if model.isConnected(s) {
                    Button("\(name) verbunden ✓ – abmelden", role: .destructive) { model.disconnect(s) }
                } else {
                    NavigationLink("Mit \(name) verbinden") { SyncLoginView(service: s) }
                }
            }
        }
    }
}
