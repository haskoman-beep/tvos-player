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
    /// F-B-3: phone page opened from the Trakt row; outside the row so saving the ID does not close it.
    @State private var phoneOpen = false

    var body: some View {
        SettingsToggleRow(symbol: "sparkles", tint: Theme.CategoryTint.home.color, title: "Fusion-Kit",
                          detail: "Kit-Reihen auf der Startseite; Auswahl unter „Reihen & Collections“",
                          reserveDetailSpace: false,
                          isOn: Binding(get: { kit.settings.enabled }, set: { on in
                              kit.setEnabled(on)
                              RemoteLog.info("kit", on ? "Fusion-Kit an" : "Fusion-Kit aus")
                          }))
            .task { await kit.refresh() }   // Auswahl steht im Browser; der lädt den ganzen Katalog (Review M12)
            .settingsConfirmation(item: $removeCandidate, title: { "„\($0.title)“ entfernen?" },
                                  message: { _ in "Die Kit-Datei wird nicht mehr geladen. Über „Collections importieren“ lässt sie sich wieder einfügen." },
                                  verb: "Entfernen") { src in
                kit.removeSource(src.id)
                RemoteLog.info("kit", "Eigene Kit-Datei entfernt: \(src.title)")
            }
        if kit.settings.enabled {
            SettingsRow(symbol: "arrow.clockwise", tint: Theme.CategoryTint.home.color,
                        title: busy ? "Lädt …" : "Neu laden",
                        detail: kit.listingError.map { "Kit-Katalog nicht erreichbar: \($0)" },
                        detailAlwaysVisible: kit.listingError != nil, reserveDetailSpace: false) {
                guard !busy else { return }
                Task { await kit.refresh(force: true, all: true) }
            }
            .settingsUnavailable(busy)   // fokussierbar bleiben statt .disabled (F-a M2)
            // F-B-3: the row stays in the tree once the ID is saved (the open phone page keeps its link); only the
            // text changes. E11: a hint with a way to the phone instead of text without a way out.
            let missing = !model.hasTraktID
            SettingsRow(symbol: missing ? Theme.Tone.warn.symbol : "key", tint: missing ? Theme.Tone.warn.color : Theme.CategoryTint.home.color,
                        title: missing ? "Trakt Client ID fehlt" : "Trakt Client ID",
                        detail: missing ? "Ohne sie fehlen Trakt-Reihen und -Kacheln · Am Handy eintragen" : "Eingetragen · am Handy ändern",
                        accessory: .chevron, detailAlwaysVisible: missing, reserveDetailSpace: false) { phoneOpen = true }
                .navigationDestination(isPresented: $phoneOpen) { PhoneInputView(section: .keys) }
        }
        // Eigene Kit-Dateien (per Handy eingefügt, nicht im Katalog) lassen sich hier wieder entfernen –
        // auch bei ausgeschaltetem Kit (F-b2-Review M5).
        ForEach(kit.sources.filter { !kit.isListed($0.id) }) { src in
            SettingsRow(symbol: "trash", tint: Theme.Tone.error.color, title: "„\(src.title)“ entfernen",
                        detail: "Eigene Kit-Datei", reserveDetailSpace: false) { removeCandidate = src }
        }
    }

    private var busy: Bool { kit.listingLoading || !kit.loading.isEmpty }
}
