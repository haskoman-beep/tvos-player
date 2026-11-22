import SwiftUI
import PlayerCore

/// Wave P-a: section „Überspringen“: action per segment type (Aus / Knopf / Automatisch) and the card after a movie.
/// Self-contained (one hook line in today's settings); wave S moves it into the new settings tree.
struct SkipSettingsRows: View {
    @EnvironmentObject var model: AppModel

    private let tint = SettingsCategory.playback.tint

    var body: some View {
        SettingsSection("Überspringen") {
            ForEach(SkipSettings.configurableKinds, id: \.self) { kind in
                SettingsChoiceRow(symbol: Self.symbol(kind), tint: tint, title: SkipSettings.title(kind),
                                  detail: Self.detail(kind, model.profile.skip.action(for: kind)),
                                  options: SkipAction.allCases,
                                  selection: Binding(get: { model.profile.skip.action(for: kind) },
                                                     set: { a in model.update { $0.skip.set(a, for: kind) } }),
                                  label: { $0.label })
            }
            SettingsToggleRow(symbol: "rectangle.stack", tint: tint, title: "Karte nach dem Film",
                              detail: "Zeigt bei Filmen ab dem Abspann zwei bis drei Empfehlungen, „Abspann weiterschauen“ "
                                  + "und „Zurück“. Braucht Abspann-Marken (Kapitel oder IntroDB).",
                              reserveDetailSpace: false, isOn: model.binding(\.skip.postPlayCard))
            SettingsFootnote("Eine Szene nach dem Abspann wird nie übersprungen oder verdeckt. Bei „Automatisch“ "
                             + "läuft 5 s ein Ring; OK springt sofort, jede andere Taste bricht ab.")
        }
    }

    static func symbol(_ k: SkipSegment.Kind) -> String {
        switch k {
        case .intro: "forward.end"
        case .recap: "clock.arrow.circlepath"
        case .credits: "list.and.film"
        case .preview: "film.stack"
        case .postCredits: "sparkles"
        }
    }

    static func detail(_ k: SkipSegment.Kind, _ a: SkipAction) -> String {
        if k == .credits {
            switch a {
            case .off: return "Kein Knopf. Die Karte „Nächste Folge“ bzw. die Karte nach dem Film gilt weiter."
            case .button, .auto:
                return "Nur, wenn keine Karte den Abspann übernimmt. Mit Szene danach endet der Sprung an der Szene."
            }
        }
        switch a {
        case .off: return "Kein Knopf, kein Sprung."
        case .button: return "Knopf „\(SkipSettings.title(k)) überspringen“, solange der Abschnitt läuft."
        case .auto: return "Springt nach 5 s Countdown; einmal je Abschnitt."
        }
    }
}
