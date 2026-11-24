import SwiftUI
import PlayerCore

/// Kategorie „Profil & Konten“ (§2.2): Statuskarte, Profile wechseln/anlegen/löschen, Konten, Schlüssel (wave S:
/// TMDB, MDBList and TorBox), Fortschritt.
struct ProfileSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var naming = false
    @State private var newName = ""
    @State private var confirmDelete = false

    private let tint = SettingsCategory.profile.tint

    var body: some View {
        let p = model.profile
        CategoryPage(.profile, summary: SettingsSummary.profile(name: p.name, trakt: model.isConnected("trakt"),
                                                               simkl: model.isConnected("simkl"))) {
            StatusCard(leading: .initial(p.name, tint), title: p.name,
                       subtitle: SettingsSummary.profiles(model.stored.profiles.count) + " auf diesem Gerät",
                       metrics: SettingsSummary.profileMetrics(addons: p.addons.count, rows: p.home.rows.count,
                                                               progress: p.progressSource).map { StatusCard.Metric(text: $0) })
            SettingsSection("Profile") {
                ForEach(model.stored.profiles) { q in
                    let active = q.id == p.id
                    SettingsRow(symbol: "person", tint: tint, title: q.name,
                                detail: active ? "Aktives Profil" : "OK wechselt zu diesem Profil.",
                                accessory: .value(active ? "Aktiv" : ""), reserveDetailSpace: false) {
                        guard !active else { return }
                        RemoteLog.info("einstellung", "Profil gewechselt")
                        model.switchProfile(q.id)
                    }
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
                SettingsRow(symbol: "plus", tint: tint, title: "Neues Profil …",
                            detail: "Eigene Addons, eigene Startseite, eigener Fortschritt.", reserveDetailSpace: false) {
                    newName = ""
                    naming = true
                }
                // F-B-9: the row stays after deleting down to one profile (focus keeps its view); then only dimmed.
                SettingsRow(symbol: "trash", tint: Theme.Tone.error.color, title: "Profil „\(p.name)“ löschen …",
                            detail: model.hasMultipleProfiles ? nil : "Das einzige Profil lässt sich nicht löschen.",
                            reserveDetailSpace: false) {
                    guard model.hasMultipleProfiles else { return }
                    confirmDelete = true
                }
                .settingsUnavailable(!model.hasMultipleProfiles)
            }
            // Review S M3: the page label says "this profile", the profile list itself is device-wide.
            SettingsFootnote("Die Profilliste gilt für das ganze Gerät.")
            AccountSettingsRows()
            SettingsSection("Fortschritt") {
                SettingsChoiceRow(symbol: "checkmark.circle", tint: tint, title: "Fortschritt & Gesehen",
                                  detail: "Woher Weiterschauen und „gesehen“ kommen.",
                                  options: ProgressSource.allCases, selection: model.binding(\.progressSource),
                                  alwaysList: true,   // Review F-a M6: kein Zwischenwert (Trakt) beim Durchschalten
                                  label: SettingsSummary.progressName)
            }
        }
        .sheet(isPresented: $naming) {
            NewProfileSheet(name: $newName) { name in
                model.addProfile(name: name)
                RemoteLog.info("einstellung", "Profil angelegt")
            }
        }
        .settingsConfirmation("Profil „\(p.name)“ löschen?", isPresented: $confirmDelete,
                              message: "Addons, Collections und Fortschritt dieses Profils gehen verloren.",
                              verb: "Profil löschen") {
            RemoteLog.info("einstellung", "Profil gelöscht")
            model.deleteProfile(p.id)
        }
    }
}

/// Blatt „Neues Profil“: die einzige Texteingabe am Fernseher (§2.2).
private struct NewProfileSheet: View {
    @Binding var name: String
    let create: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Neues Profil").textRole(.pageTitle)
            Text("Name des Profils, z. B. „Kinder“. Das Profil startet leer: Addons und Startseite richtest du danach ein.")
                .textRole(.rowDetail)
                .multilineTextAlignment(.leading)
            TextField("Name", text: $name)
                .onSubmit { submit() }
            HStack(spacing: Theme.Space.m) {
                Button("Profil anlegen") { submit() }
                    .settingsUnavailable(trimmed.isEmpty)
                Button("Abbrechen", role: .cancel) { dismiss() }
            }
        }
        .frame(maxWidth: 900, alignment: .leading)
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .settingsSurface()   // Review F-a M9: gleicher Grund wie die Einstellungen
    }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        create(trimmed)
        dismiss()
    }
}
