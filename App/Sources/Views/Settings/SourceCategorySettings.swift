import SwiftUI
import PlayerCore

/// Wave S: category „Quellen“ (split from „Addons & Quellen“): which source plays and what happens beforehand.
/// Rows unchanged, only moved: sorting, badges and prefetch were „Addons & Quellen › Quellenliste“,
/// „Sofort abspielen anzeigen“ was „Wiedergabe & Bild › Detailseite“ (wave F-n). TorBox key: Profil & Konten.
struct SourceCategorySettings: View {
    @EnvironmentObject var model: AppModel

    private let tint = SettingsCategory.sources.tint

    var body: some View {
        let p = model.profile
        let torboxSet = !(p.apiKeys["torbox"] ?? "").isEmpty
        CategoryPage(.sources, summary: SettingsSummary.sources(order: p.sources.order, prefetch: p.appearance.prefetchStreams,
                                                                instantPlay: p.player.instantPlay)) {
            StatusCard(leading: .symbol("list.bullet.rectangle", tint),
                       title: SettingsSummary.orderName(p.sources.order) + " sortiert",
                       subtitle: "Quellen vorladen " + (p.appearance.prefetchStreams ? "an" : "aus"),
                       metrics: [StatusCard.Metric(text: "TorBox: " + (torboxSet ? "Schlüssel gespeichert" : "kein Schlüssel"))])
            SettingsSection("Auswahl") {
                StreamOrderSettingsRow()
                // Wave F-n: „Sofort abspielen“ card (wave G-a) only on request; default off, „Abspielen“ is the main button.
                SettingsToggleRow(symbol: "play.circle", tint: tint, title: "Sofort abspielen anzeigen",
                                  detail: "Zeigt bei Filmen neben „Abspielen“ die Karte „Sofort abspielen“: startet die beste Quelle ohne Auswahl.",
                                  reserveDetailSpace: false, isOn: model.binding(\.player.instantPlay))
            }
            SettingsSection("Liste") {
                StreamListBadgeSettingsRow()
                SettingsToggleRow(symbol: "bolt", tint: tint, title: "Quellen vorladen",
                                  detail: "Sucht Quellen schon im Hintergrund, damit die Liste beim Öffnen sofort da ist.",
                                  reserveDetailSpace: false, isOn: model.binding(\.appearance.prefetchStreams))
            }
        }
    }
}
