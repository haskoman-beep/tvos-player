import SwiftUI
import PlayerCore

// Welle F-a: gemeinsame Bausteine der Einstellungsseiten (auf den F-0-Bausteinen aus Views/Design).
// Alle Zeilen hier sind dichte Listen: `reserveDetailSpace: false` (F-0-Re-Review N2), Texte links bündig (N3).

/// Scrollender Inhalt einer Kategorie (rechte Spalte) bzw. einer Unterseite. Seitentitel und Kopf scrollen mit
/// (kein `navigationTitle`, der große tvOS-Titel lag sonst beim Scrollen über den Zeilen).
struct SettingsPage<Content: View>: View {
    var pageTitle: String? = nil
    let title: String
    var summary: String? = nil
    /// Wave S: storage scope under the category title („Gilt für dieses Profil“ / „… Gerät“).
    var scope: SettingsScope? = nil
    let content: Content
    /// Task 5.6: inside the `liste` layout the page is one section of the shared list: no scroll view of its own
    /// and no page title (the list has one), the category title is the section header.
    @Environment(\.settingsEmbedded) private var embedded

    init(pageTitle: String? = nil, title: String, summary: String? = nil, scope: SettingsScope? = nil,
         @ViewBuilder content: () -> Content) {
        self.pageTitle = pageTitle
        self.title = title
        self.summary = summary
        self.scope = scope
        self.content = content()
    }

    var body: some View {
        if embedded {
            page(showsPageTitle: false)
        } else {
            ScrollView(.vertical) {
                page(showsPageTitle: true)
                    .frame(maxWidth: Theme.Layout.contentMaxWidth, alignment: .leading)
                    .padding(.vertical, Theme.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollClipDisabled()
        }
    }

    private func page(showsPageTitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if showsPageTitle, let pageTitle {
                Text(pageTitle).textRole(.pageTitle).accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                SettingsHeader(title: title, summary: summary)
                if let scope { SettingsScopeLine(scope: scope) }
            }
            .padding(.bottom, Theme.Space.xs)
            content
        }
    }
}

/// Wave S: one quiet line under the category title that says where its values are stored. Not focusable.
struct SettingsScopeLine: View {
    let scope: SettingsScope

    var body: some View {
        Label(scope.label, systemImage: scope == .device ? "appletv" : "person.crop.circle")
            .textRole(.rowDetail)
            .lineLimit(1)
            .accessibilityLabel(scope.label)
    }
}

/// Inhalt einer Kategorie: Seitentitel „Einstellungen“, Kategorietitel, Zusammenfassung aus `SettingsSummary`,
/// darunter die Geltung (wave S, `SettingsCategory.scope`).
struct CategoryPage<Content: View>: View {
    let category: SettingsCategory
    let summary: String
    let content: Content

    init(_ category: SettingsCategory, summary: String, @ViewBuilder content: () -> Content) {
        self.category = category
        self.summary = summary
        self.content = content()
    }

    var body: some View {
        SettingsPage(pageTitle: "Einstellungen", title: category.title, summary: summary, scope: category.scope) { content }
    }
}

/// Unterseite (Push im Einstellungs-Stack, §2.4) mit eigenem Kopf. Menu führt zur auslösenden Zeile zurück.
struct SettingsSubpage<Content: View>: View {
    let title: String
    var summary: String? = nil
    let content: Content

    init(title: String, summary: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.summary = summary
        self.content = content()
    }

    var body: some View {
        SettingsPage(title: title, summary: summary) { content }
            // Task 5.6: a subpage pushed from the `liste` layout is a page of its own again.
            .environment(\.settingsEmbedded, false)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .settingsSurface()
            .onAppear { RemoteLog.info("nav", "Einstellungen › \(title)") }
    }
}

/// Abschnitt mit Kapitälchen-Überschrift.
struct SettingsSection<Content: View>: View {
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let title { SettingsSectionLabel(title: title) }
            content
        }
    }
}

/// Erklärender Text unter Zeilen (nicht fokussierbar).
struct SettingsFootnote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .textRole(.rowDetail)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Space.m)
            .frame(maxWidth: Theme.Layout.contentMaxWidth, alignment: .leading)
    }
}

/// Zeile, die eine Unterseite öffnet (Chevron, optional mit aktuellem Wert).
struct SettingsLinkRow<Destination: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    var detail: String? = nil
    var value: String? = nil
    var detailAlwaysVisible = false
    @ViewBuilder let destination: () -> Destination

    private var accessory: SettingsRowAccessory { value.map { .valueChevron($0) } ?? .chevron }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            SettingsRowLabel(symbol: symbol, tint: tint, title: title, detail: detail, accessory: accessory,
                             detailAlwaysVisible: detailAlwaysVisible, reserveDetailSpace: false)
        }
        .buttonStyle(ThemeRowButtonStyle())
        .settingsRowAccessibility(title: title, detail: detail, accessory: accessory)
    }
}

/// E7: Statt Schlüssel- oder Adressfeld am Fernseher öffnet die Zeile die QR-Seite am passenden Abschnitt (Anker).
struct PhoneLinkRow: View {
    let section: PhoneSection?
    let symbol: String
    let tint: Color
    let title: String
    var detail: String? = nil
    var value: String? = nil
    var detailAlwaysVisible = false

    var body: some View {
        SettingsLinkRow(symbol: symbol, tint: tint, title: title, detail: detail, value: value,
                        detailAlwaysVisible: detailAlwaysVisible) {
            PhoneInputView(section: section)
        }
    }
}

/// Auswahlzeile (§2.4). Bis 3 Werte: OK schaltet in der Zeile weiter (Wert rechts). Mehr als 3 Werte:
/// Push-Liste mit Häkchen. Abweichung vom Plan (◀▶ in der Zeile): links/rechts gehört auf tvOS dem Fokus
/// (links führt in die Kategorienspalte), darum OK zum Weiterschalten.
struct SettingsChoiceRow<Value: Hashable>: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String?
    let detailAlwaysVisible: Bool
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    let optionTint: ((Value) -> Color)?
    /// Immer Push-Liste, auch bei ≤ 3 Werten: für Auswahlen mit Nebenwirkung (Sync, Neuladen, Umbau der Oberfläche),
    /// damit beim Durchschalten kein Zwischenwert gespeichert wird (Review F-a M6).
    let alwaysList: Bool

    init(symbol: String, tint: Color, title: String, detail: String? = nil, detailAlwaysVisible: Bool = false,
         options: [Value], selection: Binding<Value>, optionTint: ((Value) -> Color)? = nil, alwaysList: Bool = false,
         label: @escaping (Value) -> String) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.detail = detail
        self.detailAlwaysVisible = detailAlwaysVisible
        self.options = options
        self._selection = selection
        self.label = label
        self.optionTint = optionTint
        self.alwaysList = alwaysList
    }

    var body: some View {
        if options.count <= 3, !alwaysList {
            SettingsRow(symbol: symbol, tint: tint, title: title, detail: detail, accessory: .value(label(selection)),
                        detailAlwaysVisible: detailAlwaysVisible, reserveDetailSpace: false) {
                guard !options.isEmpty else { return }
                let next = options.firstIndex(of: selection).map { (options.index(after: $0)) % options.count } ?? 0
                selection = options[next]
                RemoteLog.info("einstellung", "\(title): \(label(options[next]))")
            }
        } else {
            SettingsLinkRow(symbol: symbol, tint: tint, title: title, detail: detail, value: label(selection),
                            detailAlwaysVisible: detailAlwaysVisible) {
                SettingsChoicePage(title: title, detail: detail, symbol: symbol, tint: tint, options: options,
                                   selection: $selection, optionTint: optionTint, label: label)
            }
        }
    }
}

/// Push-Liste einer Auswahl mit Häkchen; OK wählt und kehrt zurück. Fokus startet auf dem gewählten Wert.
struct SettingsChoicePage<Value: Hashable>: View {
    let title: String
    let detail: String?
    let symbol: String
    let tint: Color
    let options: [Value]
    @Binding var selection: Value
    let optionTint: ((Value) -> Color)?
    let label: (Value) -> String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Value?

    var body: some View {
        SettingsSubpage(title: title, summary: detail) {
            ForEach(options, id: \.self) { v in
                let on = v == selection
                Button {
                    selection = v
                    RemoteLog.info("einstellung", "\(title): \(label(v))")
                    dismiss()
                } label: {
                    SettingsRowLabel(symbol: on ? "checkmark" : symbol, tint: optionTint?(v) ?? tint, title: label(v),
                                     accessory: .value(on ? "Gewählt" : ""), reserveDetailSpace: false)
                }
                .buttonStyle(ThemeRowButtonStyle())
                .focused($focus, equals: v)
                .settingsRowAccessibility(title: label(v), detail: nil, accessory: .none)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .defaultFocus($focus, selection)
    }
}

/// Reine Info-Zeile (fokussierbar, damit die Liste bis dorthin scrollt; OK tut nichts).
struct SettingsInfoRow: View {
    let symbol: String
    let tint: Color
    let title: String
    var detail: String? = nil
    var value: String? = nil
    var detailAlwaysVisible = false

    var body: some View {
        SettingsRow(symbol: symbol, tint: tint, title: title, detail: detail, accessory: value.map { SettingsRowAccessory.value($0) } ?? SettingsRowAccessory.none,
                    detailAlwaysVisible: detailAlwaysVisible, reserveDetailSpace: false) {}
    }
}

/// E6/§2.4: eigene Rückfrage statt `confirmationDialog`. Grund (Review F-a I1): tvOS fokussiert im Aktionsblatt die
/// erste Aktion, `role: .cancel` rückt „Behalten“ aber ans Ende – der Fokus läge auf dem Zerstörenden.
/// Hier steht „Behalten“ oben und bekommt den Fokus doppelt abgesichert (`defaultFocus` + `onAppear`);
/// Menu schließt ohne Aktion (`onExitCommand`). Wiederverwendbar für alle Wellen (auch F-b2).
struct SettingsConfirmationView: View {
    let title: String
    let message: String
    let verb: String
    /// Symbol der bestätigenden Zeile (Review F-a N1): Löschen = Papierkorb, Abmelden/Ausblenden eigene Symbole.
    var symbol: String = "trash"
    let onKeep: () -> Void
    let onConfirm: () -> Void

    private enum Choice: Hashable { case keep, confirm }
    @FocusState private var focus: Choice?

    var body: some View {
        ZStack {
            Theme.Palette.scrim.ignoresSafeArea()
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text(title).textRole(.sectionTitle)
                Text(message).textRole(.rowDetail)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: Theme.Space.s) {
                    Button(action: keep) {
                        SettingsRowLabel(symbol: "arrow.uturn.backward", tint: Theme.CategoryTint.system.color, title: "Behalten",
                                         reserveDetailSpace: false)
                    }
                    .buttonStyle(ThemeRowButtonStyle(maxWidth: .infinity))
                    .focused($focus, equals: .keep)
                    .settingsRowAccessibility(title: "Behalten", detail: nil, accessory: .none)
                    Button(action: confirm) {
                        SettingsRowLabel(symbol: symbol, tint: Theme.Tone.error.color, title: verb, reserveDetailSpace: false)
                    }
                    .buttonStyle(ThemeRowButtonStyle(maxWidth: .infinity))
                    .focused($focus, equals: .confirm)
                    .settingsRowAccessibility(title: verb, detail: message, accessory: .none)
                }
                .padding(.top, Theme.Space.s)
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: Theme.Layout.confirmationWidth)
            .background(Theme.Palette.overlayCard, in: RoundedRectangle(cornerRadius: Theme.Radius.overlayCard))
            .focusSection()
        }
        .defaultFocus($focus, .keep)
        .onAppear { focus = .keep }
        .onExitCommand(perform: keep)
    }

    private func keep() {
        RemoteLog.info("einstellung", "Rückfrage „\(title)“: behalten")
        onKeep()
    }

    private func confirm() {
        RemoteLog.info("einstellung", "Rückfrage „\(title)“: \(verb)")
        onConfirm()
    }
}

/// Hält fest, ob bestätigt wurde, und führt die Aktion (bzw. `onKeep`) erst nach dem Schließen der Überlagerung aus
/// (sonst kollidiert z. B. „Addon entfernen“ + Seite schließen mit der laufenden Ausblendung, und ein Fokus-Sprung
/// käme vor dem Ende der Überlagerung).
private struct SettingsConfirmationModifier: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let message: String
    let verb: String
    let symbol: String
    let onKeep: (() -> Void)?
    let action: () -> Void
    /// Aktion aus dem Moment der Wahl (bei item: noch mit dem Objekt).
    @State private var pending: (() -> Void)?
    /// Letzter sichtbarer Text: bei der item-Variante wird `title` beim Schließen leer, die Karte blendet aber noch aus.
    @State private var shownTitle = ""
    @State private var shownMessage = ""

    func body(content: Content) -> some View {
        content
            .onChange(of: title, initial: true) { _, t in if !t.isEmpty { shownTitle = t } }
            .onChange(of: message, initial: true) { _, m in if !m.isEmpty { shownMessage = m } }
            .fullScreenCover(isPresented: $isPresented, onDismiss: {
                let run = pending
                pending = nil
                run?()
            }) {
                SettingsConfirmationView(title: title.isEmpty ? shownTitle : title,
                                         message: message.isEmpty ? shownMessage : message,
                                         verb: verb, symbol: symbol,
                                         onKeep: { pending = onKeep; isPresented = false },
                                         onConfirm: { pending = action; isPresented = false })
                    .presentationBackground(.clear)
            }
    }
}

extension View {
    /// Review F-a M2/M3: „gerade nicht verfügbar“ – abgeschwächt, aber weiter fokussierbar (kein `.disabled`, damit der
    /// Fokus nicht springt, wenn sich eine Zeile unter ihm sperrt). Die Aktion muss selbst nichts tun.
    func settingsUnavailable(_ unavailable: Bool) -> some View {
        opacity(unavailable ? 0.5 : 1)
            .accessibilityHint(unavailable ? "Nicht verfügbar" : "")
    }

    /// E6/§2.4: Rückfrage vor Zerstörendem (Titel = Frage mit Objektname, Nachricht = Folge, Verb + „Behalten“).
    /// Zeigt `SettingsConfirmationView` als Vollbild-Überlagerung; „Behalten“ hat den Standardfokus.
    /// Die Aktion läuft erst nach dem Schließen: Werte, die `isPresented` steuern, sind dann schon zurückgesetzt –
    /// für solche Fälle die item-Variante nehmen.
    func settingsConfirmation(_ title: String, isPresented: Binding<Bool>, message: String, verb: String,
                              symbol: String = "trash", onKeep: (() -> Void)? = nil,
                              action: @escaping () -> Void) -> some View {
        modifier(SettingsConfirmationModifier(title: title, isPresented: isPresented, message: message, verb: verb,
                                              symbol: symbol, onKeep: onKeep, action: action))
    }

    /// Variante mit Objekt (z. B. „„X“ entfernen?“): zeigt die Rückfrage, solange `item` nicht nil ist.
    /// `action`/`onKeep` bekommen das Objekt aus dem Moment der Wahl.
    func settingsConfirmation<Item>(item: Binding<Item?>, title: @escaping (Item) -> String, message: @escaping (Item) -> String,
                                    verb: String, symbol: String = "trash", onKeep: ((Item) -> Void)? = nil,
                                    action: @escaping (Item) -> Void) -> some View {
        let current = item.wrappedValue
        let keep: (() -> Void)? = onKeep.map { f in { if let current { f(current) } } }
        return settingsConfirmation(current.map(title) ?? "",
                                    isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } }),
                                    message: current.map(message) ?? "", verb: verb, symbol: symbol,
                                    onKeep: keep) {
            if let current { action(current) }
        }
    }
}
