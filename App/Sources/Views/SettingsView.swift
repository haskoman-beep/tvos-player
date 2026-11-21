import SwiftUI
import PlayerCore

/// Einstellungen des aktiven Profils (jedes Profil ist komplett eigenständig).
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var addonURL = ""
    @State private var tmdbKey = ""
    @State private var nuvioURL = ""
    @State private var newProfile = ""
    @State private var busy = false

    var body: some View {
        List {
            Section {
                NavigationLink("📱 Am Handy eingeben (QR-Code)") { PhoneInputView() }
            }
            Section("Profil: \(model.profile.name)") {
                ForEach(model.stored.profiles) { p in
                    Button { model.switchProfile(p.id) } label: {
                        HStack { Text(p.name); Spacer(); if p.id == model.profile.id { Image(systemName: "checkmark") } }
                    }
                }
                TextField("Neues Profil (Name)", text: $newProfile)
                Button("Profil anlegen") { model.addProfile(name: newProfile); newProfile = "" }.disabled(newProfile.isEmpty)
                if model.hasMultipleProfiles {
                    Button("Dieses Profil löschen", role: .destructive) { model.deleteProfile(model.profile.id) }
                }
            }

            Section("Addons") {
                ForEach(model.profile.addons) { a in
                    Button("\(a.manifest.name) \(a.manifest.version) – entfernen", role: .destructive) {
                        model.update { $0.addons.removeAll { $0.manifestURL == a.manifestURL } }
                    }
                }
                TextField("Manifest-URL (z. B. AIOStreams)", text: $addonURL)
                Button(busy ? "Lädt …" : "Addon hinzufügen") {
                    busy = true
                    Task { await model.installAddon(addonURL); addonURL = ""; busy = false }
                }
                .disabled(addonURL.isEmpty || busy)
            }

            Section("Dienste") {
                SecureField(model.profile.apiKeys["tmdb"].map { _ in "TMDB-Key (gespeichert)" } ?? "TMDB-API-Key", text: $tmdbKey)
                Button("TMDB-Key speichern") { model.update { $0.apiKeys["tmdb"] = tmdbKey }; tmdbKey = "" }.disabled(tmdbKey.isEmpty)
                Text("Trakt, Simkl, TVDB und MDBList folgen (P4/P5).").foregroundStyle(.secondary)
            }

            Section("Collections") {
                Text("\(model.profile.collections.count) Collections · \(model.profile.home.rows.count) Reihen auf der Startseite")
                TextField("Nuvio-Export-URL (JSON)", text: $nuvioURL)
                Button("Importieren") { Task { await model.importNuvio(from: nuvioURL); nuvioURL = "" } }.disabled(nuvioURL.isEmpty)
            }

            Section("Wiedergabe") {
                Picker("Sprache der App", selection: binding(\.language)) {
                    Text("Deutsch").tag(AppLanguage.de); Text("English").tag(AppLanguage.en)
                }
                Text("Tonspur-Vorrang: " + model.profile.audioPriority.map { $0 == "orig" ? "Original" : $0.uppercased() }.joined(separator: " → "))
                Toggle("Untertitel automatisch an", isOn: binding(\.subtitlesEnabled))
                Picker("Fortschritt & Gesehen", selection: binding(\.progressSource)) {
                    Text("Lokal").tag(ProgressSource.local); Text("Trakt").tag(ProgressSource.trakt); Text("Simkl").tag(ProgressSource.simkl)
                }
            }
        }
        .navigationTitle("Einstellungen")
    }

    private func binding<T>(_ kp: WritableKeyPath<Profile, T>) -> Binding<T> {
        Binding(get: { model.profile[keyPath: kp] }, set: { v in model.update { $0[keyPath: kp] = v } })
    }
}
