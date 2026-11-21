import SwiftUI
import PlayerCore

/// Rechte Seite einer `SettingsRow`.
enum SettingsRowAccessory: Equatable {
    /// Nichts rechts (reine Aktion).
    case none
    /// Nur Chevron: öffnet eine Unterseite.
    case chevron
    /// Aktueller Wert ohne Chevron (Wert wechselt in der Zeile).
    case value(String)
    /// Aktueller Wert und Chevron: Auswahlliste bzw. Unterseite.
    case valueChevron(String)
    /// An/Aus-Schalter (Text „An“/„Aus“ wie bei tvOS).
    case toggle(Bool)

    var valueText: String? {
        switch self {
        case .value(let v), .valueChevron(let v): v.isEmpty ? nil : v
        case .toggle(let on): on ? "An" : "Aus"
        case .none, .chevron: nil
        }
    }

    var showsChevron: Bool {
        switch self {
        case .chevron, .valueChevron: true
        default: false
        }
    }
}

/// Inhalt einer Einstellungszeile (§4.6): Symbolkachel 48×48 in Kategoriefarbe · Titel (`rowTitle`) ·
/// Beschreibung (`rowDetail`, 1–2 Zeilen) · rechts Wert / Chevron / An-Aus.
/// Als Label in `Button` oder `NavigationLink` mit `ThemeRowButtonStyle` einsetzen (oder fertig als `SettingsRow`).
/// Die Beschreibung steht bei der fokussierten Zeile immer, sonst nur mit `detailAlwaysVisible` (wichtige Hinweise).
/// `reserveDetailSpace` (Standard an): die Beschreibung bleibt im Layout und wird nur ein- und ausgeblendet,
/// damit die Zeilenhöhe beim Fokuswechsel nicht springt. Aus: die Zeile wächst bei Fokus (dichte Listen).
/// Die Breite begrenzt `ThemeRowButtonStyle` für die ganze Fläche.
struct SettingsRowLabel: View {
    let symbol: String
    let tint: Color
    let title: String
    var detail: String? = nil
    var accessory: SettingsRowAccessory = .none
    var detailAlwaysVisible = false
    var reserveDetailSpace = true
    @Environment(\.isFocused) private var focused

    private var detailShown: Bool { focused || detailAlwaysVisible }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            IconTile(symbol: symbol, color: tint)
            VStack(alignment: .leading, spacing: Theme.Space.xs / 2) {
                Text(title).textRoleInRow(.rowTitle).lineLimit(1)
                if let detail, !detail.isEmpty {
                    if reserveDetailSpace {
                        detailText(detail).opacity(detailShown ? 1 : 0)
                    } else if detailShown {
                        detailText(detail).transition(.opacity)
                    }
                }
            }
            .animation(.easeOut(duration: Theme.Focus.duration), value: detailShown)
            Spacer(minLength: Theme.Space.m)
            if let value = accessory.valueText {
                Text(value).textRoleInRow(.rowDetail).monospacedDigit().lineLimit(1)
            }
            if accessory.showsChevron {
                Image(systemName: "chevron.right")
                    .font(Theme.TextRole.rowDetail.font.weight(.semibold))
                    .foregroundStyle(Theme.Palette.foreground(secondary: true, focused: focused))
                    .accessibilityHidden(true)
            }
        }
    }

    private func detailText(_ text: String) -> some View {
        Text(text).textRoleInRow(.rowDetail).lineLimit(2).fixedSize(horizontal: false, vertical: true)
    }
}

/// Fertige Einstellungszeile als Knopf. VoiceOver liest Titel, Wert und die Beschreibung als Hinweis.
struct SettingsRow: View {
    let symbol: String
    let tint: Color
    let title: String
    var detail: String? = nil
    var accessory: SettingsRowAccessory = .none
    var detailAlwaysVisible = false
    var reserveDetailSpace = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowLabel(symbol: symbol, tint: tint, title: title, detail: detail,
                             accessory: accessory, detailAlwaysVisible: detailAlwaysVisible,
                             reserveDetailSpace: reserveDetailSpace)
        }
        .buttonStyle(ThemeRowButtonStyle())
        .settingsRowAccessibility(title: title, detail: detail, accessory: accessory)
    }
}

/// An/Aus-Zeile: OK schaltet um, rechts steht „An“/„Aus“.
struct SettingsToggleRow: View {
    let symbol: String
    let tint: Color
    let title: String
    var detail: String? = nil
    var detailAlwaysVisible = false
    var reserveDetailSpace = true
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            SettingsRowLabel(symbol: symbol, tint: tint, title: title, detail: detail,
                             accessory: .toggle(isOn), detailAlwaysVisible: detailAlwaysVisible,
                             reserveDetailSpace: reserveDetailSpace)
        }
        .buttonStyle(ThemeRowButtonStyle())
        .settingsRowAccessibility(title: title, detail: detail, accessory: .toggle(isOn))
        .accessibilityAddTraits(.isToggle)
    }
}

extension View {
    /// Einheitliche VoiceOver-Texte einer Zeile: Titel als Label, Wert als Wert, Beschreibung als Hinweis.
    func settingsRowAccessibility(title: String, detail: String?, accessory: SettingsRowAccessory) -> some View {
        // Auf dem Knopf selbst gesetzt (kein eigenes Element), damit die Aktivierung erhalten bleibt.
        self
            .accessibilityLabel(title)
            .accessibilityValue(accessory.valueText ?? "")
            .accessibilityHint(DesignText.accessibilityLabel([detail]))
    }
}

/// Fester Kopf der rechten Spalte (§4.6): Kategorietitel (`sectionTitle`) und einzeilige Zusammenfassung.
/// Steht außerhalb der scrollenden Liste, damit beim Scrollen nichts überdeckt wird.
struct SettingsHeader: View {
    let title: String
    var summary: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title).textRole(.sectionTitle).lineLimit(1)
            if let summary, !summary.isEmpty {
                Text(summary).textRole(.rowDetail).lineLimit(1)
            }
        }
        .frame(maxWidth: Theme.Layout.contentMaxWidth, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(DesignText.accessibilityLabel([title, summary]))
    }
}

/// Abschnittsüberschrift in Kapitälchen („SPRACHE“, `rowDetail`, 65 %).
struct SettingsSectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .textRole(.rowDetail)
            .tracking(1)
            .padding(.top, Theme.Space.l - Theme.Space.m)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(title)
    }
}

#Preview("Einstellungszeilen") {
    @Previewable @State var night = false
    VStack(alignment: .leading, spacing: Theme.Space.s) {
        SettingsHeader(title: "Ton & Untertitel", summary: DesignText.metaLine(["Deutsch → Englisch", "Nur erzwungene Untertitel"]))
        SettingsSectionLabel(title: "Sprache")
        SettingsRow(symbol: "waveform", tint: Theme.CategoryTint.audio.color, title: "Tonsprache",
                    detail: "Welche Tonspur zuerst gewählt wird.", accessory: .valueChevron("Deutsch → Englisch")) {}
        SettingsRow(symbol: "hifispeaker", tint: Theme.CategoryTint.audio.color, title: "Ton-Anlage",
                    detail: "TrueHD/DTS-HD als Dolby Digital Plus 5.1: Surround auch über optisch und ARC.",
                    accessory: .valueChevron("Über Fernseher (ARC)"), detailAlwaysVisible: true) {}
        SettingsSectionLabel(title: "Klang")
        SettingsToggleRow(symbol: "moon", tint: Theme.CategoryTint.audio.color, title: "Nachtmodus",
                          detail: "Leise Stellen lauter, laute leiser.", isOn: $night)
        SettingsRow(symbol: "timer", tint: Theme.CategoryTint.audio.color, title: "Ton-Versatz",
                    accessory: .value("0 ms")) {}
    }
    .padding(.horizontal, Theme.Space.edge)
    .padding(.vertical, Theme.Space.edgeVertical)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .settingsSurface()
}
