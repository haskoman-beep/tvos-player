import SwiftUI
import PlayerCore

/// Kategorie 3 „Startseite“ (§2.2): Status, Reihen & Collections › / Fusion-Kit / Import (HomeSettings, Welle F-b2,
/// hier nur eingehängt), Titelbild, Kalender.
struct HomeCategorySettings: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var kit = FusionKitStore.shared

    private let tint = SettingsCategory.home.tint

    var body: some View {
        let p = model.profile
        CategoryPage(.home, summary: SettingsSummary.home(rows: p.home.rows.count, fusionKit: kit.settings.enabled)) {
            StatusCard(leading: .symbol("house", tint), title: SettingsSummary.rows(p.home.rows.count),
                       subtitle: SettingsSummary.collections(p.collections.count),
                       metrics: [StatusCard.Metric(text: "Fusion-Kit " + (kit.settings.enabled ? "an" : "aus")),
                                 StatusCard.Metric(text: p.hiddenRows.isEmpty ? "" : "\(p.hiddenRows.count) ausgeblendet")])
            SettingsSection("Reihen") {
                // Reihen & Collections ›, Fusion-Kit, Collections importieren › (Inhalt gehört Welle F-b2).
                HomeSettings()
            }
            SettingsSection("Titelbild") {
                SettingsToggleRow(symbol: "photo.artframe", tint: tint, title: "Titelbild oben",
                                  detail: "Großes Bild mit Titel oben auf der Startseite.",
                                  reserveDetailSpace: false, isOn: model.binding(\.appearance.heroEnabled))
                if p.appearance.heroEnabled {
                    SettingsChoiceRow(symbol: "photo", tint: tint, title: "Titelbild zeigt",
                                      detail: "Aus welcher Reihe das Titelbild kommt.",
                                      options: [UUID?.none] + listRows.map { UUID?.some($0.id) },
                                      selection: heroSelection, label: heroName)
                }
            }
            SettingsSection("Kalender") {
                SettingsToggleRow(symbol: "calendar", tint: tint, title: "Sendezeiten von TVmaze",
                                  detail: "Uhrzeit und Tag in deiner Zeitzone (US-Abendfolgen stehen sonst einen Tag zu früh). "
                                      + "Sendedaten von TVmaze.com, Lizenz CC BY-SA 4.0.",
                                  reserveDetailSpace: false, isOn: model.binding(\.sources.tvmazeAirtimes))
            }
        }
    }

    /// Zeigt „Automatisch“, wenn die gespeicherte Reihe keine Listen-Reihe (mehr) ist.
    private var heroSelection: Binding<UUID?> {
        Binding(get: {
            let id = model.profile.appearance.heroRowID
            return listRows.contains { $0.id == id } ? id : nil
        }, set: { v in model.update { $0.appearance.heroRowID = v } })
    }

    /// Nur Listen-Reihen, nie Collection-Reihen.
    private var listRows: [HomeRow] {
        model.profile.home.rows.filter { row in
            if case .list = row.content { return true }
            return false
        }
    }

    private func heroName(_ id: UUID?) -> String {
        guard let id, let r = listRows.first(where: { $0.id == id }), case .list(let s) = r.content else { return "Automatisch" }
        return s.title
    }
}
