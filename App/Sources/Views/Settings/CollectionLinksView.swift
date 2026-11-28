import SwiftUI
import PlayerCore

/// Wave F-o round 2: Settings › Startseite › "Collection-Link hinzufügen". A link to a widget export, preview pack
/// or collection export is fetched, detected and imported; stored links can be fetched again ("Aktualisieren").
struct CollectionLinksPage: View {
    @Environment(AppModel.self) var model
    @ObservedObject private var store = CollectionLinkStore.shared
    @State private var link = ""

    private let tint = Theme.CategoryTint.home.color
    private var trimmed: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        SettingsSubpage(title: "Collection-Links",
                        summary: store.links.isEmpty ? "Noch kein Link" : (store.links.count == 1 ? "1 Import" : "\(store.links.count) Importe")) {
            SettingsSection("Link hinzufügen") {
                TextField("https://… (Widget-Export, Preview Pack oder Collection-Export)", text: $link)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { add() }
                SettingsRow(symbol: "square.and.arrow.down", tint: tint, title: store.busy ? "Wird geladen …" : "Importieren",
                            detail: "Lädt den Link, erkennt das Format und übernimmt Reihen, Kacheln, Videos und Ton.",
                            reserveDetailSpace: false) { add() }
                    .settingsUnavailable(trimmed.isEmpty || store.busy)
                if let e = model.lastError, e.hasPrefix("Import") {
                    SettingsInfoRow(symbol: "exclamationmark.triangle", tint: Theme.Tone.error.color, title: "Fehler",
                                    detail: e, detailAlwaysVisible: true)
                } else if let n = model.notice, n.hasPrefix("Import") || n.hasPrefix("Preview Pack") {
                    SettingsInfoRow(symbol: "checkmark.circle", tint: tint, title: "Ergebnis", detail: n, detailAlwaysVisible: true)
                }
            }
            if !store.links.isEmpty {
                SettingsSection("Importe") {
                    ForEach(store.links) { l in
                        let account = NuvioAccountImport.isAccountLink(l.url)   // T10: pseudo-link, no host
                        SettingsRow(symbol: account ? "person.crop.circle" : (l.url == nil ? "doc.on.clipboard" : "link"), tint: tint,
                                    title: account ? "Nuvio-Konto" : (l.url.flatMap { URL(string: $0)?.host } ?? "Eingefügter Code"),
                                    detail: "\(l.format) · \(l.summary)",
                                    accessory: .value(l.at.formatted(date: .numeric, time: .shortened)),
                                    reserveDetailSpace: false) {
                            guard l.url != nil else { return }
                            Task { await store.refresh(l.id, model: model) }
                        }
                        .contextMenu {
                            if l.url != nil {
                                Button("Aktualisieren") { Task { await store.refresh(l.id, model: model) } }
                            }
                            Button("Entfernen", role: .destructive) { store.remove(l.id) }
                        }
                    }
                    SettingsRow(symbol: "arrow.clockwise", tint: tint, title: "Alle aktualisieren",
                                detail: "Holt alle gespeicherten Links neu. OK auf einem Link aktualisiert nur diesen, langes Drücken entfernt ihn.",
                                reserveDetailSpace: false) { Task { await store.refreshAll(model: model) } }
                        .settingsUnavailable(store.busy || !store.links.contains { $0.url != nil })
                }
            }
        }
        .onAppear { store.ensure(model) }
    }

    private func add() {
        guard !trimmed.isEmpty, !store.busy else { return }
        let u = trimmed
        Task {
            await store.importLink(u, model: model)
            if model.lastError == nil { link = "" }
        }
    }
}
