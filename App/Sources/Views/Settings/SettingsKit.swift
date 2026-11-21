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
    let content: Content

    init(pageTitle: String? = nil, title: String, summary: String? = nil, @ViewBuilder content: () -> Content) {
        self.pageTitle = pageTitle
        self.title = title
        self.summary = summary
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if let pageTitle {
                    Text(pageTitle).textRole(.pageTitle).accessibilityAddTraits(.isHeader)
                }
                SettingsHeader(title: title, summary: summary)
                    .padding(.bottom, Theme.Space.xs)
                content
            }
            .frame(maxWidth: Theme.Layout.contentMaxWidth, alignment: .leading)
            .padding(.vertical, Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollClipDisabled()
    }
}

/// Inhalt einer Kategorie: Seitentitel „Einstellungen“, Kategorietitel, Zusammenfassung aus `SettingsSummary`.
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
        SettingsPage(pageTitle: "Einstellungen", title: category.title, summary: summary) { content }
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

    init(symbol: String, tint: Color, title: String, detail: String? = nil, detailAlwaysVisible: Bool = false,
         options: [Value], selection: Binding<Value>, optionTint: ((Value) -> Color)? = nil,
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
    }

    var body: some View {
        if options.count <= 3 {
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

extension View {
    /// E6/§2.4: Rückfrage vor Zerstörendem. Titel = Frage mit Objektname, Nachricht = Folge,
    /// Knöpfe = Verb und „Behalten“ (Abbrechen-Rolle, damit Menu und der Standardfokus nichts löschen).
    func settingsConfirmation(_ title: String, isPresented: Binding<Bool>, message: String, verb: String,
                              action: @escaping () -> Void) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            Button(verb, role: .destructive, action: action)
            Button("Behalten", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}
