import SwiftUI
import PlayerCore

/// Ein Eintrag der linken Spalte einer `CategoryList`.
struct CategoryEntry {
    let title: String
    let symbol: String
    let tint: Color
    /// Anzahl rechts (z. B. Einträge je Quelle im Reihen-Browser); `nil` = keine.
    var count: Int? = nil
}

/// Wave S: what stands above an entry of the left column when it opens a group. Not focusable: focus moves
/// from entry to entry, the column scrolls with it, and the header scrolls along above its first entry.
enum CategoryGroupLabel: Equatable {
    /// Small-caps header, e.g. „INHALTE“.
    case title(String)
    /// Only a gap (System at the end, set apart without a header).
    case gap
}

/// Zweispaltiges Muster „links wählen, rechts Inhalt“ (§4.6) für die Einstellungen und den Reihen-Browser.
/// - Fokuswechsel ohne Klick: der fokussierte Eintrag links wird sofort aktiv.
/// - Akzentmarke statt Chevron am aktiven Eintrag.
/// - Rückkehr auf den aktiven Eintrag: kommt der Fokus von rechts zurück, landet er auf dem aktiven Eintrag,
///   nicht auf dem geometrisch nächsten.
/// - Menu (N3): aus der rechten Spalte auf den aktiven Eintrag, aus der linken Spalte `onExit`.
///
/// `header` steht über den Einträgen (z. B. die Kopfkachel „Am Handy einrichten“). **Die Wurzel des Kopfs muss
/// selbst genau ein Knopf sein** (z. B. eine `SettingsRow`), kein Container mit einem Knopf darin: nur dann greift
/// `.focused(_, equals: .header)`. Sonst bliebe `focused == nil`, Menu auf dem Kopf spränge auf den aktiven
/// Eintrag statt `onExit`, und „runter“ vom Kopf würde auf den aktiven Eintrag umgelenkt.
struct CategoryList<Item: Hashable, Header: View, Content: View>: View {
    let items: [Item]
    @Binding var selected: Item
    let entry: (Item) -> CategoryEntry
    /// Wave S: optional group header or gap above an entry (`nil` = none).
    let groupLabel: (Item) -> CategoryGroupLabel?
    /// Menu in der linken Spalte (z. B. Einstellungen verlassen bzw. Browser schließen).
    let onExit: () -> Void
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: (Item) -> Content

    private enum Focus: Hashable { case header, item(Item) }
    @FocusState private var focused: Focus?

    init(items: [Item], selected: Binding<Item>, entry: @escaping (Item) -> CategoryEntry,
         groupLabel: @escaping (Item) -> CategoryGroupLabel? = { _ in nil },
         onExit: @escaping () -> Void,
         @ViewBuilder header: @escaping () -> Header,
         @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self._selected = selected
        self.entry = entry
        self.groupLabel = groupLabel
        self.onExit = onExit
        self.header = header
        self.content = content
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.xl) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    header()
                        .focused($focused, equals: .header)
                        .padding(.bottom, Theme.Space.m)
                    ForEach(items, id: \.self) { item in
                        let e = entry(item)
                        let active = item == selected
                        if let label = groupLabel(item) {
                            CategoryGroupHeader(label: label)
                        }
                        Button { selected = item } label: {
                            CategoryEntryLabel(entry: e, active: active)
                        }
                        .buttonStyle(ThemeRowButtonStyle(minHeight: Theme.Layout.categoryRowMinHeight, maxWidth: .infinity))
                        .focused($focused, equals: .item(item))
                        .accessibilityLabel(e.title)
                        .accessibilityValue(e.count.map { $0 == 1 ? "1 Eintrag" : "\($0) Einträge" } ?? "")
                        .accessibilityAddTraits(active ? .isSelected : [])
                    }
                }
                .padding(.vertical, Theme.Space.m)
            }
            .scrollClipDisabled()
            .frame(width: Theme.Layout.categoryColumnWidth)
            .focusSection()
            .defaultFocus($focused, .item(selected))

            content(selected)
                .id(selected)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .focusSection()
        }
        .onChange(of: focused) { old, new in
            guard case .item(let item)? = new else { return }
            if old == nil && item != selected {
                // Fokus kommt von rechts: auf den aktiven Eintrag lenken, statt still den nächsten zu wählen.
                focused = .item(selected)
            } else if item != selected {
                selected = item
            }
        }
        .onExitCommand {
            if focused == nil {
                focused = .item(selected)
            } else {
                onExit()
            }
        }
    }
}

extension CategoryList where Header == EmptyView {
    init(items: [Item], selected: Binding<Item>, entry: @escaping (Item) -> CategoryEntry,
         groupLabel: @escaping (Item) -> CategoryGroupLabel? = { _ in nil },
         onExit: @escaping () -> Void,
         @ViewBuilder content: @escaping (Item) -> Content) {
        self.init(items: items, selected: selected, entry: entry, groupLabel: groupLabel, onExit: onExit,
                  header: { EmptyView() }, content: content)
    }
}

/// Wave S: group header (small caps, aligned with the entry titles) or a plain gap. Not focusable.
private struct CategoryGroupHeader: View {
    let label: CategoryGroupLabel

    var body: some View {
        switch label {
        case .title(let t):
            Text(t.uppercased())
                .textRole(.rowDetail)
                .tracking(1)
                .lineLimit(1)
                // Same inset as the row content (row padding of ThemeRowButtonStyle).
                .padding(.leading, Theme.Space.m)
                .padding(.top, Theme.Space.s)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(t)
        case .gap:
            Spacer().frame(height: Theme.Space.m).accessibilityHidden(true)
        }
    }
}

/// Zeile der linken Spalte: Akzentmarke (nur aktiv) · Symbolkachel · Titel · Anzahl.
private struct CategoryEntryLabel: View {
    let entry: CategoryEntry
    let active: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            // Platz für die Marke bleibt immer frei, damit die Titel auf einer Linie stehen.
            Capsule()
                .fill(active ? Theme.accentMark(focused: focused) : AnyShapeStyle(Color.clear))
                .frame(width: Theme.Layout.accentMarkWidth, height: Theme.Layout.iconTile - Theme.Space.xs)
                .accessibilityHidden(true)
            IconTile(symbol: entry.symbol, color: entry.tint)
            Text(entry.title)
                .textRoleInRow(.rowTitle)
                .fontWeight(active ? .semibold : .regular)
                .lineLimit(1)
            Spacer(minLength: Theme.Space.s)
            if let count = entry.count {
                Text("\(count)").textRoleInRow(.rowDetail).monospacedDigit()
            }
        }
    }
}

#Preview("Kategorieliste") {
    @Previewable @State var selected = Theme.CategoryTint.audio
    let names: [Theme.CategoryTint: (String, String)] = [
        .profile: ("Profil & Konten", "person.crop.circle"),
        .addons: ("Addons", "puzzlepiece.extension"),
        .sources: ("Quellen", "list.bullet.rectangle"),
        .home: ("Startseite", "house"),
        .appearance: ("Aussehen", "paintpalette"),
        .playback: ("Wiedergabe", "play.rectangle"),
        .audio: ("Sprache & Untertitel", "captions.bubble"),
        .picture: ("Bild & Ton", "tv.and.hifispeaker.fill"),
        .system: ("System", "gearshape"),
    ]
    CategoryList(items: Theme.CategoryTint.allCases, selected: $selected,
                 entry: { CategoryEntry(title: names[$0]?.0 ?? "", symbol: names[$0]?.1 ?? "circle", tint: $0.color) },
                 onExit: {},
                 header: {
                     SettingsRow(symbol: "qrcode", tint: Theme.CategoryTint.system.color, title: "Am Handy einrichten",
                                 detail: "Addons, Schlüssel, Importe", accessory: .chevron, detailAlwaysVisible: true) {}
                 },
                 content: { item in
                     VStack(alignment: .leading, spacing: Theme.Space.s) {
                         SettingsHeader(title: names[item]?.0 ?? "", summary: "Zusammenfassung")
                         SettingsRow(symbol: names[item]?.1 ?? "circle", tint: item.color, title: "Erste Zeile",
                                     detail: "Beschreibung der Zeile.", accessory: .value("Wert")) {}
                     }
                 })
    .padding(.horizontal, Theme.Space.edge)
    .padding(.vertical, Theme.Space.edgeVertical)
    .settingsSurface()
}
