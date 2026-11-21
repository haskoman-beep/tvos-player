import SwiftUI

/// Sichtbares Fokusziel „Fertig“ bzw. „Zurück“ für Seiten ohne andere Fokusziele (N6, A4): Lade-, Fehler- und
/// QR-Seiten. Ohne fokussierbares Element feuert `onExitCommand` nicht zuverlässig; ein versteckter Knopf
/// (`Button {}.hidden()`) ist nicht fokussierbar und hilft deshalb nicht.
/// Ohne eigene Aktion schließt der Knopf die Seite (`dismiss`).
struct FocusAnchor: View {
    enum Kind {
        case done, back

        var title: String {
            switch self {
            case .done: "Fertig"
            case .back: "Zurück"
            }
        }

        var symbol: String {
            switch self {
            case .done: "checkmark"
            case .back: "chevron.left"
            }
        }

        var hint: String {
            switch self {
            case .done: "Schließt diese Seite."
            case .back: "Geht eine Ebene zurück."
            }
        }
    }

    var kind: Kind = .done
    /// Eigener Text statt „Fertig“/„Zurück“.
    var title: String? = nil
    /// Eigene Aktion; `nil` schließt die Seite.
    var action: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let text = title ?? kind.title
        Button {
            if let action { action() } else { dismiss() }
        } label: {
            Label(text, systemImage: kind.symbol)
                .font(Theme.TextRole.rowTitleEmphasis)
                .padding(.horizontal, Theme.Space.s)
        }
        .accessibilityLabel(text)
        .accessibilityHint(kind.hint)
    }
}

#Preview("Fokusanker") {
    VStack(spacing: Theme.Space.l) {
        Text("Scanne den QR-Code mit dem Handy.").textRole(.rowDetail)
        FocusAnchor()
        FocusAnchor(kind: .back)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .settingsSurface()
}
