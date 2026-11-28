import SwiftUI
import PlayerCore

/// Nuvio account, T10: one row for the Nuvio settings screen. It opens the import page, which loads the preview of
/// addons and collections of the chosen account profile. Place it with `NuvioImportRow()` (needs `AppModel` in the
/// environment, like every settings page).
struct NuvioImportRow: View {
    var body: some View {
        SettingsLinkRow(symbol: "square.and.arrow.down", tint: SettingsCategory.addons.tint,
                        title: "Vom Nuvio-Konto laden",
                        detail: "Addons und Collections mit Vorschau übernehmen") {
            NuvioImportPage()
        }
    }
}

/// Preview and apply. Addons show name and host only; the address never appears (it may carry a key).
struct NuvioImportPage: View {
    @Environment(AppModel.self) var model
    @ObservedObject private var ui = NuvioImportStore.shared

    private var tint: Color { SettingsCategory.addons.tint }

    var body: some View {
        SettingsSubpage(title: "Vom Nuvio-Konto laden",
                        summary: "Nur hinzufügen: Nichts wird umsortiert und nichts wird ins Konto zurückgeschrieben.") {
            switch ui.phase {
            case .idle, .loading:
                SettingsSection { SettingsInfoRow(symbol: "hourglass", tint: tint, title: "Lädt …") }
            case .signedOut:
                SettingsSection {
                    SettingsInfoRow(symbol: Theme.Tone.warn.symbol, tint: Theme.Tone.warn.color, title: "Nicht verbunden",
                                    detail: "Anmelden am Handy mit E-Mail und Passwort.", detailAlwaysVisible: true)
                }
            case .noProfile:
                SettingsSection {
                    SettingsInfoRow(symbol: Theme.Tone.warn.symbol, tint: Theme.Tone.warn.color,
                                    title: AppModel.NuvioImportText.noProfile(model.profile.name), detailAlwaysVisible: true)
                }
            case .failed(let text):
                SettingsSection {
                    SettingsInfoRow(symbol: Theme.Tone.error.symbol, tint: Theme.Tone.error.color, title: text)
                    reloadRow
                }
            case .ready, .applying:
                if let p = ui.preview { previewSections(p) }
            case .done(let text):
                SettingsSection {
                    SettingsInfoRow(symbol: "checkmark.circle", tint: tint, title: "Übernommen", detail: text,
                                    detailAlwaysVisible: true)
                    reloadRow
                }
            }
        }
        .task { if !ui.busy { await model.nuvioImportPreview() } }   // every opening loads a fresh preview
    }

    private var reloadRow: some View {
        SettingsRow(symbol: "arrow.clockwise", tint: tint, title: "Erneut laden", reserveDetailSpace: false) {
            Task { await model.nuvioImportPreview() }
        }
        .settingsUnavailable(ui.busy)
    }

    @ViewBuilder
    private func previewSections(_ p: NuvioImportPreview) -> some View {
        SettingsSection("Addons aus Nuvio") {
            if p.addons.isEmpty {
                SettingsInfoRow(symbol: "puzzlepiece.extension", tint: tint, title: "Im Nuvio-Profil sind keine Addons.")
            }
            ForEach(p.addons) { a in addonRow(a) }
        }
        if p.disabledSkipped > 0 {
            SettingsFootnote(p.disabledSkipped == 1 ? "1 deaktiviertes Addon am Konto wird nicht übernommen."
                             : "\(p.disabledSkipped) deaktivierte Addons am Konto werden nicht übernommen.")
        }
        if !p.removedOnAccount.isEmpty {
            SettingsSection("Am Konto entfernt") {
                ForEach(p.removedOnAccount) { a in
                    SettingsToggleRow(symbol: "trash", tint: Theme.Tone.error.color, title: a.name,
                                      detail: a.host + " · Hier entfernen?", reserveDetailSpace: false,
                                      isOn: binding(a.instanceID, in: \.remove))
                }
            }
            SettingsFootnote("Früher vom Konto übernommen. Nur ausgewählte Addons werden hier entfernt.")
        }
        if !p.disabledOnAccount.isEmpty {
            SettingsSection("Am Konto deaktiviert") {
                ForEach(p.disabledOnAccount) { a in
                    SettingsInfoRow(symbol: "pause.circle", tint: tint, title: a.name, detail: a.host + " · Bleibt installiert")
                }
            }
        }
        SettingsSection("Collections aus Nuvio") {
            if p.collections.isEmpty {
                SettingsInfoRow(symbol: "square.stack", tint: tint, title: "Im Nuvio-Profil sind keine Collections.")
            } else {
                if p.collectionsToImport {
                    SettingsToggleRow(symbol: "square.stack", tint: tint, title: "Collections übernehmen",
                                      reserveDetailSpace: false, isOn: $ui.takeCollections)
                }
                ForEach(p.collections) { c in
                    SettingsInfoRow(symbol: "folder", tint: tint, title: c.title,
                                    detail: Self.collectionDetail(c), detailAlwaysVisible: c.status == .matchedByTitle)
                }
            }
        }
        SettingsSection {
            if p.nothingToDo, ui.install.isEmpty, ui.remove.isEmpty {
                SettingsInfoRow(symbol: "checkmark.circle", tint: tint, title: "Alles schon übernommen",
                                detail: "Am Konto hat sich nichts geändert.")
            } else {
                SettingsRow(symbol: "square.and.arrow.down", tint: tint,
                            title: ui.phase == .applying ? "Übernimmt …" : "Übernehmen", reserveDetailSpace: false) {
                    Task { await model.nuvioImportApply() }
                }
                .settingsUnavailable(ui.busy)
            }
            reloadRow
        }
    }

    @ViewBuilder
    private func addonRow(_ a: NuvioImportPreview.AccountAddon) -> some View {
        if a.installable {
            SettingsToggleRow(symbol: "puzzlepiece.extension", tint: tint, title: a.name, detail: Self.addonDetail(a),
                              detailAlwaysVisible: a.sharesManifestIDWith != nil, reserveDetailSpace: false,
                              isOn: binding(a.instanceID, in: \.install))
        } else {
            SettingsInfoRow(symbol: a.status == .installed ? "checkmark.circle" : Theme.Tone.warn.symbol,
                            tint: a.status == .installed ? tint : Theme.Tone.warn.color,
                            title: a.name, detail: Self.addonDetail(a),
                            detailAlwaysVisible: a.status != .installed)
        }
    }

    private func binding(_ id: String, in key: ReferenceWritableKeyPath<NuvioImportStore, Set<String>>) -> Binding<Bool> {
        Binding(get: { ui[keyPath: key].contains(id) }, set: { on in
            if on { ui[keyPath: key].insert(id) } else { ui[keyPath: key].remove(id) }
        })
    }

    static func addonDetail(_ a: NuvioImportPreview.AccountAddon) -> String {
        var parts = [a.host]
        switch a.status {
        case .new: break
        case .installed: parts.append("Schon installiert")
        case .otherConfiguration(let localName): parts.append("Andere Konfiguration als „\(localName)“ · zusätzlich installierbar")
        case .invalidAddress: parts.append("Keine Addon-Adresse")
        case .manifestUnavailable: parts.append("Manifest nicht geladen · später erneut laden")
        }
        if let other = a.sharesManifestIDWith { parts.append("Gleiche Addon-ID wie „\(other)“: Collections nutzen „\(other)“") }
        return parts.joined(separator: " · ")
    }

    static func collectionDetail(_ c: NuvioImportPreview.AccountCollection) -> String {
        let folders = c.folders == 1 ? "1 Ordner" : "\(c.folders) Ordner"
        switch c.status {
        case .new: return folders + " · Neu"
        case .update: return folders + " · Wird aktualisiert"
        case .unchanged: return folders + " · Unverändert"
        case .matchedByTitle: return folders + " · Über den Titel einer vorhandenen Collection zugeordnet (früherer Import), keine Kopie"
        }
    }
}
