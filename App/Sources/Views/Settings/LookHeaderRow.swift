import SwiftUI
import PlayerCore

/// Task 4.5: top row of Einstellungen › Aussehen. „Mein Look“ with „Apple TV“ or „angepasst · n“
/// (`SettingsSummary.lookValue`). There is no preset choice; OK asks first and then resets every option
/// (`Profile.resetLook`, which also writes the old fields).
struct LookHeaderRow: View {
    @EnvironmentObject var model: AppModel
    @State private var confirming = false

    static let title = "Mein Look"
    static let resetTitle = "Alles auf Apple TV zurücksetzen"

    var body: some View {
        SettingsRow(symbol: "paintpalette", tint: SettingsCategory.appearance.tint, title: Self.title,
                    detail: Self.resetTitle, accessory: .value(SettingsSummary.lookValue(model.profile)),
                    detailAlwaysVisible: true, reserveDetailSpace: false) {
            confirming = true
        }
        .settingsConfirmation("Alles auf Apple TV zurücksetzen?", isPresented: $confirming,
                              message: "Alle Optionen von „Mein Look“ bekommen wieder ihren Grundwert.",
                              verb: "Zurücksetzen", symbol: "arrow.counterclockwise") {
            model.update { $0.resetLook() }
            LookOptionRows.logLook(model.profile)
        }
    }
}
