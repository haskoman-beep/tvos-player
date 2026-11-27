import SwiftUI
import PlayerCore

/// Kategorie „Startseite“ (§2.2): Status, Reihen & Collections › / Fusion-Kit / Import (HomeSettings, Welle F-b2,
/// hier nur eingehängt), Titelbild, Kalender. Task 4.5: card size is the catalog row „Kartengröße“ under Aussehen;
/// integration build 5: hero on/off is the catalog row „Hero-Stil“ there too.
struct HomeCategorySettings: View {
    @Environment(AppModel.self) var model
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
            // Integration build 5 (user decision 26.11.): the old toggle „Titelbild oben“ is gone; the look row
            // `heroStyle` (Aussehen › Hero-Stil, „Aus“) switches the hero, so the source row follows the theme.
            if p.themeLook.home.heroStyle != .aus {
                SettingsSection("Titelbild") {
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
