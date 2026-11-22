import SwiftUI
import PlayerCore

/// Einstellungen › Startseite › Fusion-Kit (Plan §2.2, E10): nur noch an/aus und „Neu laden“.
/// Die Kit-Reihen wählt man im Hinzufügen-Browser (Quelle „Fusion-Kit“, Welle F-b2); gewählte Reihen hängen unten
/// an der Startseite und lassen sich im Verwalter wie jede Reihe ordnen oder ausblenden.
/// Kit-Dateien kommen zur Laufzeit von GitHub (kit.betterer.cc).
struct FusionKitSettingsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var kit = FusionKitStore.shared
    @State private var removeCandidate: FusionKitSource?

    var body: some View {
        SettingsToggleRow(symbol: "sparkles", tint: Theme.CategoryTint.home.color, title: "Fusion-Kit",
                          detail: "Kit-Reihen auf der Startseite; Auswahl unter „Reihen & Collections“",
                          reserveDetailSpace: false,
                          isOn: Binding(get: { kit.settings.enabled }, set: { on in
                              kit.setEnabled(on)
                              RemoteLog.info("kit", on ? "Fusion-Kit an" : "Fusion-Kit aus")
                          }))
            .task { await kit.refresh() }   // Auswahl steht im Browser; der lädt den ganzen Katalog (Review M12)
            .confirmationDialog(removeCandidate.map { "„\($0.title)“ entfernen?" } ?? "",
                                isPresented: Binding(get: { removeCandidate != nil }, set: { if !$0 { removeCandidate = nil } }),
                                titleVisibility: .visible, presenting: removeCandidate) { src in
                // „Behalten“ zuerst: Fokus startet dort (§2.4, Review M1).
                Button("Behalten", role: .cancel) {}
                Button("Entfernen", role: .destructive) {
                    kit.removeSource(src.id)
                    RemoteLog.info("kit", "Eigene Kit-Datei entfernt: \(src.title)")
                }
            } message: { _ in
                Text("Die Kit-Datei wird nicht mehr geladen. Über „Collections importieren“ lässt sie sich wieder einfügen.")
            }
        if kit.settings.enabled {
            SettingsRow(symbol: "arrow.clockwise", tint: Theme.CategoryTint.home.color,
                        title: busy ? "Lädt …" : "Neu laden",
                        detail: kit.listingError.map { "Kit-Katalog nicht erreichbar: \($0)" },
                        detailAlwaysVisible: kit.listingError != nil, reserveDetailSpace: false) {
                Task { await kit.refresh(force: true, all: true) }
            }
            .disabled(busy)
            if !model.hasTraktID {
                // E11: ein Hinweis mit Weg zum Handy statt Text ohne Ausweg.
                NavigationLink { PhoneInputView(section: .keys) } label: {
                    SettingsRowLabel(symbol: Theme.Tone.warn.symbol, tint: Theme.Tone.warn.color,
                                     title: "Trakt Client ID fehlt",
                                     detail: "Ohne sie fehlen Trakt-Reihen und -Kacheln · Am Handy eintragen",
                                     accessory: .chevron, detailAlwaysVisible: true, reserveDetailSpace: false)
                }
                .buttonStyle(ThemeRowButtonStyle())
                .settingsRowAccessibility(title: "Trakt Client ID fehlt", detail: "Am Handy eintragen", accessory: .chevron)
            }
            // Eigene Kit-Dateien (per Handy eingefügt, nicht im Katalog) lassen sich hier wieder entfernen.
            ForEach(kit.sources.filter { !kit.isListed($0.id) }) { src in
                SettingsRow(symbol: "trash", tint: Theme.Tone.error.color, title: "„\(src.title)“ entfernen",
                            detail: "Eigene Kit-Datei", reserveDetailSpace: false) { removeCandidate = src }
            }
        }
    }

    private var busy: Bool { kit.listingLoading || !kit.loading.isEmpty }
}
