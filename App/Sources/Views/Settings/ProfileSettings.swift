import SwiftUI
import PlayerCore

/// Kategorie „Profil“: wechseln, anlegen, löschen.
struct ProfileSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var newProfile = ""

    var body: some View {
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
    }
}
