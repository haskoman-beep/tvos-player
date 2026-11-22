import SwiftUI
import PlayerCore

/// Welle F-b2: Kontextmenü einer Startseiten-Reihe (langer Druck auf eine Kachel, Plan R6/N8):
/// „Reihe bearbeiten“ öffnet den Verwalter mit dieser Reihe, „Ganz nach oben“ setzt sie auf Platz 1,
/// „Ausblenden …“ fragt erst nach (die Startseite zeigt die Rückfrage).
struct HomeRowMenu {
    var canMoveUp: Bool
    var edit: () -> Void
    var moveToTop: () -> Void
    var hide: () -> Void
}

extension View {
    @ViewBuilder func homeRowMenu(_ menu: HomeRowMenu?) -> some View {
        if let menu {
            contextMenu {
                Button { menu.edit() } label: { Label("Reihe bearbeiten", systemImage: "slider.horizontal.3") }
                if menu.canMoveUp {
                    Button { menu.moveToTop() } label: { Label("Ganz nach oben", systemImage: "arrow.up.to.line") }
                }
                Button(role: .destructive) { menu.hide() } label: { Label("Ausblenden …", systemImage: "eye.slash") }
            }
        } else {
            self
        }
    }
}
