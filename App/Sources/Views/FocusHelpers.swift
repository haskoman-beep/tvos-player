import SwiftUI

extension View {
    /// Fokusziel ohne Fokusrahmen für Seiten, die (zeitweise) nur einen Hinweis zeigen.
    /// Ohne Fokusziel im Inhalt landet der Fokus nirgends (oder bleibt in der Seitenleiste), und tvOS wertet
    /// Zurück als „App verlassen“. Mit diesem Ziel führt Zurück wie in den anderen Bereichen in die Seitenleiste.
    /// Rückmeldung beim Fokus gibt `quietHintStyle()` im Label (Sekundärtext wird hell). `enabled == false`: unverändert.
    @ViewBuilder func quietFocusTarget(_ enabled: Bool = true) -> some View {
        if enabled {
            Button {} label: { self.frame(maxWidth: .infinity, alignment: .leading) }
                .buttonStyle(QuietFocusStyle())
        } else {
            self
        }
    }

    /// Hinweistext: sekundär, solange das umgebende Fokusziel (`quietFocusTarget`) nicht fokussiert ist, sonst primär.
    /// Außerhalb eines Fokusziels immer sekundär.
    func quietHintStyle() -> some View { modifier(QuietHintStyle()) }
}

/// Zeigt nur das Label: kein Fokusrahmen, kein Anheben. Text ohne eigenen Stil in Primärfarbe statt in der
/// Akzentfarbe, die ein Knopf seinem Label sonst gibt (RootView .tint).
private struct QuietFocusStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(HierarchicalShapeStyle.primary)
    }
}

private struct QuietHintStyle: ViewModifier {
    /// Fokus des nächsten fokussierbaren Vorfahren (hier der Knopf aus `quietFocusTarget`).
    @Environment(\.isFocused) private var focused

    func body(content: Content) -> some View {
        content.foregroundStyle(focused ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
    }
}
