import SwiftUI
import PlayerCore

/// Welle E-b: Einstellung „Quellen sortieren“ (Wie Addon / Smart (App)); Welle F-a: Zeile im Abschnitt „Quellenliste“; wave S: Quellen › Auswahl.
/// E-b M1 (Entscheidung F-a: Hinweis statt Verhaltensänderung): Weiterschauen, automatischer Wechsel und nächste
/// Folge wählen auch bei „Wie Addon“ nach den App-Vorlieben. Bei „Wie Addon“ steht das darum immer sichtbar da.
struct StreamOrderSettingsRow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let mode = model.profile.sources.order
        SettingsChoiceRow(symbol: "arrow.up.arrow.down", tint: SettingsCategory.sources.tint, title: "Quellen sortieren",
                          detail: mode == .smart
                              ? "Gecachte Quellen und Quellen in der ersten Tonsprache zuerst; AV1 ab 1440p ohne Hardware-Dekoder "
                                + "und AV1 bei Dolby Vision nach hinten; bei mehreren Diensten TorBox zuerst."
                              : "Liste wie von den Addons geliefert. Weiterschauen, automatischer Wechsel und nächste Folge "
                                + "wählen trotzdem nach deinen Vorlieben (Tonsprache, Cache-Status, TorBox zuerst, AV1).",
                          detailAlwaysVisible: mode == .addon,
                          options: StreamOrderMode.allCases, selection: model.binding(\.sources.order),
                          label: { $0.label })
    }
}

/// Welle E-b: Einstellung „App-Plaketten in der Quellenliste“ (Aus / Kompakt).
struct StreamListBadgeSettingsRow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        SettingsChoiceRow(symbol: "tag", tint: SettingsCategory.sources.tint, title: "App-Plaketten in der Liste",
                          detail: model.profile.sources.appBadges == .compact
                              ? "Nur „sofort“ und Größe, und nur, wenn der Text des Addons sie nicht schon zeigt."
                              : "Keine eigenen Plaketten, nur der Text der Addons.",
                          options: StreamListBadgeMode.allCases, selection: model.binding(\.sources.appBadges),
                          label: { $0.label })
    }
}
