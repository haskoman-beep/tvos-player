import SwiftUI
import PlayerCore

/// Task 4.5 (D-14, D-19, D-28): every option of `LookOptionCatalog.all` as a row, in four areas like the
/// configurator (Startseite & Hero, Detailseite, Player, Navigation & Einstellungen) with the group headers of
/// appendix A. A row shows the current value; OK opens the list of all values. A row that differs carries the
/// accent dot, and its long-press menu offers „Auf Standard zurücksetzen“. Rows that cannot change yet stay
/// focusable but dimmed and show the reason (`LookOptionCatalog.isEnabled`).
///
/// All writes go through `Profile.setLook` / `resetLook`, so the old fields follow and the theme changes at once.
/// Rows are keyed by `entry.id` and keep their view type when the value changes, so focus stays on the row.
struct LookOptionRows: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct AreaSection: Identifiable {
        let area: LookArea
        let title: String
        var id: LookArea { area }
    }

    /// The configurator's tab order.
    static let areas: [AreaSection] = [
        AreaSection(area: .home, title: "Startseite & Hero"),
        AreaSection(area: .detail, title: "Detailseite"),
        AreaSection(area: .player, title: "Player"),
        AreaSection(area: .global, title: "Navigation & Einstellungen"),
    ]

    /// Groups of an area in catalog order.
    static func groups(_ area: LookArea) -> [String] {
        var seen: [String] = []
        for e in LookOptionCatalog.rows where e.area == area && !seen.contains(e.group) { seen.append(e.group) }
        return seen
    }

    static func entries(_ area: LookArea, _ group: String) -> [LookOptionEntry] {
        LookOptionCatalog.rows.filter { $0.area == area && $0.group == group }
    }

    /// Number of options that differ (accent dots), for the log line.
    static func overriddenCount(_ p: Profile) -> Int {
        p.lookRows.overriddenCount + LookOptionCatalog.extras.filter { p.isLookOverridden($0.key) }.count
    }

    /// Fern-Log: „aussehen: Mein Look · <n> Abweichungen“ after every change.
    static func logLook(_ p: Profile) {
        RemoteLog.info("aussehen", "Mein Look · \(overriddenCount(p)) Abweichungen")
    }

    /// Tile symbol of a row, by group.
    static func symbol(_ e: LookOptionEntry) -> String {
        switch e.group {
        case "Navigation": "sidebar.left"
        case "Farbe": "paintbrush"
        case "Schrift und Bewegung": "textformat.size"
        case "Hero": "photo"
        case "Karten und Reihen": "rectangle.grid.2x2"
        case "Fokus-Effekt": "scope"
        case "Aufbau": "doc.text"
        case "Plaketten und Bewertungen": "seal"
        case "Quellenliste": "list.bullet"
        case "Folgen und Titel": "rectangle.stack"
        case "Steuerleiste": "playpause"
        case "Panels und Hinweise": "rectangle.on.rectangle"
        default: "circle"
        }
    }

    /// Colour field of a value: the accent, or the background tone (`LookTheme`). `nil` for other options.
    /// Review M1: a background shows its page tone (`surface`) with a raised card (`raised`) on it; the four `base`
    /// tones are all near black and could not be told apart on a TV.
    static func swatch(_ key: String, _ raw: String) -> LookSwatchColors? {
        if key == "accent", let accent = LookAccent(rawValue: raw) {
            return LookSwatchColors(fill: ThemeValues.rgb(LookTheme.accent(accent).accent))
        }
        if key == "background", let tone = LookBackground(rawValue: raw) {
            let bg = LookTheme.background(tone)
            return LookSwatchColors(fill: ThemeValues.rgb(bg.surface), card: ThemeValues.rgb(bg.raised))
        }
        return nil
    }

    var body: some View {
        // Review M2: `themeLook` and one encode per body (`Profile.lookRows`), not two encodes per row.
        let values = model.profile.themeLook
        let rows = LookRowValues(values)
        ForEach(Self.areas) { section in
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(section.title)
                    .textRole(.rowTitleEmphasis)
                    .padding(.top, Theme.Space.l)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Self.groups(section.area), id: \.self) { group in
                    SettingsSection(group) {
                        if let hint = LookOptionCatalog.groupHint(group, in: values) {
                            SettingsFootnote(hint)
                        }
                        ForEach(Self.entries(section.area, group)) { e in
                            let state = LookOptionCatalog.isEnabled(e.key, in: values, reduceMotion: reduceMotion)
                            LookOptionRow(entry: e, raw: rows.raw[e.key], overridden: rows.isOverridden(e.key),
                                          enabled: state.enabled, reason: state.reason)
                        }
                    }
                }
            }
        }
    }
}

/// One option row. Enabled: opens `LookChoicePage`. Not enabled: focusable, dimmed, OK does nothing
/// (`settingsUnavailable`, so focus never jumps when a row locks under it).
private struct LookOptionRow: View {
    let entry: LookOptionEntry
    let raw: String?
    let overridden: Bool
    let enabled: Bool
    let reason: String?
    @EnvironmentObject var model: AppModel

    private var value: String { raw.flatMap { entry.choiceLabel($0) } ?? "" }
    /// Review M6: a disabled row shows only its reason, so it stays one line high; an enabled row keeps the help
    /// text (after the reduce-motion note, if any) while focused and only the note at rest (`restingDetail`).
    private var detail: String { enabled ? DesignText.metaLine([reason, entry.help]) : (reason ?? entry.help) }

    var body: some View {
        Group {
            if enabled {
                NavigationLink {
                    LookChoicePage(entry: entry)
                } label: {
                    label(.valueChevron(value))
                }
            } else {
                Button {} label: {
                    label(.value(value))
                }
            }
        }
        .buttonStyle(ThemeRowButtonStyle())
        .settingsRowAccessibility(title: entry.label, detail: detail,
                                  accessory: .value(overridden ? "\(value), angepasst" : value))
        .settingsUnavailable(!enabled)
        .contextMenu {
            if overridden {
                Button("Auf Standard zurücksetzen") {
                    model.update { $0.setLook(entry.key, to: nil) }
                    RemoteLog.info("einstellung", "\(entry.label): auf Standard zurückgesetzt")
                    LookOptionRows.logLook(model.profile)
                }
            }
        }
    }

    private func label(_ accessory: SettingsRowAccessory) -> some View {
        SettingsRowLabel(symbol: LookOptionRows.symbol(entry), tint: SettingsCategory.appearance.tint,
                         title: entry.label, detail: detail, accessory: accessory,
                         detailAlwaysVisible: reason != nil, reserveDetailSpace: false, marked: overridden,
                         restingDetail: reason)
    }
}

/// Push list of all values of one option; OK picks, writes through `Profile.setLook` and goes back to the row.
/// Focus starts on the current value. Accent and background values show their colour field.
struct LookChoicePage: View {
    let entry: LookOptionEntry
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: String?

    var body: some View {
        let current = model.profile.lookRawValue(entry.key)
        SettingsSubpage(title: entry.label, summary: entry.help) {
            ForEach(entry.choices, id: \.raw) { c in
                let on = c.raw == current
                Button {
                    choose(c)
                } label: {
                    LookChoiceLabel(entry: entry, choice: c, selected: on)
                }
                .buttonStyle(ThemeRowButtonStyle())
                .focused($focus, equals: c.raw)
                .settingsRowAccessibility(title: c.label, detail: nil, accessory: .none)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .defaultFocus($focus, current)
    }

    private func choose(_ c: LookChoice) {
        model.update { $0.setLook(entry.key, to: c.raw) }
        RemoteLog.info("einstellung", "\(entry.label): \(c.label)")
        LookOptionRows.logLook(model.profile)
        dismiss()
    }
}

/// One value: colour field (accent, background) or the row tile with a check mark on the chosen value.
private struct LookChoiceLabel: View {
    let entry: LookOptionEntry
    let choice: LookChoice
    let selected: Bool

    var body: some View {
        if let colors = LookOptionRows.swatch(entry.key, choice.raw) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                LookSwatch(colors: colors)
                Text(choice.label).textRoleInRow(.rowTitle).lineLimit(1)
                Spacer(minLength: Theme.Space.m)
                if selected {
                    Text("Gewählt").textRoleInRow(.rowDetail).lineLimit(1)
                }
            }
        } else {
            SettingsRowLabel(symbol: selected ? "checkmark" : LookOptionRows.symbol(entry),
                             tint: SettingsCategory.appearance.tint, title: choice.label,
                             accessory: .value(selected ? "Gewählt" : ""), reserveDetailSpace: false)
        }
    }
}

/// Colours of one swatch: the field, and for a background tone the raised card drawn on it.
struct LookSwatchColors {
    let fill: Color
    var card: Color? = nil
}

/// Colour field in the size of an icon tile, with a grey edge so black on a dark row and white on the focused
/// (white) row both stay visible. A background tone carries a small raised card in its lower half (review M1).
private struct LookSwatch: View {
    let colors: LookSwatchColors

    var body: some View {
        let tile: CGFloat = Theme.Layout.iconTile
        let inset: CGFloat = tile * 0.18
        RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous)
            .fill(colors.fill)
            .overlay(alignment: .bottom) {
                if let card = colors.card {
                    RoundedRectangle(cornerRadius: inset / 2, style: .continuous)
                        .fill(card)
                        .frame(height: tile * 0.42)
                        .padding(inset)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous)
                    .strokeBorder(Color(white: 0.5).opacity(0.6), lineWidth: 2)
            }
            .frame(width: tile, height: tile)
            .accessibilityHidden(true)
    }
}
