import SwiftUI
import PlayerCore

/// Welle C-d: Spoilerschutz für Folgenbilder (Aussehen › Karten).
struct SpoilerSettingsRow: View {
    @Environment(AppModel.self) var model

    var body: some View {
        SettingsToggleRow(symbol: "eye.slash", tint: SettingsCategory.appearance.tint,
                          title: "Bilder ungesehener Folgen weichzeichnen",
                          detail: "Schützt vor Spoilern in Folgenbildern.",
                          reserveDetailSpace: false, isOn: model.binding(\.sources.blurUnwatchedStills))
    }
}

/// Welle C-d/F-a: eigener Bewertungs-Icon-Satz (JSON, wird nur zur Laufzeit geladen).
/// E7: Die Adresse kommt nur noch von der Handy-Seite (Feld „icon_set“, Abschnitt System); hier Status und
/// „Eingebaute Plaketten verwenden“. Erreichbar über Aussehen › Plaketten (wave S: only there).
struct RatingIconSettingsPage: View {
    @Environment(AppModel.self) var model
    @ObservedObject private var store = RatingIconStore.shared

    private let tint = SettingsCategory.appearance.tint

    /// Wert der Zeile: „Eingebaut“ oder Ladestand des eigenen Satzes.
    static func value(_ url: String?, status: String?) -> String {
        url == nil ? "Eingebaut" : (status ?? "lädt …")
    }

    var body: some View {
        let current = model.profile.sources.ratingIconSetURL
        SettingsSubpage(title: "Bewertungs-Icon-Satz", summary: current == nil ? "Eingebaute Plaketten" : "Eigener Satz aktiv") {
            SettingsSection {
                SettingsInfoRow(symbol: "photo.on.rectangle", tint: tint, title: "Status",
                                detail: current.flatMap { URL(string: $0)?.host },
                                value: Self.value(current, status: store.status))
                // F-B-9: the row stays (focus keeps its view) and is only dimmed once the built-in set is active.
                SettingsRow(symbol: "arrow.uturn.backward", tint: tint, title: "Eingebaute Plaketten verwenden",
                            reserveDetailSpace: false) {
                    guard current != nil else { return }
                    model.setRatingIconSet("")
                }
                .settingsUnavailable(current == nil)
                PhoneLinkRow(section: .system, symbol: "iphone", tint: tint, title: "Adresse am Handy eintragen",
                             detail: "Feld „Eigener Bewertungs-Icon-Satz“ im Abschnitt System.")
            }
            SettingsFootnote("JSON wie {\"imdb\": \"https://…/imdb.png\", \"tomatoes\": \"https://…\"} oder [{\"name\", \"url\"}]. "
                             + "Nur https, Bilder als PNG/JPG/WebP/HEIC (kein SVG), höchstens 50 Einträge; fehlt oder scheitert ein Icon, bleibt der Text.")
        }
        .task(id: current) { store.ensure(current) }
    }
}

extension AppModel {
    /// Welle F-a: Icon-Satz setzen (Handy-Seite, `PhoneCommand.setRatingIconSet`) oder leeren („Eingebaute verwenden“).
    func setRatingIconSet(_ s: String) {
        let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if !v.isEmpty, !RatingIconSet.isValidSetURL(v) { lastError = "Icon-Satz: nur https-Adressen"; return }
        update { $0.sources.ratingIconSetURL = v.isEmpty ? nil : v }
        RemoteLog.info("bewertung", v.isEmpty ? "Icon-Satz aus" : "Icon-Satz gesetzt")
    }
}
