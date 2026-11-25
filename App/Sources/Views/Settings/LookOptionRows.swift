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
        for e in LookOptionCatalog.all where e.area == area && !seen.contains(e.group) { seen.append(e.group) }
        return seen
    }

    static func entries(_ area: LookArea, _ group: String) -> [LookOptionEntry] {
        LookOptionCatalog.all.filter { $0.area == area && $0.group == group }
    }

    /// Number of options that differ (accent dots), for the log line.
    static func overriddenCount(_ p: Profile) -> Int {
        LookOptionCatalog.all.filter { p.isLookOverridden($0.key) }.count
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
        case "Steuerleiste": "playpause"
        case "Panels und Hinweise": "rectangle.on.rectangle"
        default: "circle"
        }
    }

    /// Colour field of a value: the accent, or the background tone (`LookTheme`). `nil` for other options.
    static func swatch(_ key: String, _ raw: String) -> Color? {
        switch key {
        case "accent": LookAccent(rawValue: raw).map { ThemeValues.rgb(LookTheme.accent($0).accent) }
        case "background": LookBackground(rawValue: raw).map { ThemeValues.rgb(LookTheme.background($0).base) }
        default: nil
        }
    }

    var body: some View {
        let profile = model.profile
        let values = profile.themeLook
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
                            LookOptionRow(entry: e, raw: profile.lookRawValue(e.key),
                                          overridden: profile.isLookOverridden(e.key),
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
    private var detail: String { DesignText.metaLine([reason, entry.help]) }

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
                         detailAlwaysVisible: reason != nil, reserveDetailSpace: false, marked: overridden)
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
        if let color = LookOptionRows.swatch(entry.key, choice.raw) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                LookSwatch(color: color)
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

/// Colour field in the size of an icon tile, with a grey edge so black on a dark row and white on the focused
/// (white) row both stay visible.
private struct LookSwatch: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous)
            .fill(color)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous)
                    .strokeBorder(Color(white: 0.5).opacity(0.6), lineWidth: 2)
            }
            .frame(width: Theme.Layout.iconTile, height: Theme.Layout.iconTile)
            .accessibilityHidden(true)
    }
}
